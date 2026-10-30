# Commerce AWS

One application, one AWS learning environment, one repository.

Terraform provisions EKS, VPC networking, private RDS PostgreSQL, SQS/DLQ,
Secrets Manager, Pod Identity, CloudWatch alarms and a budget. GitHub Actions
tests and scans changed images, publishes signed immutable ECR releases and
opens a reviewed deployment PR. Argo CD reconciles Helm configuration.
Prometheus, Grafana and Alertmanager provide runtime monitoring and Slack alerts.

Start with [DOC.md](DOC.md): architecture, setup, commands, exercises,
cost choices, teardown and the limits of the learning profile.

**AWS provisioning and image publishing start disabled.** The checked-in app
configuration creates no workloads until AWS configuration and a release are reviewed.
Existing local projects and repositories are independent and untouched.
