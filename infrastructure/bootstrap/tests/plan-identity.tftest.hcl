mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock-policy" }
  }
}
variables {
  enable_production_subzone         = false
  account_id                        = "123456789012"
  aws_region                        = "ap-south-1"
  state_bucket_name                 = "commerce-aws-test-state"
  budget_email                      = "operator@example.com"
  existing_github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}
run "plan_identity_is_constrained" {
  command = plan
  assert {
    condition = (
      jsondecode(local.plan_trust).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com" &&
      jsondecode(local.plan_trust).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:ref"] == "refs/heads/main" &&
      jsondecode(local.plan_trust).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:Narx-Space-Prod@346206471/commerce-aws@1439227210:environment:infrastructure-plan"
    )
    error_message = "Only the infrastructure-plan environment can assume the role."
  }
  assert {
    condition = alltrue(flatten([for s in jsondecode(local.plan_permissions).Statement : [for a in s.Action :
      !startswith(a, "iam:Create") && !startswith(a, "iam:Put") && !startswith(a, "eks:Create") && !startswith(a, "ec2:Create") && !startswith(a, "rds:Create")
    ]]))
    error_message = "The plan role must not create infrastructure or change IAM."
  }
  assert {
    condition = alltrue([for s in jsondecode(local.plan_permissions).Statement :
      !contains(s.Action, "s3:PutObject") || !contains(try(tolist(s.Resource), [s.Resource]), "arn:aws:s3:::commerce-aws-test-state/session/terraform.tfstate")
    ])
    error_message = "The plan role cannot overwrite session state."
  }
}
