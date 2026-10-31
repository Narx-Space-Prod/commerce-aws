mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/commerce-aws-publisher-boundary" }
  }
}
variables {
  enable_production_subzone = false
  account_id                = "123456789012"
  aws_region                = "ap-south-1"
  state_bucket_name         = "commerce-aws-test-state"
  budget_email              = "operator@example.com"
  bootstrap_user_arn        = "arn:aws:iam::123456789012:user/commerce-operator"
}
run "scoped_mfa_bootstrap" {
  command = apply
  assert {
    condition = (
      jsondecode(aws_iam_role.bootstrap[0].assume_role_policy).Statement[0].Principal.AWS == var.bootstrap_user_arn &&
      jsondecode(aws_iam_role.bootstrap[0].assume_role_policy).Statement[0].Condition.Bool["aws:MultiFactorAuthPresent"] == "true" &&
      aws_iam_role.bootstrap[0].max_session_duration == 3600
    )
    error_message = "Only the named non-root user with MFA may obtain a one-hour bootstrap session."
  }
  assert {
    condition = (
      alltrue([for statement in jsondecode(local.bootstrap_writes).Statement : alltrue([for action in statement.Action : !endswith(action, "*")])]) &&
      alltrue([for statement in jsondecode(local.bootstrap_writes).Statement : alltrue([for resource in statement.Resource :
        resource != "*" || statement.Action == ["route53:CreateHostedZone"]
      ])])
    )
    error_message = "Bootstrap writes must use explicit actions and scoped resources, except Route 53 CreateHostedZone which requires Resource=*."
  }
  assert {
    condition = (
      jsondecode(local.bootstrap_writes).Statement[3].Action == ["route53:CreateHostedZone"] &&
      jsondecode(local.bootstrap_writes).Statement[3].Resource == ["*"] &&
      jsondecode(local.bootstrap_writes).Statement[4].Action == ["route53:ChangeTagsForResource"] &&
      alltrue([for statement in jsondecode(local.bootstrap_writes).Statement :
        !contains(statement.Action, "route53:DeleteHostedZone") &&
        !contains(statement.Action, "route53:ChangeResourceRecordSets")
      ])
    )
    error_message = "The bootstrap role may create and tag the retained DNS zone but must not delete zones or change DNS records."
  }
  assert {
    condition = (
      !contains(flatten([for statement in jsondecode(local.bootstrap_writes).Statement : statement.Action]), "iam:CreatePolicyVersion") &&
      !contains(flatten([for statement in jsondecode(local.bootstrap_writes).Statement : statement.Action]), "iam:DeleteRolePermissionsBoundary") &&
      alltrue([for statement in jsondecode(local.bootstrap_writes).Statement : !contains(statement.Resource, "arn:aws:iam::123456789012:role/commerce-aws-bootstrap")])
    )
    error_message = "Bootstrap cannot rewrite itself, modify boundary policies or remove the publisher's boundary."
  }
  assert {
    condition = (
      jsondecode(local.bootstrap_writes).Statement[6].Condition.StringEquals["iam:PermissionsBoundary"] == local.boundary_arn &&
      aws_iam_role.publisher.permissions_boundary == aws_iam_policy.publisher_boundary[0].arn &&
      alltrue([for statement in local.publisher_statements : alltrue([for action in statement.Action : startswith(action, "ecr:")])])
    )
    error_message = "The created publisher must retain its ECR-only permissions boundary."
  }
  assert {
    condition = alltrue([for statement in jsondecode(local.bootstrap_writes).Statement :
      alltrue([for action in statement.Action : !startswith(action, "ec2:") && !startswith(action, "eks:") && !startswith(action, "rds:")])
    ])
    error_message = "The foundation role must not create compute, Kubernetes clusters or databases."
  }
}
run "reject_root_bootstrap" {
  command = plan
  variables { bootstrap_user_arn = "arn:aws:iam::123456789012:root" }
  expect_failures = [var.bootstrap_user_arn]
}
run "reject_other_account" {
  command = plan
  variables { bootstrap_user_arn = "arn:aws:iam::999999999999:user/commerce-operator" }
  expect_failures = [var.bootstrap_user_arn]
}
