output "state_bucket_name" {
  description = "S3 backend bucket shared by separate Terraform state keys."
  value       = aws_s3_bucket.state.id
}

output "aws_region" {
  description = "Region to use in the S3 backend configuration."
  value       = var.aws_region
}
