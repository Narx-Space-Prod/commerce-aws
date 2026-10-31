locals {
  regional         = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
  new_project      = { StringEquals = { "aws:RequestedRegion" = var.aws_region, "aws:RequestTag/Project" = "commerce-aws" } }
  existing_project = { StringEquals = { "aws:RequestedRegion" = var.aws_region, "aws:ResourceTag/Project" = "commerce-aws" } }
  ec2_resources    = [for kind in ["vpc", "subnet", "internet-gateway", "route-table", "security-group", "security-group-rule", "launch-template"] : "arn:aws:ec2:${var.aws_region}:${var.account_id}:${kind}/*"]
  apply_ec2_statements = [
    { Effect = "Allow", Resource = local.ec2_resources, Condition = local.new_project, Action = ["ec2:CreateVpc", "ec2:CreateSubnet", "ec2:CreateInternetGateway", "ec2:CreateRouteTable", "ec2:CreateSecurityGroup", "ec2:CreateLaunchTemplate", "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress"] },
    { Effect = "Allow", Resource = local.ec2_resources, Condition = local.existing_project, Action = [
      "ec2:CreateSubnet", "ec2:CreateRouteTable", "ec2:CreateSecurityGroup", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DeleteInternetGateway", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:ReplaceRoute", "ec2:DeleteRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:ReplaceRouteTableAssociation", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress", "ec2:ModifySecurityGroupRules", "ec2:DeleteLaunchTemplate", "ec2:CreateLaunchTemplateVersion", "ec2:DeleteLaunchTemplateVersions", "ec2:ModifyLaunchTemplate", "ec2:CreateTags"
    ] },
    { Effect = "Allow", Action = ["ec2:CreateTags"], Resource = local.ec2_resources, Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region, "aws:RequestTag/Project" = "commerce-aws", "ec2:CreateAction" = ["CreateVpc", "CreateSubnet", "CreateInternetGateway", "CreateRouteTable", "CreateSecurityGroup", "CreateLaunchTemplate", "AuthorizeSecurityGroupIngress", "AuthorizeSecurityGroupEgress"] } } }
  ]
  eks_resources = ["arn:aws:eks:${var.aws_region}:${var.account_id}:cluster/commerce-aws", "arn:aws:eks:${var.aws_region}:${var.account_id}:nodegroup/commerce-aws/*", "arn:aws:eks:${var.aws_region}:${var.account_id}:addon/commerce-aws/*", "arn:aws:eks:${var.aws_region}:${var.account_id}:access-entry/commerce-aws/*", "arn:aws:eks:${var.aws_region}:${var.account_id}:podidentityassociation/commerce-aws/*"]
  apply_eks_statements = [{ Effect = "Allow", Resource = local.eks_resources, Condition = local.regional, Action = [
    "eks:CreateCluster", "eks:DeleteCluster", "eks:UpdateClusterConfig", "eks:UpdateClusterVersion", "eks:TagResource", "eks:UntagResource",
    "eks:CreateNodegroup", "eks:DeleteNodegroup", "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion", "eks:CreateAddon", "eks:UpdateAddon", "eks:DeleteAddon",
    "eks:CreateAccessEntry", "eks:UpdateAccessEntry", "eks:DeleteAccessEntry", "eks:AssociateAccessPolicy", "eks:DisassociateAccessPolicy",
    "eks:CreatePodIdentityAssociation", "eks:UpdatePodIdentityAssociation", "eks:DeletePodIdentityAssociation"
  ] }]
  runtime_secrets = "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:commerce-aws-runtime-*"
  apply_data_statements = [
    { Effect = "Allow", Resource = ["arn:aws:rds:${var.aws_region}:${var.account_id}:db:commerce-aws", "arn:aws:rds:${var.aws_region}:${var.account_id}:subgrp:commerce-aws", "arn:aws:rds:${var.aws_region}:${var.account_id}:pg:commerce-aws-*"], Condition = local.regional, Action = [
      "rds:CreateDBInstance", "rds:DeleteDBInstance", "rds:ModifyDBInstance", "rds:CreateDBSubnetGroup", "rds:ModifyDBSubnetGroup", "rds:DeleteDBSubnetGroup", "rds:CreateDBParameterGroup", "rds:ModifyDBParameterGroup", "rds:DeleteDBParameterGroup", "rds:AddTagsToResource", "rds:RemoveTagsFromResource"
    ] },
    { Effect = "Allow", Resource = ["arn:aws:sqs:${var.aws_region}:${var.account_id}:commerce-aws-order-paid", "arn:aws:sqs:${var.aws_region}:${var.account_id}:commerce-aws-dead-letter"], Condition = local.regional, Action = ["sqs:CreateQueue", "sqs:DeleteQueue", "sqs:SetQueueAttributes", "sqs:TagQueue", "sqs:UntagQueue"] },
    { Effect = "Allow", Resource = [local.runtime_secrets], Condition = local.regional, Action = ["secretsmanager:CreateSecret", "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret", "secretsmanager:DeleteSecret", "secretsmanager:TagResource", "secretsmanager:UntagResource"] },
    { Effect = "Allow", Resource = ["arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:rds!db-*"], Condition = local.regional, Action = ["secretsmanager:CreateSecret", "secretsmanager:TagResource"] },
    { Effect = "Allow", Resource = ["*"], Condition = local.new_project, Action = ["kms:CreateKey"] },
    { Effect = "Allow", Resource = ["arn:aws:kms:${var.aws_region}:${var.account_id}:key/*"], Condition = local.existing_project, Action = ["kms:PutKeyPolicy", "kms:EnableKeyRotation", "kms:DisableKeyRotation", "kms:ScheduleKeyDeletion", "kms:TagResource"] },
    { Effect = "Allow", Resource = ["arn:aws:sns:${var.aws_region}:${var.account_id}:commerce-aws-operations", "arn:aws:sns:${var.aws_region}:${var.account_id}:commerce-aws-operations:*"], Condition = local.regional, Action = ["sns:CreateTopic", "sns:DeleteTopic", "sns:SetTopicAttributes", "sns:Subscribe", "sns:Unsubscribe", "sns:TagResource", "sns:UntagResource"] },
    { Effect = "Allow", Resource = ["arn:aws:cloudwatch:${var.aws_region}:${var.account_id}:alarm:commerce-aws-*"], Condition = local.regional, Action = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:TagResource", "cloudwatch:UntagResource"] },
    { Effect = "Allow", Resource = ["arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/eks/commerce-aws/cluster", "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/eks/commerce-aws/cluster:*"], Condition = local.regional, Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:UntagLogGroup"] }
  ]
  apply_policy_documents = {
    iam     = jsonencode({ Version = "2012-10-17", Statement = local.apply_iam_statements })
    network = jsonencode({ Version = "2012-10-17", Statement = local.apply_ec2_statements })
    cluster = jsonencode({ Version = "2012-10-17", Statement = local.apply_eks_statements })
    data    = jsonencode({ Version = "2012-10-17", Statement = local.apply_data_statements })
    state   = jsonencode({ Version = "2012-10-17", Statement = local.apply_storage_statements })
    read    = jsonencode({ Version = "2012-10-17", Statement = concat([jsondecode(local.plan_permissions).Statement[0], jsondecode(local.plan_permissions).Statement[1]], [{ Effect = "Allow", Action = ["elasticloadbalancing:DescribeLoadBalancers"], Resource = ["*"], Condition = local.regional }]) })
  }
}
