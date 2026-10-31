output "runtime_secret_arn" {
  description = "Runtime secret identifier; this output contains no secret payload."
  value       = aws_secretsmanager_secret.runtime.arn
}

output "database_secret_arn" {
  description = "RDS-managed master-secret identifier; this output contains no secret payload."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "database_identifier" {
  description = "Database identifier for backup and restore operations."
  value       = aws_db_instance.this.identifier
}

output "queue_url" {
  description = "Order-paid queue URL used by application delivery processes."
  value       = aws_sqs_queue.paid.url
}

output "dlq_url" {
  description = "Dead-letter queue URL for incident investigation."
  value       = aws_sqs_queue.dlq.url
}
