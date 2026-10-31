# Public DNS is a retained foundation resource. Creating this zone does not
# delegate the domain; the registrar continues using the current DNS provider
# until all existing records have been copied and reviewed.
resource "aws_route53_zone" "public" {
  name = var.public_dns_zone_name

  lifecycle {
    prevent_destroy = true
  }
}

# Keep the existing Cloudflare Tunnel hostnames in the parent zone. AWS owns a
# delegated child zone, so switching the registrar's nameservers is unnecessary.
data "cloudflare_zones" "narx_space" {
  count  = var.enable_production_subzone ? 1 : 0
  name   = "narx.space"
  status = "active"
}

resource "aws_route53_zone" "production" {
  count = var.enable_production_subzone ? 1 : 0
  name  = "prod.narx.space"

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_dns_record" "production_delegation" {
  count   = var.enable_production_subzone ? 4 : 0
  zone_id = one(data.cloudflare_zones.narx_space[0].result).id
  name    = aws_route53_zone.production[0].name
  type    = "NS"
  ttl     = 3600
  content = "${aws_route53_zone.production[0].name_servers[count.index]}."
  proxied = false
  comment = "Terraform-managed delegation to the AWS production DNS zone."
}
