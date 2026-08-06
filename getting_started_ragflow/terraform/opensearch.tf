/*
============================================================================
Amazon OpenSearch Service configuration
============================================================================
Deploys a managed OpenSearch domain as RAGFlow's document and vector store.

Amazon OpenSearch Serverless is not usable here: RAGFlow's client signs no
SigV4 request (it only knows HTTP basic authentication), and Serverless does
not expose the "_search/pipeline" API the connector provisions for hybrid
BM25 + KNN search.
*/

/*
----------------------------------------------------------------------------
Connection Details
----------------------------------------------------------------------------
*/

locals {
  # The engine version RAGFlow is tested against upstream (its Compose file
  # runs opensearchproject/opensearch:2.19.1). The connector requires major
  # version >= 2, and hybrid search requires >= 2.10.
  opensearch_engine_version = "OpenSearch_2.19"

  opensearch_host     = aws_opensearch_domain.main.endpoint
  opensearch_username = "ragflow"
  opensearch_password = random_password.opensearch_master.result
}

/*
----------------------------------------------------------------------------
Service-Linked Role
----------------------------------------------------------------------------
A VPC domain cannot be created until the account has the Amazon OpenSearch
Service service-linked role. It is account-wide and shared with every other
domain, so it is created if missing rather than owned by this stack, and it is
left in place on destroy.
*/

resource "null_resource" "opensearch_service_linked_role" {
  provisioner "local-exec" {
    command = "aws iam get-role --role-name AWSServiceRoleForAmazonOpenSearchService > /dev/null 2>&1 || aws iam create-service-linked-role --aws-service-name opensearchservice.amazonaws.com"
  }
}

/*
----------------------------------------------------------------------------
Domain
----------------------------------------------------------------------------
*/

resource "aws_opensearch_domain" "main" {
  depends_on = [null_resource.opensearch_service_linked_role]

  domain_name    = "${local.name_prefix}-rf"
  engine_version = local.opensearch_engine_version

  cluster_config {
    instance_type          = "t3.small.search"
    instance_count         = 1
    zone_awareness_enabled = false
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 20
  }

  vpc_options {
    # A single data node lives in a single availability zone.
    subnet_ids         = [module.vpc.subnets_ids[0]]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = module.vpc.kms_key_arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-PFS-2023-10"
  }

  # Fine-grained access control with an internal master user: RAGFlow
  # authenticates with a username and password, which is the only scheme its
  # OpenSearch client supports.
  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = local.opensearch_username
      master_user_password = local.opensearch_password
    }
  }

  /*
  Requests authenticated by the internal user database carry no IAM principal,
  so the domain access policy cannot restrict by principal without rejecting
  them. Authorization is enforced by fine-grained access control instead, and
  reachability by the VPC placement and the security group below.
  */
  access_policies = data.aws_iam_policy_document.opensearch.json
}

data "aws_iam_policy_document" "opensearch" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["es:ESHttp*"]
    resources = ["arn:aws:es:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:domain/${local.name_prefix}-rf/*"]
  }
}

resource "random_password" "opensearch_master" {
  length = 32
  # The master user password must mix cases, digits and a special character.
  # The set excludes the single quote, which would end the YAML scalar the
  # password is rendered into, and the characters bash would treat specially.
  override_special = "!#%&*+-:;<=>?@^_~"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

/*
----------------------------------------------------------------------------
Network Configuration
----------------------------------------------------------------------------
*/

resource "aws_security_group" "opensearch" {
  name        = "${local.name_prefix}-opensearch"
  description = "${local.name_prefix}-opensearch"
  vpc_id      = module.vpc.vpc_id
}
