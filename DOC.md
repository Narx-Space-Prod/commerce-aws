# Commerce AWS learning guide

This repository is a hands-on DevOps learning project. Read the handbooks in order; each starts with the big picture, teaches the concepts, then walks the relevant code and commands.

> **Last confirmed AWS state — 31 October 2026 (not re-inventoried on 1 November):** the last protected AWS destroy was partial. Its Terraform log reported 51 resources destroyed, including EKS, its node group, RDS, the VPC, queues and monitoring volumes. It then stopped on missing `iam:ListInstanceProfilesForRole` permission for eight workload roles. The narrow policy fix is merged in PR #37, but the AWS policy update and a fresh reviewed destroy plan are still needed before claiming cleanup is complete. `INFRA_ENABLED=false`. The application and ingress are disabled in `deploy/environment.yaml`; do not assume there is a live cluster, endpoint, database, load balancer or HTTPS shop. Bootstrap state/ECR/DNS resources and image digests are retained. `deploy/environment.yaml` still contains the former runtime/database secret ARNs, and `deploy/platform/ingress-values.yaml` contains the former VPC ID; treat those identifiers as stale after teardown. On the next cluster session, regenerate them with `scripts/platform.sh configure`, review the generated values, and merge an update before Argo install. The current AWS inventory and billing have not been refreshed in this documentation turn.

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

The handbooks are intentionally long. Use the table of contents in each file and read a real source file beside its explanation. Start with the trace-through sections and exercises; they are designed to build understanding step by step, not to serve only as a quick reference.

## How to study and prove understanding

Read each handbook's “Start here” chapter before its runbook. Keep the referenced code open beside it. Work through these milestones in order; advance when you can explain the evidence, not simply repeat the commands.

| Milestone | Exercise | Evidence of understanding |
|---|---|---|
| Source to artifact | Trace one frontend change through the workflow | Explain why source SHA, image digest and release commit differ |
| Infrastructure ownership | Draw the network/EKS/data module graph | Identify which objects Terraform owns and which controllers create |
| Identity | Follow one SQS worker credential request | Name the service account, Pod Identity role, trust and permission scope |
| Deployment | Render the Helm chart and inspect a Deployment | Explain selectors, probes, requests, limits, surge and HPA ownership |
| Operations | Trace a delayed order to its alert | Distinguish outbox failure, queue backlog, worker failure and notification failure |
| Recovery | Design a synthetic-data restore exercise | State the backup needed, expected data, measured RPO/RTO and cleanup owner |

For a hands-on exercise, record four things: your prediction, the command or reviewed change, the observed result, and your explanation if it differed. Keep synthetic exercise evidence private when it includes account metadata. Live AWS exercises require a deliberately provisioned session; reading, inspecting source and rendering examples can be done without creating cloud resources.

Completing these guides builds a strong foundation. Operational expertise also requires practicing diagnosis, recovery, review and communication over time. The documents label what is implemented, what remains to be configured and what has not been tested, so you can describe your experience accurately.

## Practise the decisions while reading

Each handbook now ends with a **Guided simulation**. These are fictional scenarios with illustrative evidence and worked answers; they are not claims that a live deployment, incident or restore occurred.

Follow this sequence to practise the skills without provisioning AWS:

1. Read the CI simulation and trace source → build → release → running image. Diagnose the old UI and choose a compatible rollback.
2. Read the AWS simulation and review an unexpected database replacement, classify an access failure, recover from partial teardown and plan recreation.
3. Read the Argo simulation and identify where a rollout stops: scheduling, secret readiness or desired-state reconciliation.
4. Read the integrations simulation and follow failed event publication, duplicate delivery, alert routing and backup verification.

Before reading an answer, write your next action and the evidence you expect it to produce. Compare your reasoning with the explanation. If your action would change a different layer from the one the evidence implicates, revisit the concept chapter. Finish by writing the incident note or ownership ledger requested at the end of the scenario.

This provides detailed rehearsal of operational reasoning within the document. Later hands-on practice establishes whether you can execute those decisions against a real system, including unexpected errors and time pressure.
