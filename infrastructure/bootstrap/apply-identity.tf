locals {
  apply_trust = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRoleWithWebIdentity", Principal = { Federated = local.provider_arn },
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub" = "repo:${local.repository_subject}:environment:infrastructure-apply",
      "token.actions.githubusercontent.com:ref" = "refs/heads/main"
    } }
  }] })
  session_roles = { for key in keys(local.workload_boundaries) : key => "arn:aws:iam::${var.account_id}:role/commerce-aws-${key}" }
  managed_workload_policies = {
    cluster = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]
    node    = ["arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy", "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"]
    cni     = ["arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"]
    storage = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
  }
  apply_iam_statements = concat(
    [for key, arn in local.session_roles : {
      Sid       = "Create${replace(key, "-", "")}Role", Effect = "Allow", Action = ["iam:CreateRole"], Resource = [arn],
      Condition = { StringEquals = { "iam:PermissionsBoundary" = "arn:aws:iam::${var.account_id}:policy/commerce-aws-${key}-boundary" } }
    }],
    [for key, policies in local.managed_workload_policies : {
      Effect    = "Allow", Action = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"], Resource = [local.session_roles[key]],
      Condition = { ArnEquals = { "iam:PolicyARN" = policies } }
    }],
    [{ Effect = "Allow", Action = ["iam:DeleteRole", "iam:TagRole", "iam:UntagRole"], Resource = values(local.session_roles) },
      # The AWS provider checks role instance profiles before DeleteRole. Keep
      # that read scoped to the exact workload roles managed by this session.
      { Sid = "ListProfilesForSessionRoles", Effect = "Allow", Action = ["iam:ListInstanceProfilesForRole"], Resource = values(local.session_roles) },
      { Effect = "Allow", Action = ["iam:PutRolePolicy", "iam:DeleteRolePolicy"], Resource = [for key in ["session-publisher", "session-worker", "secrets", "ingress"] : local.session_roles[key]] },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = [local.session_roles.cluster, local.session_roles.node], Condition = { StringEquals = { "iam:PassedToService" = ["eks.amazonaws.com", "ec2.amazonaws.com"] } } },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = [for key in ["cni", "storage", "session-publisher", "session-worker", "secrets", "ingress"] : local.session_roles[key]], Condition = { StringEquals = { "iam:PassedToService" = "pods.eks.amazonaws.com" } } },
      { Effect = "Allow", Action = ["iam:CreateServiceLinkedRole"], Resource = [for service in ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "rds.amazonaws.com", "autoscaling.amazonaws.com", "elasticloadbalancing.amazonaws.com"] : "arn:aws:iam::${var.account_id}:role/aws-service-role/${service}/*"], Condition = { StringEquals = { "iam:AWSServiceName" = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "rds.amazonaws.com", "autoscaling.amazonaws.com", "elasticloadbalancing.amazonaws.com"] } } }
  ])
  session_s3 = "arn:aws:s3:::${var.state_bucket_name}/session/terraform.tfstate"
  apply_storage_statements = [
    { Effect = "Allow", Action = ["s3:GetBucketLocation"], Resource = ["arn:aws:s3:::${var.state_bucket_name}"] },
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = ["arn:aws:s3:::${var.state_bucket_name}"], Condition = { StringLike = { "s3:prefix" = ["session/terraform.tfstate", "session/terraform.tfstate.tflock", "plans/*"] } } },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = [local.session_s3, "${local.session_s3}.tflock"] },
    { Effect = "Allow", Action = ["s3:DeleteObject"], Resource = ["${local.session_s3}.tflock"] },
    { Effect = "Allow", Action = ["s3:GetObjectVersion"], Resource = ["arn:aws:s3:::${var.state_bucket_name}/plans/*"] }
  ]
}

resource "aws_iam_role" "apply" {
  name                 = "commerce-aws-apply"
  assume_role_policy   = local.apply_trust
  max_session_duration = 7200
}
resource "aws_iam_policy" "apply" {
  for_each = local.apply_policy_documents
  name     = "commerce-aws-apply-${each.key}"
  policy   = each.value
  lifecycle {
    precondition {
      condition     = length(each.value) <= 6144
      error_message = "Apply policy exceeds the IAM managed-policy limit."
    }
  }
}
resource "aws_iam_role_policy_attachment" "apply" {
  for_each   = aws_iam_policy.apply
  role       = aws_iam_role.apply.name
  policy_arn = each.value.arn
}
output "apply_role_arn" { value = aws_iam_role.apply.arn }
