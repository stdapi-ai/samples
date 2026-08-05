/*
============================================================================
Application Load Balancer for OpenClaw
============================================================================
Public ALB exposing the OpenClaw gateway and Control UI, both multiplexed
on a single port (18789).
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
  alb_dns_enabled = var.alb_domain_name != null && var.alb_route53_zone_name != null
  alb_protocol    = local.alb_dns_enabled ? "HTTPS" : "HTTP"
  alb_host        = local.alb_dns_enabled ? var.alb_domain_name : aws_lb.alb.dns_name

  # Also the origin OpenClaw's own gateway.controlUi.allowedOrigins allowlist
  # must carry (see openclaw.tf): it has to be exactly what the browser sends
  # as its Origin header, port included since 18789 is not a default scheme
  # port.
  openclaw_control_ui_url = "${lower(local.alb_protocol)}://${local.alb_host}:${local.openclaw_port}"
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

  # The Control UI holds its WebSocket connection open for the life of a
  # session (device pairing, live agent output); the default 60s ALB idle
  # timeout would otherwise drop it mid-session.
  idle_timeout = 3600
}

resource "aws_vpc_security_group_ingress_rule" "alb_listener" {
  security_group_id = aws_security_group.alb.id
  description       = "OpenClaw gateway/Control UI from current IP"
  from_port         = local.openclaw_port
  to_port           = local.openclaw_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "${chomp(data.http.myip.response_body)}/32"
}

resource "aws_lb_target_group" "alb_openclaw" {
  name        = "${local.name_prefix}-openclaw"
  port        = local.openclaw_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check {
    # Verified: GET /health returns {"ok":true,"status":"live"}, unauthenticated,
    # with no session/LLM call. https://docs.openclaw.ai/gateway/health
    path = "/health"
  }
  # A pairing/agent session is bound to the WebSocket connection it opened
  # on; only relevant if the service ever scales beyond one task (it does
  # not by default -- see openclaw.tf), kept here for that case.
  stickiness {
    type    = "lb_cookie"
    enabled = true
  }
}

resource "aws_lb_listener" "alb" {
  load_balancer_arn = aws_lb.alb.arn
  port              = local.openclaw_port
  protocol          = local.alb_protocol
  certificate_arn   = local.alb_dns_enabled ? aws_acm_certificate_validation.alb[0].certificate_arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_openclaw.arn
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

output "openclaw_control_ui_url" {
  description = "OpenClaw gateway/Control UI URL (HTTPS when a custom domain is configured)"
  value       = local.openclaw_control_ui_url
}
