# Commerce AWS learning guide

This repository is a hands-on DevOps learning project. Read the handbooks in order; each starts with the big picture, teaches the concepts, then walks the relevant code and commands.

> **State of the lab — 31 October 2026:** the last protected AWS destroy was partial. Its Terraform log reported 51 resources destroyed, including EKS, its node group, RDS, the VPC, queues and monitoring volumes. It then stopped on missing `iam:ListInstanceProfilesForRole` permission for eight workload roles. The narrow policy fix is merged in PR #37, but the AWS policy update and a fresh reviewed destroy plan are still needed before claiming cleanup is complete. `INFRA_ENABLED=false`. The application and ingress are disabled in `deploy/environment.yaml`; do not assume there is a live cluster, endpoint, database, load balancer or HTTPS shop. Bootstrap state/ECR/DNS resources and image digests are retained. The current AWS inventory and billing have not been refreshed in this documentation turn.

## The four handbooks

1. [CI/CD: from pull request to GitOps release](docs/01-CI-CD.md) — developer workflow, checks, reusable image build, security evidence, OIDC publishing, release PR, and pipeline code tour.
2. [AWS and Terraform: account to infrastructure](docs/02-AWS-TERRAFORM.md) — architecture, AWS services, network, IAM roles/policies, Terraform module tour, safe setup, operations, costs and teardown.
3. [Argo CD: GitOps and Kubernetes delivery](docs/03-ARGO-CD.md) — desired state, Applications/AppProjects, Helm chart values, bootstrap, reconcile/debug commands and ordered removal.
4. [Integrations: monitoring, messaging, secrets and operations](docs/04-INTEGRATIONS.md) — Prometheus/Grafana/Alertmanager, Slack/SNS, SQS, Secrets Manager, DNS/TLS, database recovery and practical incident exercises.

## Suggested learning path

- Start with the CI/CD handbook and trace one change from a feature branch to an immutable image digest and reviewed deployment PR.
- Read the AWS/Terraform handbook before creating cloud resources. Learn identity and inspect a plan before applying anything.
- Follow the Argo CD handbook only when a cluster exists and the bootstrap workflow is deliberately enabled.
- Use the integrations handbook to understand alerts, secrets, queues, backups and operational failure modes.
- For any live AWS work, confirm the account, region, budget and current inventory first. A Terraform plan is a proposal, not a safety guarantee; review every create, update and destroy.

## Ground rules

The handbooks describe both the architecture encoded in this repository and the lab's current state. “Designed/configured in code” does not mean “currently running.” Commands that create, modify, or delete cloud resources are clearly marked. Prefer the protected GitHub Actions infrastructure workflow and its saved plan/approval flow; do not run an unreviewed local `terraform apply`. Never commit credentials, paste MFA codes or expose `.work` files. EKS, public IPv4, RDS, load balancers, storage and data transfer can cost money. Budgets notify; they do not cap spending.

This is a learning replica of common production practices, not a claim of production readiness or high availability. Its single-node, single-AZ data profile intentionally trades resilience for lab cost. The handbooks explain the tradeoffs and how to discuss them in an interview.
