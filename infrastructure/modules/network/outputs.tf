output "vpc_id" {
  description = "VPC identifier for state ownership checks and teardown inventory."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs in the configured availability-zone order."
  value       = aws_subnet.public[*].id
}

output "database_subnet_ids" {
  description = "Isolated database subnet IDs in the configured availability-zone order."
  value       = aws_subnet.database[*].id
}
