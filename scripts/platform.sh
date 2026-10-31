#!/usr/bin/env bash
# Run from the repository root after the AWS session exists. Never targets the local cluster.
set -euo pipefail
operation="${1:-}"
case "$operation" in prepare|configure|install|teardown) ;; *) echo 'Usage: bash scripts/platform.sh prepare|configure|install|teardown' >&2; exit 1 ;; esac
source deploy/platform/versions.env
chart_dir="$PWD/.work/platform-charts"
prepare_charts() {
  command -v helm > /dev/null
  command -v timeout > /dev/null
  mkdir -p "$chart_dir"
  while read -r chart version repository; do
    archive="$chart_dir/$chart-$version.tgz"
    if [ ! -f "$archive" ]; then
      echo "Downloading $chart $version before cluster installation..."
      downloaded=false
      for attempt in 1 2 3; do
        if timeout 120s helm pull "$chart" --repo "$repository" --version "$version" --destination "$chart_dir" > "$chart_dir/$chart-$version.download.log" 2>&1; then
          downloaded=true
          break
        fi
        echo "Download attempt $attempt failed for $chart."
      done
      if [ "$downloaded" != true ]; then
        echo "Chart download failed; inspect $chart_dir/$chart-$version.download.log and retry prepare." >&2
        return 1
      fi
    fi
    helm show chart "$archive" > /dev/null
  done <<CHARTS
argo-cd $ARGO_CHART https://argoproj.github.io/argo-helm
CHARTS
}
if [ "$operation" = prepare ]; then
  prepare_charts
  echo 'Pinned platform charts prepared. No AWS or Kubernetes resources created.'
  exit 0
fi
for tool in aws terraform kubectl helm jq python3; do command -v "$tool" > /dev/null; done
if [ "$operation" = configure ]; then
  mkdir -p .work
  umask 077
  terraform -chdir=infrastructure/session output -json | python3 -c '
import json, re, sys
from pathlib import Path
x=json.load(sys.stdin)
get=lambda key:x[key]["value"]
account=get("account_id"); region=get("region")
if get("cluster_name") != "commerce-aws" or not re.fullmatch(r"[0-9]{12}", account):
    raise SystemExit("Unexpected environment outputs")
values={"enabled":False,"region":region,"publicOrigin":"https://localhost","ingress":{"enabled":False},"runtimeSecretArn":get("runtime_secret_arn"),"databaseSecretArn":get("database_secret_arn")}
for key in ("runtimeSecretArn","databaseSecretArn"):
    if not values[key].startswith(f"arn:aws:secretsmanager:{region}:{account}:secret:"):
        raise SystemExit("Secret ARN does not belong to the expected account/region")
vpc=get("vpc_id")
if not re.fullmatch(r"vpc-[0-9a-f]+", vpc):
    raise SystemExit("Invalid VPC output")
controller={"clusterName":get("cluster_name"),"region":region,"vpcId":vpc,"enableCertManager":True,"serviceAccount":{"name":"aws-load-balancer-controller"},"defaultTags":{"Project":"commerce-aws","Environment":"learning"}}
Path(".work/environment.generated.json").write_text(json.dumps(values,indent=2)+"\n")
Path(".work/platform-ingress.generated.json").write_text(json.dumps(controller,indent=2)+"\n")
'
  echo 'Review .work/environment.generated.json and .work/platform-ingress.generated.json through a configuration PR. Workloads and ingress are disabled; HTTPS localhost is a placeholder until private TLS is configured.'
  exit 0
