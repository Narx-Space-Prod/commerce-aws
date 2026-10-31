moved {
  from = aws_vpc.this
  to   = module.network.aws_vpc.this
}

moved {
  from = aws_internet_gateway.this
  to   = module.network.aws_internet_gateway.this
}

moved {
  from = aws_subnet.public
  to   = module.network.aws_subnet.public
}

moved {
  from = aws_subnet.database
  to   = module.network.aws_subnet.database
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route_table_association.public
  to   = module.network.aws_route_table_association.public
}

moved {
  from = aws_security_group.database
  to   = module.data.aws_security_group.database
}

moved {
  from = aws_vpc_security_group_ingress_rule.database
  to   = module.data.aws_vpc_security_group_ingress_rule.database
}

moved {
  from = aws_iam_role.cluster
  to   = module.eks.aws_iam_role.cluster
}

moved {
  from = aws_iam_role_policy_attachment.cluster
  to   = module.eks.aws_iam_role_policy_attachment.cluster
}

moved {
  from = aws_cloudwatch_log_group.eks
  to   = module.eks.aws_cloudwatch_log_group.eks
}

moved {
  from = aws_eks_cluster.this
  to   = module.eks.aws_eks_cluster.this
}

moved {
  from = aws_eks_access_entry.operator
  to   = module.eks.aws_eks_access_entry.operator
}

moved {
  from = aws_eks_access_policy_association.operator
  to   = module.eks.aws_eks_access_policy_association.operator
}

moved {
  from = aws_iam_role.node
  to   = module.eks.aws_iam_role.node
}

moved {
  from = aws_iam_role_policy_attachment.node
  to   = module.eks.aws_iam_role_policy_attachment.node
}

moved {
  from = aws_launch_template.node
  to   = module.eks.aws_launch_template.node
}

moved {
  from = aws_eks_node_group.this
  to   = module.eks.aws_eks_node_group.this
}

moved {
  from = aws_eks_addon.identity
  to   = module.eks.aws_eks_addon.identity
}

moved {
  from = aws_eks_addon.cni
  to   = module.eks.aws_eks_addon.cni
}

moved {
  from = aws_iam_role.cni
  to   = module.eks.aws_iam_role.cni
}

moved {
  from = aws_iam_role_policy_attachment.cni
  to   = module.eks.aws_iam_role_policy_attachment.cni
}

moved {
  from = aws_eks_addon.proxy
  to   = module.eks.aws_eks_addon.proxy
}

moved {
  from = aws_eks_addon.dns
  to   = module.eks.aws_eks_addon.dns
}

moved {
  from = aws_iam_role.storage
  to   = module.eks.aws_iam_role.storage
}

moved {
  from = aws_iam_role_policy_attachment.storage
  to   = module.eks.aws_iam_role_policy_attachment.storage
}

moved {
  from = aws_eks_addon.storage
  to   = module.eks.aws_eks_addon.storage
}

moved {
  from = aws_iam_role.ingress
  to   = module.eks.aws_iam_role.ingress
}

moved {
  from = aws_iam_role_policy.ingress
  to   = module.eks.aws_iam_role_policy.ingress
}

moved {
  from = aws_eks_pod_identity_association.ingress
  to   = module.eks.aws_eks_pod_identity_association.ingress
}

moved {
  from = aws_db_subnet_group.this
  to   = module.data.aws_db_subnet_group.this
}

moved {
  from = aws_db_parameter_group.this
  to   = module.data.aws_db_parameter_group.this
}

moved {
  from = aws_db_instance.this
  to   = module.data.aws_db_instance.this
}

moved {
  from = aws_sqs_queue.dlq
  to   = module.data.aws_sqs_queue.dlq
}

moved {
  from = aws_sqs_queue.paid
  to   = module.data.aws_sqs_queue.paid
}

moved {
  from = aws_sqs_queue_redrive_allow_policy.dlq
  to   = module.data.aws_sqs_queue_redrive_allow_policy.dlq
}

moved {
  from = random_password.session
  to   = module.data.random_password.session
}

moved {
  from = random_password.database
  to   = module.data.random_password.database
}

moved {
  from = aws_secretsmanager_secret.runtime
  to   = module.data.aws_secretsmanager_secret.runtime
}

moved {
  from = aws_secretsmanager_secret_version.runtime
  to   = module.data.aws_secretsmanager_secret_version.runtime
}

moved {
  from = aws_iam_role.delivery
  to   = module.data.aws_iam_role.delivery
}

moved {
  from = aws_iam_role_policy.delivery
  to   = module.data.aws_iam_role_policy.delivery
}

moved {
  from = aws_eks_pod_identity_association.delivery
  to   = module.data.aws_eks_pod_identity_association.delivery
}

moved {
  from = aws_iam_role.secrets
  to   = module.data.aws_iam_role.secrets
}

moved {
  from = aws_iam_role_policy.secrets
  to   = module.data.aws_iam_role_policy.secrets
}

moved {
  from = aws_eks_pod_identity_association.secrets
  to   = module.data.aws_eks_pod_identity_association.secrets
}

moved {
  from = aws_kms_key.notifications
  to   = module.data.aws_kms_key.notifications
}

moved {
  from = aws_sns_topic_policy.alarms
  to   = module.data.aws_sns_topic_policy.alarms
}

moved {
  from = aws_sns_topic.operations
  to   = module.data.aws_sns_topic.operations
}

moved {
  from = aws_sns_topic_subscription.email
  to   = module.data.aws_sns_topic_subscription.email
}

moved {
  from = aws_cloudwatch_metric_alarm.dead_letters
  to   = module.data.aws_cloudwatch_metric_alarm.dead_letters
}

moved {
  from = aws_cloudwatch_metric_alarm.queue_age
  to   = module.data.aws_cloudwatch_metric_alarm.queue_age
}
