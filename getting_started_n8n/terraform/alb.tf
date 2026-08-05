/*
============================================================================
Application Load Balancer for n8n
============================================================================
Public ALB to expose n8n over HTTPS.

HTTPS is not optional here: n8n marks its
session cookie "Secure" whenever N8N_PROTOCOL=https, which every browser
then refuses to send back over plain HTTP. A custom domain backed by a
Route53 zone is therefore a hard prerequisite, not a nice-to-have.
*/

variable "alb_domain_name" {
  type        = string
  description = "Custom domain name for the ALB, e.g. \"n8n.example.com\". Required: n8n needs a real HTTPS origin."
}

variable "alb_route53_zone_name" {
  type        = string
  description = "Route53 zone name that hosts var.alb_domain_name, e.g. \"example.com\". Required for ACM DNS validation."
}

locals {
  alb_listener_port = 443
  n8n_url           = "https://${var.alb_domain_name}"
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
}

resource "aws_vpc_security_group_ingress_rule" "alb_listener" {
  security_group_id = aws_security_group.alb.id
  description       = "ALB listener from current IP"
  from_port         = local.alb_listener_port
  to_port           = local.alb_listener_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "${chomp(data.http.myip.response_body)}/32"
}

resource "aws_lb_target_group" "alb_n8n" {
  name        = "${local.name_prefix}-n8n"
  port        = local.n8n_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check {
    path = "/healthz"
  }
}

resource "aws_lb_listener" "alb" {
  load_balancer_arn = aws_lb.alb.arn
  port              = local.alb_listener_port
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate_validation.alb.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_n8n.arn
  }
}

/*
----------------------------------------------------------------------------
HTTPS Custom Domain
----------------------------------------------------------------------------
*/

data "aws_route53_zone" "alb" {
  name = var.alb_route53_zone_name
}

resource "aws_acm_certificate" "alb" {
  domain_name       = var.alb_domain_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "alb_validation" {
  for_each = {
    for dvo in aws_acm_certificate.alb.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
  zone_id = data.aws_route53_zone.alb.zone_id
}

resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for record in aws_route53_record.alb_validation : record.fqdn]
}

resource "aws_route53_record" "alb" {
  zone_id = data.aws_route53_zone.alb.zone_id
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

output "n8n_url" {
  description = "n8n URL"
  value       = local.n8n_url
}
