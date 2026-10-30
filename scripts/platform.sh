#!/usr/bin/env bash
# Run from the repository root after the AWS session exists. Never targets the local cluster.
set -euo pipefail
operation="${1:-}"
case "$operation" in install|teardown) ;; *) echo 'Usage: bash scripts/platform.sh install|teardown' >&2; exit 1 ;; esac
for tool in aws terraform kubectl helm jq; do command -v "$tool" > /dev/null; done
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
source deploy/platform/versions.env
if [ "$operation" = install ]; then
  kubectl --context commerce-aws apply -f deploy/platform/storage.yaml
  kubectl --context commerce-aws create namespace monitoring --dry-run=client -o yaml | kubectl --context commerce-aws apply -f -
  # Secret helper prompts safely and preserves existing values.
  python3 scripts/secrets.py grafana
  if ! kubectl --context commerce-aws -n monitoring get secret slack-notifications > /dev/null 2>&1; then
    echo 'Configure the dedicated Slack webhook before installing Alertmanager.'
    python3 scripts/secrets.py slack
  fi
  helm upgrade --install external-secrets external-secrets --repo https://charts.external-secrets.io --version "$SECRETS_CHART" --kube-context commerce-aws -n external-secrets --create-namespace --set serviceAccount.name=external-secrets --wait --timeout 10m
  helm upgrade --install metrics-server metrics-server --repo https://kubernetes-sigs.github.io/metrics-server --version "$METRICS_CHART" --kube-context commerce-aws -n kube-system --wait --timeout 10m
  helm upgrade --install aws-load-balancer-controller aws-load-balancer-controller --repo https://aws.github.io/eks-charts --version "$INGRESS_CHART" --kube-context commerce-aws -n kube-system --set "clusterName=$cluster" --set "region=$region" --set "vpcId=$vpc" --set serviceAccount.name=aws-load-balancer-controller --set defaultTags.Project=commerce-aws --set defaultTags.Environment=learning --wait --timeout 10m
  helm upgrade --install monitoring kube-prometheus-stack --repo https://prometheus-community.github.io/helm-charts --version "$MONITORING_CHART" --kube-context commerce-aws -n monitoring -f deploy/platform/monitoring-values.yaml --wait --timeout 15m
  helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version "$ARGO_CHART" --kube-context commerce-aws -n argocd --create-namespace -f deploy/platform/argo-values.yaml --wait --timeout 10m
  kubectl --context commerce-aws apply -f deploy/argocd.yaml
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