fi
if [ "$operation" = install ]; then prepare_charts; fi
readarray -t settings < <(terraform -chdir=infrastructure/session output -json | python3 -c '
import json,sys
x=json.load(sys.stdin)
for key in ["account_id", "region", "cluster_name", "vpc_id"]: print(x[key]["value"])
')
test "${#settings[@]}" = 4
account="${settings[0]}"
region="${settings[1]}"
cluster="${settings[2]}"
vpc="${settings[3]}"
test "$cluster" = commerce-aws
test "$(aws sts get-caller-identity --query Account --output text)" = "$account"
aws eks update-kubeconfig --name "$cluster" --region "$region" --alias commerce-aws > /dev/null
test "$(kubectl config current-context)" = commerce-aws
expected=$(aws eks describe-cluster --name "$cluster" --region "$region" --query cluster.endpoint --output text)
test "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" = "$expected"
if [ "$operation" = install ]; then
  # Reject stale or placeholder cluster values before bootstrapping controllers.
  CLUSTER="$cluster" REGION="$region" VPC="$vpc" python3 - <<'PYCODE'
import os, yaml
values=yaml.safe_load(open('deploy/platform/ingress-values.yaml'))
expected={'clusterName':os.environ['CLUSTER'],'region':os.environ['REGION'],'vpcId':os.environ['VPC']}
if any(values.get(key) != value for key,value in expected.items()):
    raise SystemExit('Platform ingress values do not match Terraform outputs; generate and merge the configuration PR first.')
PYCODE
  kubectl --context commerce-aws wait --for=condition=Ready nodes --all --timeout=10m
  if [ -z "$(kubectl --context commerce-aws get namespace monitoring --ignore-not-found -o name)" ]; then
    kubectl --context commerce-aws create namespace monitoring
  fi
  # Seed these private inputs once. The baseline Application subsequently owns the namespace.
  python3 scripts/secrets.py grafana
  python3 scripts/secrets.py slack
  helm upgrade --install argocd "$chart_dir/argo-cd-$ARGO_CHART.tgz" --kube-context commerce-aws -n argocd --create-namespace -f deploy/platform/argo-values.yaml --atomic --wait --timeout 10m
  kubectl --context commerce-aws wait --for=condition=Established --timeout=5m crd/applications.argoproj.io
  kubectl --context commerce-aws apply -f deploy/platform-root.yaml
  python3 - <<'PYCODE'
import json, subprocess, time
names=['platform-baseline','platform-cert-manager','platform-external-secrets','platform-metrics-server','platform-ingress','platform-monitoring']
deadline=time.monotonic()+1200
while time.monotonic() < deadline:
    pending=[]
    for name in names:
        result=subprocess.run(['kubectl','--context','commerce-aws','-n','argocd','get','application',name,'--ignore-not-found','-o','json'],capture_output=True,text=True)
        if result.returncode:
            raise SystemExit('Cannot read platform Application status: '+name)
        obj=json.loads(result.stdout) if result.stdout.strip() else {}
        status=obj.get('status',{})
        if status.get('sync',{}).get('status')!='Synced' or status.get('health',{}).get('status')!='Healthy':
            pending.append(name)
    if not pending:
        print('Platform Applications are Synced and Healthy.'); break
    print('Waiting for platform: '+', '.join(pending),flush=True)
    time.sleep(10)
else:
    raise SystemExit('Platform readiness timed out; inspect Argo Application conditions and pod events.')
PYCODE
  kubectl --context commerce-aws wait --for=condition=Established --timeout=5m crd/externalsecrets.external-secrets.io crd/secretstores.external-secrets.io crd/servicemonitors.monitoring.coreos.com crd/prometheusrules.monitoring.coreos.com
  kubectl --context commerce-aws apply -f deploy/argocd.yaml
  echo 'Platform reconciled by Argo CD. Application configuration and business health require separate verification.'
else
  test "${CONFIRM_DESTROY:-}" = 'destroy commerce-aws' || { echo 'Set CONFIRM_DESTROY="destroy commerce-aws" after reviewing backup and teardown in DOC.md.' >&2; exit 1; }
  # Parent has no cascade finalizer: stop it recreating children, preserve ordered cleanup.
  kubectl --context commerce-aws -n argocd delete application platform-root --ignore-not-found --wait=true --timeout=5m
  for application in platform-baseline platform-cert-manager platform-external-secrets platform-metrics-server platform-ingress platform-monitoring; do
    if [ -n "$(kubectl --context commerce-aws -n argocd get application "$application" --ignore-not-found -o name)" ]; then
      kubectl --context commerce-aws -n argocd patch application "$application" --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
    fi
  done
  kubectl --context commerce-aws -n argocd delete application commerce --ignore-not-found --wait=true --timeout=5m
  kubectl --context commerce-aws -n commerce delete ingress commerce --ignore-not-found --wait=true --timeout=10m
  kubectl --context commerce-aws delete namespace commerce --ignore-not-found --wait=true --timeout=10m
  kubectl --context commerce-aws -n argocd delete application platform-monitoring --ignore-not-found --wait=true --timeout=10m
  kubectl --context commerce-aws -n monitoring delete pvc --all --wait=true --timeout=10m
  for application in platform-external-secrets platform-metrics-server platform-ingress platform-cert-manager platform-baseline; do
    kubectl --context commerce-aws -n argocd delete application "$application" --ignore-not-found --wait=true --timeout=10m
  done
  helm uninstall argocd --kube-context commerce-aws -n argocd --ignore-not-found --wait --timeout 10m
  echo 'Ordered GitOps teardown complete. Inspect ALBs, target groups, ENIs and EBS before Terraform destroy.'
fi
