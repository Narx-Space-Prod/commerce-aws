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
external-secrets $SECRETS_CHART https://charts.external-secrets.io
metrics-server $METRICS_CHART https://kubernetes-sigs.github.io/metrics-server
aws-load-balancer-controller $INGRESS_CHART https://aws.github.io/eks-charts
kube-prometheus-stack $MONITORING_CHART https://prometheus-community.github.io/helm-charts
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
Path(".work/environment.generated.json").write_text(json.dumps(values,indent=2)+"\n")
'
  echo 'Review .work/environment.generated.json through a configuration PR. Workloads and ingress are disabled; HTTPS localhost is a placeholder until private TLS is configured.'
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
  kubectl --context commerce-aws wait --for=condition=Ready nodes --all --timeout=10m
  kubectl --context commerce-aws apply -f deploy/platform/storage.yaml
  kubectl --context commerce-aws create namespace monitoring --dry-run=client -o yaml | kubectl --context commerce-aws apply -f -
  # Secret helper prompts safely and preserves existing values.
  python3 scripts/secrets.py grafana
  python3 scripts/secrets.py slack
  helm upgrade --install external-secrets "$chart_dir/external-secrets-$SECRETS_CHART.tgz" --kube-context commerce-aws -n external-secrets --create-namespace --set serviceAccount.name=external-secrets --atomic --wait --timeout 10m
  helm upgrade --install metrics-server "$chart_dir/metrics-server-$METRICS_CHART.tgz" --kube-context commerce-aws -n kube-system --atomic --wait --timeout 10m
  helm upgrade --install aws-load-balancer-controller "$chart_dir/aws-load-balancer-controller-$INGRESS_CHART.tgz" --kube-context commerce-aws -n kube-system --set "clusterName=$cluster" --set "region=$region" --set "vpcId=$vpc" --set serviceAccount.name=aws-load-balancer-controller --set defaultTags.Project=commerce-aws --set defaultTags.Environment=learning --atomic --wait --timeout 10m
  helm upgrade --install monitoring "$chart_dir/kube-prometheus-stack-$MONITORING_CHART.tgz" --kube-context commerce-aws -n monitoring -f deploy/platform/monitoring-values.yaml --atomic --wait --timeout 15m
  helm upgrade --install argocd "$chart_dir/argo-cd-$ARGO_CHART.tgz" --kube-context commerce-aws -n argocd --create-namespace -f deploy/platform/argo-values.yaml --atomic --wait --timeout 10m
  kubectl --context commerce-aws wait --for=condition=Established --timeout=5m crd/externalsecrets.external-secrets.io crd/secretstores.external-secrets.io crd/servicemonitors.monitoring.coreos.com crd/prometheusrules.monitoring.coreos.com crd/applications.argoproj.io
  kubectl --context commerce-aws apply -f deploy/argocd.yaml
  kubectl --context commerce-aws -n argocd rollout status deployment/argocd-server --timeout=5m
  echo 'Platform readiness checks passed. Application sync and business health still require separate verification.'
  echo 'Platform installed. Review deploy/environment.yaml and a signed release before enabling the app.'
else
  test "${CONFIRM_DESTROY:-}" = 'destroy commerce-aws' || { echo 'Set CONFIRM_DESTROY="destroy commerce-aws" after reviewing the backup and teardown steps in DOC.md.' >&2; exit 1; }
  # Stop reconciliation before deleting resources; keep the ALB controller until its finalizers finish.
  kubectl --context commerce-aws -n argocd delete application commerce --ignore-not-found
  kubectl --context commerce-aws -n commerce delete ingress commerce --ignore-not-found --wait=true --timeout=10m
  kubectl --context commerce-aws delete namespace commerce --ignore-not-found --wait=true --timeout=10m
  helm uninstall monitoring --kube-context commerce-aws -n monitoring --ignore-not-found --wait --timeout 10m
  kubectl --context commerce-aws -n monitoring delete pvc --all --wait=true --timeout=10m
  for item in 'argocd argocd' 'external-secrets external-secrets' 'metrics-server kube-system' 'aws-load-balancer-controller kube-system'; do
    read -r release namespace <<< "$item"
    helm uninstall "$release" --kube-context commerce-aws -n "$namespace" --ignore-not-found --wait --timeout 10m
  done
  echo 'Kubernetes cleanup complete. Inspect ALBs, ENIs and EBS volumes before approving Terraform destroy.'
fi
