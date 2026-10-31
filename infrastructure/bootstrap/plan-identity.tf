// The plan identity can inspect infrastructure and write a saved plan, but it
// cannot apply changes or overwrite the Terraform state.
locals {
  plan_trust = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRoleWithWebIdentity", Principal = { Federated = local.provider_arn },
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub" = "repo:${local.repository_subject}:environment:infrastructure-plan",
      "token.actions.githubusercontent.com:ref" = "refs/heads/main"
    } }
  }] })
  plan_permissions = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Resource = "*", Action = [
      "ec2:Describe*", "eks:Describe*", "eks:List*", "rds:Describe*", "rds:ListTagsForResource",
      "autoscaling:Describe*", "cloudwatch:Describe*", "cloudwatch:ListTagsForResource",
      "logs:DescribeLogGroups", "logs:ListTagsForResource", "iam:GetRole", "iam:GetRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:GetPolicy", "iam:GetPolicyVersion",
      "kms:DescribeKey", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListResourceTags",
      "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ListQueueTags", "sns:GetTopicAttributes",
      "sns:GetSubscriptionAttributes", "sns:ListTagsForResource", "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds", "acm:DescribeCertificate", "route53:GetHostedZone",
      "route53:ListResourceRecordSets", "route53:GetChange", "tag:GetResources"
    ] },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "secretsmanager:GetResourcePolicy"], Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:commerce-aws-runtime-*" },
    { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:GetBucketVersioning"], Resource = "arn:aws:s3:::${var.state_bucket_name}" },
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = "arn:aws:s3:::${var.state_bucket_name}", Condition = { StringLike = { "s3:prefix" = ["session/terraform.tfstate", "session/terraform.tfstate.tflock", "plans/*"] } } },
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = ["arn:aws:s3:::${var.state_bucket_name}/session/terraform.tfstate", "arn:aws:s3:::${var.state_bucket_name}/session/terraform.tfstate.tflock"] },
    { Effect = "Allow", Action = ["s3:PutObject", "s3:DeleteObject"], Resource = "arn:aws:s3:::${var.state_bucket_name}/session/terraform.tfstate.tflock" },
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = "arn:aws:s3:::${var.state_bucket_name}/plans/*" }
  ] })
}

resource "aws_iam_role" "plan" {
  name               = "commerce-aws-plan"
  assume_role_policy = local.plan_trust
}

resource "aws_iam_role_policy" "plan" {
  name   = "commerce-aws-plan"
  role   = aws_iam_role.plan.id
  policy = local.plan_permissions
}

output "plan_role_arn" { value = aws_iam_role.plan.arn }
