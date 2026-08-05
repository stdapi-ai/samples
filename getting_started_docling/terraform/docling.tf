/*
============================================================================
Docling Serve Deployment
============================================================================
Deploys Docling Serve (https://github.com/docling-project/docling-serve) on
ECS Fargate. Docling converts PDFs and office documents into structured
Markdown/JSON for RAG pipelines.

By default Docling's conversion pipeline is classical computer vision (layout
detection, table structure, OCR) and never calls an LLM. This deployment also
wires Docling's *optional* VLM pipeline to Amazon Bedrock through stdapi.ai's
OpenAI-compatible endpoint, so that requesting `pipeline=vlm` exercises the
gateway. See the README for the exact request that triggers it.

VLM wiring notes (verified against source, not docs):
Docling Serve's own docs/configuration.md shows an example for
DOCLING_SERVE_CUSTOM_VLM_PRESETS that does not match the schema its server
actually validates (`{"engine": "openai", "model": "..."}` isn't a field on
any of the current pydantic models). The shape used below was verified
directly against the pinned version's dependency chain:
- docling-serve v1.29.0 depends on docling-jobkit>=3.2.0,<4
- docling_jobkit/convert/manager.py `_get_options_from_preset` validates a
  custom preset's raw dict with `VlmConvertOptions.model_validate(...)`
  after instantiating its `engine_options` sub-dict by `engine_type`
  (docling_jobkit/convert/manager.py `_instantiate_engine_options`)
- `VlmConvertOptions` (docling/datamodel/pipeline_options.py) requires
  `model_spec: VlmModelSpec` and `engine_options: BaseVlmEngineOptions`
- `VlmModelSpec` (docling/datamodel/stage_model_specs.py) requires `name`,
  `default_repo_id`, `prompt`, `response_format`
- `ApiVlmEngineOptions` (docling/datamodel/vlm_engine_options.py) is the
  concrete class for `engine_type in {api, api_ollama, api_lmstudio,
  api_openai}`, with `url`, `headers`, `params`, `timeout`, `concurrency`

`DOCLING_SERVE_DEFAULT_VLM_PRESET` is deliberately NOT set: verified live
that `docling_jobkit/convert/manager.py` `_build_preset_registries` always
tags its synthetic "default" registry entry `source: "docling"`, so
`"vlm_pipeline_preset": "default"` tries to resolve a custom preset ID as a
Docling built-in and fails with "Preset '<id>' not found for
VlmConvertOptions" even though the preset is registered correctly. Requests
must reference the custom preset ID directly (see README).
*/

locals {
  docling_port      = 5001
  docling_image_tag = "v1.29.0"
  # The "-cpu" image ships CPU-only torch with models baked in (no GPU, no
  # runtime download), and Fargate pulls it from Quay with no credential.
  # Quay is the current registry for this tag: GHCR stops at v1.1.0.
  docling_source_image = "quay.io/docling-project/docling-serve-cpu:${local.docling_image_tag}"

  # Vision-capable Bedrock model used for the VLM pipeline, called through
  # stdapi.ai's OpenAI-compatible /v1/chat/completions route.
  docling_vlm_model = "anthropic.claude-haiku-4-5-20251001-v1:0"

  # Custom VLM preset routing Docling's VLM pipeline to stdapi.ai -> Amazon
  # Bedrock. Requests must reference this ID directly as "vlm_pipeline_preset"
  # (see the top-of-file note on why "default" doesn't work here).
  docling_vlm_preset_id = "stdapi_bedrock"
  docling_vlm_presets = {
    (local.docling_vlm_preset_id) = {
      model_spec = {
        name            = "stdapi.ai (Amazon Bedrock)"
        default_repo_id = local.docling_vlm_model
        prompt          = "Convert this page to markdown. Do not miss any text and only output the bare markdown!"
        response_format = "markdown"
      }
      engine_options = {
        engine_type = "api_openai"
        url         = "${local.stdapi_openai_api_url}/chat/completions"
        headers = {
          Authorization = "Bearer ${module.stdapi_ai.api_key}"
        }
        params = {
          model      = local.docling_vlm_model
          max_tokens = 4096
        }
        timeout     = 90
        concurrency = 2
      }
      scale = 2.0
    }
  }
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "docling" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.4"

  name_prefix        = "${local.name_prefix}-docling"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS (image pull from Quay)

  # Docling's CPU-only conversion is memory-hungry: docling-serve's own
  # RQ-engine deployment example (docs/deploy-examples/docling-serve-rq-workers.yaml)
  # sets its "api" container (same docling-serve-cpu image) to
  # cpu: 1 / memory: 8Gi limits for CPU-only inference. Matched here.
  cpu    = 1
  memory = 8192

  container_definitions = {
    main = {
      image = local.docling_source_image
      port_mappings = {
        http = {
          container_port    = local.docling_port
          target_group_arns = [aws_lb_target_group.alb_docling.arn]
        }
      }
      health_check = {
        # Models are baked into the image, but loading them into memory on
        # a single vCPU still takes a while on first start.
        command      = ["CMD-SHELL", "curl --silent --fail http://127.0.0.1:${local.docling_port}/health || exit 1"]
        start_period = 90
        interval     = 30
        retries      = 3
      }
      environment = {
        DOCLING_SERVE_LOG_FORMAT = "json" # Structured logs for CloudWatch

        # Required for the VLM pipeline to call out to stdapi.ai over HTTP.
        DOCLING_SERVE_ENABLE_REMOTE_SERVICES = "true"
      }
      secrets = {
        # Contains the stdapi.ai API key (as an Authorization header), so
        # this goes through "secrets" (KMS-encrypted SSM SecureString),
        # never "environment" (Security Hub ECS.8).
        DOCLING_SERVE_CUSTOM_VLM_PRESETS = jsonencode(local.docling_vlm_presets)
      }
    }
  }

  security_group_connect_egress = {
    "stdapiai" = {
      from_port                    = module.stdapi_ai.port
      referenced_security_group_id = module.stdapi_ai.security_group_id
    }
  }
  security_group_connect_ingress = {
    "alb" = {
      from_port                    = local.docling_port
      referenced_security_group_id = aws_security_group.alb.id
    }
  }
}
