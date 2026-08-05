/*
============================================================================
Application Load Balancer for Hermes Agent
============================================================================
Public ALB exposing the Hermes gateway API (8642) and web dashboard (9119).
Two listeners share the same ALB and, when configured, the same certificate.
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
  alb_dns_enabled      = var.alb_domain_name != null && var.alb_route53_zone_name != null
  alb_protocol         = local.alb_dns_enabled ? "HTTPS" : "HTTP"
  alb_host             = local.alb_dns_enabled ? var.alb_domain_name : aws_lb.alb.dns_name
  hermes_gateway_url   = "${lower(local.alb_protocol)}://${local.alb_host}:${local.hermes_gateway_port}"
  hermes_dashboard_url = "${lower(local.alb_protocol)}://${local.alb_host}:${local.hermes_dashboard_port}"
}

/*
----------------------------------------------------------------------------
ALB and Listeners
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
}

resource "aws_vpc_security_group_ingress_rule" "alb_gateway" {
  security_group_id = aws_security_group.alb.id
  description       = "Hermes gateway API from current IP"
  from_port         = local.hermes_gateway_port
  to_port           = local.hermes_gateway_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "${chomp(data.http.myip.response_body)}/32"
}

resource "aws_vpc_security_group_ingress_rule" "alb_dashboard" {
  security_group_id = aws_security_group.alb.id
  description       = "Hermes dashboard from current IP"
  from_port         = local.hermes_dashboard_port
  to_port           = local.hermes_dashboard_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "${chomp(data.http.myip.response_body)}/32"
}

resource "aws_lb_target_group" "alb_hermes_gateway" {
  name        = "${local.name_prefix}-hermes-gw"
  port        = local.hermes_gateway_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check {
    # Verified: GET /health returns {"status":"ok"} on the gateway API.
    path = "/health"
  }
}

resource "aws_lb_target_group" "alb_hermes_dashboard" {
  name        = "${local.name_prefix}-hermes-dash"
  port        = local.hermes_dashboard_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check {
    # "/" 302-redirects to the login page once bound non-loopback (see
    # hermes.tf): auth here is a session-cookie login form, not a
    # WWW-Authenticate challenge, so there is no unauthenticated 401 to
    # match on. The login page itself renders 200 without credentials.
    path = "/login"
  }
}

resource "aws_lb_listener" "alb_gateway" {
  load_balancer_arn = aws_lb.alb.arn
  port              = local.hermes_gateway_port
  protocol          = local.alb_protocol
  certificate_arn   = local.alb_dns_enabled ? aws_acm_certificate_validation.alb[0].certificate_arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_hermes_gateway.arn
  }
}

resource "aws_lb_listener" "alb_dashboard" {
  load_balancer_arn = aws_lb.alb.arn
  port              = local.hermes_dashboard_port
  protocol          = local.alb_protocol
  certificate_arn   = local.alb_dns_enabled ? aws_acm_certificate_validation.alb[0].certificate_arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_hermes_dashboard.arn
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

output "hermes_gateway_url" {
  description = "Hermes gateway API URL (OpenAI-compatible), HTTPS when a custom domain is configured"
  value       = local.hermes_gateway_url
}

output "hermes_dashboard_url" {
  description = "Hermes web dashboard URL, HTTPS when a custom domain is configured"
  value       = local.hermes_dashboard_url
}
