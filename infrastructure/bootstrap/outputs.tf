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
  description = "Route 53 name servers for the narx.space staging zone; this zone is not delegated while Cloudflare Tunnel hostnames remain active."
  value       = aws_route53_zone.public.name_servers
}

output "production_dns_zone_id" {
  description = "Route 53 hosted-zone ID for prod.narx.space, when the production child zone is enabled."
  value       = try(aws_route53_zone.production[0].zone_id, null)
}

output "production_dns_name_servers" {
  description = "Route 53 name servers delegated from Cloudflare for prod.narx.space, when enabled."
  value       = try(aws_route53_zone.production[0].name_servers, null)
}

output "production_shop_hostname" {
  description = "Planned AWS storefront hostname; no shop record is created by the DNS delegation."
  value       = var.enable_production_subzone ? "shop.prod.narx.space" : null
}
