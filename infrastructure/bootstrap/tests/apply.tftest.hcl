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
  assert {
    condition = (
      length([for statement in local.apply_ec2_statements : statement if contains(statement.Action, "ec2:RunInstances")]) == 3 &&
      alltrue([for statement in local.apply_ec2_statements : !contains(statement.Resource, "*")]) &&
      alltrue([for statement in local.apply_ec2_statements : (
        !contains(statement.Action, "ec2:RunInstances") ||
        try(statement.Condition.StringEquals["aws:ResourceTag/Project"] == "commerce-aws", false) ||
        try(statement.Condition.ArnLike["ec2:LaunchTemplate"] == "arn:aws:ec2:ap-south-1:123456789012:launch-template/*", false)
      )])
    )
    error_message = "Worker launch permissions require project-tagged templates and regional template-based launch inputs, never unrestricted EC2 resources."
  }
  assert {
    condition = (
      length([for statement in local.apply_ec2_statements : statement if
        try(statement.Sid == "LaunchTaggedWorkerResources", false) &&
        try(statement.Condition.StringEquals["aws:RequestTag/Project"] == "commerce-aws", false)
      ]) == 1 &&
      length([for statement in local.apply_ec2_statements : statement if
        try(statement.Sid == "TagWorkerResourcesAtLaunch", false) &&
        try(statement.Condition.StringEquals["ec2:CreateAction"] == "RunInstances", false)
      ]) == 1
    )
    error_message = "Generated worker resources must carry ownership tags; additional tag rights apply only during RunInstances."
  }
  assert {
    condition = (
      contains(jsondecode(local.plan_permissions).Statement[1].Action, "secretsmanager:GetResourcePolicy") &&
      jsondecode(local.plan_permissions).Statement[1].Resource == "arn:aws:secretsmanager:ap-south-1:123456789012:secret:commerce-aws-runtime-*" &&
      !contains(jsondecode(local.plan_permissions).Statement[0].Action, "secretsmanager:GetResourcePolicy") &&
      contains(jsondecode(local.apply_policy_documents.read).Statement[1].Action, "secretsmanager:GetResourcePolicy")
    )
    error_message = "Both Terraform identities need secret-policy reads scoped to this project's runtime secrets."
  }

}
