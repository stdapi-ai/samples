/*
============================================================================
Amazon S3 Object Storage
============================================================================
LobeHub stores file, avatar and knowledge-base uploads in an S3 bucket.

The bucket is fully private: with S3_SET_ACL=0 and no S3_PUBLIC_DOMAIN,
LobeHub hands the browser presigned URLs for both uploads and downloads, so
nothing has to be publicly readable.

LobeHub passes S3_ACCESS_KEY_ID/S3_SECRET_ACCESS_KEY explicitly to the AWS
SDK and has no way to consume the ECS task role or a session token, so a
dedicated IAM user restricted to this bucket is created for it. See the
README for the resulting trade-off.
*/

locals {
  s3_bucket   = "${local.name_prefix}-lobehub-files"
  s3_endpoint = "https://s3.${data.aws_region.current.region}.amazonaws.com"
}

/*
----------------------------------------------------------------------------
Bucket
----------------------------------------------------------------------------
*/

resource "aws_s3_bucket" "lobehub" {
  bucket        = local.s3_bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lobehub" {
  bucket                  = aws_s3_bucket.lobehub.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disables ACLs entirely; LobeHub never needs one since S3_SET_ACL is 0.
resource "aws_s3_bucket_ownership_controls" "lobehub" {
  bucket = aws_s3_bucket.lobehub.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "lobehub" {
  bucket = aws_s3_bucket.lobehub.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lobehub" {
  bucket = aws_s3_bucket.lobehub.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      kms_master_key_id = module.vpc.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lobehub" {
  bucket     = aws_s3_bucket.lobehub.id
  depends_on = [aws_s3_bucket_versioning.lobehub]

  rule {
    id     = "cleanup"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "s3_lobehub_bucket" {
  policy_id = local.s3_bucket
  statement {
    sid    = "EnforceTLS"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.lobehub.arn,
      "${aws_s3_bucket.lobehub.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "lobehub" {
  bucket     = aws_s3_bucket.lobehub.id
  policy     = data.aws_iam_policy_document.s3_lobehub_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.lobehub]
}

# The browser uploads to and downloads from the bucket directly through
# presigned URLs, which is a cross-origin request from the app's own origin.
resource "aws_s3_bucket_cors_configuration" "lobehub" {
  bucket = aws_s3_bucket.lobehub.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "HEAD"]
    allowed_origins = [local.lobehub_url]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

/*
----------------------------------------------------------------------------
IAM User
----------------------------------------------------------------------------
*/

resource "aws_iam_user" "lobehub_s3" {
  name = "${local.name_prefix}-lobehub-s3"
}

resource "aws_iam_access_key" "lobehub_s3" {
  user = aws_iam_user.lobehub_s3.name
}

data "aws_iam_policy_document" "lobehub_s3" {
  statement {
    sid       = "Bucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.lobehub.arn]
  }
  statement {
    sid = "Objects"
    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:GetObjectAttributes",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.lobehub.arn}/*"]
  }
  # Required to write and read objects encrypted with the bucket's CMK.
  statement {
    sid       = "Encryption"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [module.vpc.kms_key_arn]
  }
}

resource "aws_iam_user_policy" "lobehub_s3" {
  name   = "${local.name_prefix}-lobehub-s3"
  user   = aws_iam_user.lobehub_s3.name
  policy = data.aws_iam_policy_document.lobehub_s3.json
}
