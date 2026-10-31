// Snapshots reviewed 2026-10-31: EKSCluster v10, EKSWorkerNode v3,
// ECRPullOnly v1, EKS_CNI v6 and EBSCSIDriver v15. Refresh through review.
locals {
  workload_boundaries = merge(jsondecode(file("${path.module}/workload-boundary-policies.json")), {
    ingress = jsondecode(file("${path.module}/../session/policies/load-balancer.json"))
    session-publisher = { Version = "2012-10-17", Statement = [{
      Effect = "Allow", Action = ["sqs:SendMessage"], Resource = "arn:aws:sqs:${var.aws_region}:${var.account_id}:commerce-aws-order-paid"
    }] }
    session-worker = { Version = "2012-10-17", Statement = [{
      Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility"], Resource = "arn:aws:sqs:${var.aws_region}:${var.account_id}:commerce-aws-order-paid"
    }] }
    secrets = { Version = "2012-10-17", Statement = [{
      Effect   = "Allow", Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
      Resource = ["arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:commerce-aws-runtime-*", "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:rds!db-*"]
    }] }
  })
}
resource "aws_iam_policy" "workload_boundary" {
  for_each    = local.workload_boundaries
  name        = "commerce-aws-${each.key}-boundary"
  description = "Maximum permissions for the Commerce ${each.key} workload role"
  policy      = jsonencode(each.value)
  lifecycle {
    precondition {
      condition     = length(jsonencode(each.value)) <= 6144
      error_message = "A workload boundary exceeds the IAM managed-policy size limit."
    }
  }
}
