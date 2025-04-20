############################################
# Provider Configuration
############################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.94.1"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

resource "random_string" "suffix" {
  length  = 3
  special = false
  upper   = false
}

locals {
  name      = "lambda-edge"
  base_name = "${local.name}-${random_string.suffix.result}"

  tags = {
    Environment = "dev"
    Project     = "example"
  }
}

module "s3_website" {
  source = "tfstack/s3-static-website/aws"

  s3_config = {
    bucket_name          = local.name
    bucket_acl           = "public-read"
    bucket_suffix        = random_string.suffix.result
    enable_force_destroy = true

    public_access = {
      block_public_acls       = false
      block_public_policy     = false
      ignore_public_acls      = false
      restrict_public_buckets = false
    }

    source_file_path = "${path.module}/external/s3"
  }

  tags = local.tags
}

resource "archive_file" "lambda_viewer_request" {
  type        = "zip"
  source_dir  = "${path.module}/external/lambda/viewer_request"
  output_path = "${path.module}/external/viewer-request.zip"
}

resource "archive_file" "lambda_origin_response" {
  type        = "zip"
  source_dir  = "${path.module}/external/lambda/origin_response"
  output_path = "${path.module}/external/origin-response.zip"
}

module "lambda_at_edge" {
  source = "../.."

  name = local.base_name

  origin = {
    domain_name     = module.s3_website.s3_bucket_domain_name
    origin_id       = "origin-1"
    http_port       = 80
    https_port      = 443
    protocol_policy = "http-only"
    ssl_protocols   = ["TLSv1.2"]
  }

  default_cache_behavior = {
    target_origin_id       = "origin-1"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    forward_query_string   = true
    cookie_forward_policy  = "none"
  }

  viewer_certificate = {
    use_default_certificate  = true
    acm_certificate_arn      = null
    ssl_support_method       = null
    ssl_min_protocol_version = "TLSv1"
  }

  cloudfront = {
    aliases             = []
    comment             = "Managed by Terraform"
    enabled             = true
    http_version        = "http2"
    ipv6_enabled        = true
    price_class         = "PriceClass_All"
    wait_for_deployment = true
    web_acl_id          = null
    default_root_object = "index.html"

    logging = {
      enabled         = false
      bucket          = ""
      prefix          = ""
      include_cookies = false
    }

    geo_restriction = {
      restriction_type = "none"
      locations        = []
    }
  }

  lambda_at_edge = {
    viewer-request = {
      enabled      = true
      zip_path     = archive_file.lambda_viewer_request.output_path
      handler      = "lambda-edge-browser.handler"
      runtime      = "nodejs18.x"
      include_body = false
    }

    origin-response = {
      enabled  = true
      zip_path = archive_file.lambda_origin_response.output_path
      handler  = "origin-response.handler"
      runtime  = "nodejs18.x"
    }

    #   # viewer_response = {
    #   #   enabled  = false
    #   #   zip_path = ""
    #   # }
  }

  lambda_edge_log_prevent_destroy = false
  lambda_edge_log_retention_days  = 1

  tags = local.tags
}

output "s3_website" {
  value = module.s3_website
}

output "lambda_at_edge" {
  value = module.lambda_at_edge
}
