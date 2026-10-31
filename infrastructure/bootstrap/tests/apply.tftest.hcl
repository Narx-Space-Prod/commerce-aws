mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock-policy" }
  }
}
variables {
  account_id        = "123456789012"
  budget_email      = "operator@example.com"
  aws_region        = "ap-south-1"
  state_bucket_name = "commerce-aws-test-state"
}
run "constrained_apply" {
  command = apply
  assert {
    condition = (
      jsondecode(aws_iam_role.apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:Narx-Space-Prod@346206471/commerce-aws@1439227210:environment:infrastructure-apply" &&
      jsondecode(aws_iam_role.apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:ref"] == "refs/heads/main" &&
      aws_iam_role.apply.max_session_duration == 7200
    )
    error_message = "Apply must use the protected main environment and cover the job duration."
  }
  assert {
    condition = alltrue([for key, arn in local.session_roles :
      length([for s in local.apply_iam_statements : s if contains(s.Action, "iam:CreateRole") && contains(s.Resource, arn) && try(s.Condition.StringEquals["iam:PermissionsBoundary"], "") == "arn:aws:iam::123456789012:policy/commerce-aws-${key}-boundary"]) == 1
    ])
    error_message = "Role creation must require that role's own boundary."
  }
  assert {
    condition = alltrue([for s in local.apply_iam_statements :
      !contains(s.Action, "iam:UpdateAssumeRolePolicy") && !contains(s.Action, "iam:PutRolePermissionsBoundary") && !contains(s.Action, "iam:DeleteRolePermissionsBoundary") && !contains(s.Action, "iam:CreatePolicyVersion") &&
      !contains(s.Resource, "arn:aws:iam::123456789012:role/commerce-aws-apply") && !contains(s.Resource, "arn:aws:iam::123456789012:role/commerce-aws-bootstrap") && !contains(s.Resource, "arn:aws:iam::123456789012:role/commerce-aws-publisher")
    ])
    error_message = "Apply must not rewrite trusts, boundaries or protected identities."
  }
  assert {
    condition = alltrue([for s in local.apply_storage_statements :
      !contains(s.Resource, "arn:aws:s3:::commerce-aws-test-state/bootstrap/terraform.tfstate")
    ])
    error_message = "The apply role must not write bootstrap state."
  }
}
