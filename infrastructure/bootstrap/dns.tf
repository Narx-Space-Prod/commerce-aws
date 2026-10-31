# Public DNS is a retained foundation resource. Creating this zone does not
# delegate the domain; the registrar continues using the current DNS provider
# until all existing records have been copied and reviewed.
resource "aws_route53_zone" "public" {
  name = var.public_dns_zone_name

  lifecycle {
    prevent_destroy = true
  }
}
