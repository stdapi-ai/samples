/*
============================================================================
Application Load Balancer for Docling Serve
============================================================================
Public ALB exposing the Docling Serve HTTP API
*/

variable "alb_domain_name" {
  type        = string
  default     = null
  description = "Optional custom domain name for the ALB (enables HTTPS)"
}

variable "alb_route53_zone_name" {
  type        = string
  default     = null
  description = "Route53 zone name that hosts the ALB domain (enables HTTPS)"
}

locals {
  alb_dns_enabled       = var.alb_domain_name != null && var.alb_route53_zone_name != null
  alb_listener_port     = local.alb_dns_enabled ? 443 : 80
  alb_listener_protocol = local.alb_dns_enabled ? "HTTPS" : "HTTP"
  docling_url           = local.alb_dns_enabled ? "https://${var.alb_domain_name}" : "http://${aws_lb.alb.dns_name}"
}

/*
----------------------------------------------------------------------------
ALB and Listener
----------------------------------------------------------------------------
*/

resource "aws_security_group" "alb" {
  name   = "${local.name_prefix}-alb"
  vpc_id = module.vpc.vpc_id
}

resource "aws_lb" "alb" {
  name                       = "${local.name_prefix}-alb"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.vpc.public_subnets_ids
  drop_invalid_header_fields = true
  # CPU-only conversion of a multi-page document routinely exceeds the ALB's
  # 60s default, returning a 504 while Docling is still working (verified:
  # a 20-page PDF took 112s). /v1/convert/* is synchronous, so the client
  # connection must stay open for the whole conversion.
  idle_timeout = 300
}

resource "aws_vpc_security_group_ingress_rule" "alb_listener" {
  security_group_id = aws_security_group.alb.id
  description       = "ALB listener from current IP"
  from_port         = local.alb_listener_port
  to_port           = local.alb_listener_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "${chomp(data.http.myip.response_body)}/32"
}

resource "aws_lb_target_group" "alb_docling" {
  name        = "${local.name_prefix}-docling"
  port        = local.docling_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check {
    path = "/health"
  }
}

resource "aws_lb_listener" "alb" {
  load_balancer_arn = aws_lb.alb.arn
  port              = local.alb_listener_port
  protocol          = local.alb_listener_protocol
  certificate_arn   = local.alb_dns_enabled ? aws_acm_certificate_validation.alb[0].certificate_arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_docling.arn
  }
}

/*
----------------------------------------------------------------------------
HTTPS Custom Domain
----------------------------------------------------------------------------
*/

data "aws_route53_zone" "alb" {
  count = local.alb_dns_enabled ? 1 : 0
  name  = var.alb_route53_zone_name
}

resource "aws_acm_certificate" "alb" {
  count             = local.alb_dns_enabled ? 1 : 0
  domain_name       = var.alb_domain_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "alb_validation" {
  for_each = local.alb_dns_enabled ? {
    for dvo in aws_acm_certificate.alb[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
  zone_id = data.aws_route53_zone.alb[0].zone_id
}

resource "aws_acm_certificate_validation" "alb" {
  count                   = local.alb_dns_enabled ? 1 : 0
  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [for record in aws_route53_record.alb_validation : record.fqdn]
}

resource "aws_route53_record" "alb" {
  count   = local.alb_dns_enabled ? 1 : 0
  zone_id = data.aws_route53_zone.alb[0].zone_id
  name    = var.alb_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

/*
----------------------------------------------------------------------------
Outputs
----------------------------------------------------------------------------
*/

output "docling_url" {
  description = "Docling Serve URL (HTTPS when a custom domain is configured)"
  value       = local.docling_url
}
