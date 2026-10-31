output "cluster_name" {
  description = "Name used by platform bootstrap and Pod Identity associations."
  value       = aws_eks_cluster.this.name
}

output "cluster_security_group_id" {
  description = "Cluster security group used to authorize database traffic."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
