output "state_bucket_name" {
  description = "S3 backend bucket shared by separate Terraform state keys."
  value       = aws_s3_bucket.state.id
}

output "aws_region" {
  description = "Region to use in the S3 backend configuration."
  value       = var.aws_region
}

output "public_dns_zone_id" {
  description = "Retained Route 53 hosted-zone ID for narx.space. Do not change registrar nameservers until DNS migration is reviewed."
  value       = aws_route53_zone.public.zone_id
}

output "public_dns_name_servers" {
  description = "Route 53 name servers; use only after all existing DNS records have been migrated and verified."
  value       = aws_route53_zone.public.name_servers
}
