# Seeded once by Terraform, only when /config/configuration.yaml is absent
# from the EFS volume (see the "init" container in home_assistant.tf).
# Home Assistant does not manage this file after onboarding -- edit it
# directly (or through the UI, where an integration supports it) and your
# changes survive redeployments.

default_config:

# Home Assistant sits behind the ALB (a reverse proxy). Without this block
# every request arriving through the ALB is rejected -- this is the single
# most common failure when running Home Assistant behind a reverse proxy.
http:
  use_x_forwarded_for: true
  trusted_proxies:
%{ for cidr in trusted_proxy_cidrs ~}
    - ${cidr}
%{ endfor ~}
