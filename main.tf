############################################
# Variables & Data Sources
############################################

locals {
  has_lambda_edge_enabled = length([
    for v in var.lambda_at_edge : v
    if try(v.enabled, false)
  ]) > 0

  enabled_log_arns = [
    for k, v in var.lambda_at_edge :
    "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name}-${k}:*"
    if try(v.enabled, false)
  ]
}

data "aws_caller_identity" "current" {}

############################################
# CloudWatch Log Group: Lambda@Edge Logs
############################################

resource "aws_cloudwatch_log_group" "lambda_logs_prevent_destroy" {
  for_each = var.lambda_edge_log_prevent_destroy ? {
    for k, v in var.lambda_at_edge : k => v
    if try(v.enabled, false)
  } : {}

  name              = "/aws/lambda/${var.name}-${each.key}"
  retention_in_days = var.lambda_edge_log_retention_days

  provider = aws.us_east_1

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.name}-${each.key}"
  }
}

resource "aws_cloudwatch_log_group" "lambda_logs_no_prevent_destroy" {
  for_each = var.lambda_edge_log_prevent_destroy ? {} : {
    for k, v in var.lambda_at_edge : k => v
    if try(v.enabled, false)
  }

  name              = "/aws/lambda/${var.name}-${each.key}"
  retention_in_days = var.lambda_edge_log_retention_days

  provider = aws.us_east_1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(var.tags, { Name = var.name })
}

############################################
# IAM Role & Policy for Lambda@Edge
############################################

resource "aws_iam_role" "lambda_edge" {
  count = local.has_lambda_edge_enabled ? 1 : 0

  name = "${var.name}-lambda-edge"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name}-lambda-edge"
  })
}

resource "aws_iam_role_policy" "lambda_edge_logs" {
  count = local.has_lambda_edge_enabled ? 1 : 0

  name = "${var.name}-lambda-edge-logs"
  role = aws_iam_role.lambda_edge[0].id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup"
          ]
          Resource = "*"
        }
      ],
      length(local.enabled_log_arns) > 0 ? [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = local.enabled_log_arns
        }
      ] : []
    )
  })
}

############################################
# Lambda Functions (us-east-1)
############################################

resource "aws_lambda_function" "lambda_edge" {
  for_each = {
    for k, v in var.lambda_at_edge : k => v
    if try(v.enabled, false)
  }

  provider         = aws.us_east_1
  function_name    = "${var.name}-${each.key}"
  filename         = each.value.zip_path
  handler          = try(each.value.handler, "index.handler")
  role             = aws_iam_role.lambda_edge[0].arn
  runtime          = try(each.value.runtime, "nodejs18.x")
  source_code_hash = filebase64sha256(each.value.zip_path)
  timeout          = 3
  publish          = true

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name       = "${var.name}-${each.key}"
    LambdaEdge = "true"
    EventType  = each.key
  })

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs_no_prevent_destroy,
    aws_cloudwatch_log_group.lambda_logs_prevent_destroy
  ]
}

resource "aws_lambda_function" "ordered_lambda_at_edge" {
  for_each = {
    for k, v in var.ordered_lambda_at_edge : k => v
    if v.enabled
  }

  provider         = aws.us_east_1
  function_name    = "${var.name}-${each.key}"
  filename         = each.value.zip_path
  handler          = try(each.value.handler, "index.handler")
  role             = aws_iam_role.lambda_edge[0].arn
  runtime          = try(each.value.runtime, "nodejs18.x")
  source_code_hash = filebase64sha256(each.value.zip_path)
  timeout          = 3
  publish          = true

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name       = "${var.name}-${each.key}"
    LambdaEdge = "true"
    EventType  = each.key
  })
}


############################################
# CloudFront Distribution
############################################

resource "aws_cloudfront_distribution" "this" {
  enabled             = var.cloudfront.enabled
  default_root_object = var.cloudfront.default_root_object
  comment             = var.cloudfront.comment
  price_class         = var.cloudfront.price_class
  http_version        = var.cloudfront.http_version
  is_ipv6_enabled     = var.cloudfront.ipv6_enabled
  wait_for_deployment = var.cloudfront.wait_for_deployment
  web_acl_id          = var.cloudfront.web_acl_id
  aliases             = var.cloudfront.aliases

  origin {
    domain_name = var.origin.domain_name
    origin_id   = var.origin.origin_id

    custom_origin_config {
      http_port              = var.origin.http_port
      https_port             = var.origin.https_port
      origin_protocol_policy = var.origin.protocol_policy
      origin_ssl_protocols   = var.origin.ssl_protocols
    }
  }

  default_cache_behavior {
    target_origin_id       = var.default_cache_behavior.target_origin_id
    viewer_protocol_policy = var.default_cache_behavior.viewer_protocol_policy
    allowed_methods        = var.default_cache_behavior.allowed_methods
    cached_methods         = var.default_cache_behavior.cached_methods
    compress               = var.default_cache_behavior.compress

    forwarded_values {
      query_string = var.default_cache_behavior.forward_query_string
      cookies {
        forward = var.default_cache_behavior.cookie_forward_policy
      }
    }

    dynamic "lambda_function_association" {
      for_each = {
        for k, v in var.lambda_at_edge :
        k => v
        if try(v.enabled, false) && contains([
          "viewer-request",
          "viewer-response",
          "origin-request",
          "origin-response"
        ], k)
      }

      content {
        event_type   = lambda_function_association.key
        lambda_arn   = aws_lambda_function.lambda_edge[lambda_function_association.key].qualified_arn
        include_body = try(lambda_function_association.value.include_body, false)
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.ordered_cache_behaviors

    content {
      path_pattern           = ordered_cache_behavior.value.path_pattern
      target_origin_id       = try(ordered_cache_behavior.value.target_origin_id, "origin-1")
      viewer_protocol_policy = try(ordered_cache_behavior.value.viewer_protocol_policy, "redirect-to-https")
      allowed_methods        = try(ordered_cache_behavior.value.allowed_methods, ["GET", "HEAD"])
      cached_methods         = try(ordered_cache_behavior.value.cached_methods, ["GET", "HEAD"])
      compress               = try(ordered_cache_behavior.value.compress, true)

      forwarded_values {
        query_string = try(ordered_cache_behavior.value.forward_query_string, false)
        cookies {
          forward = try(ordered_cache_behavior.value.cookie_forward_policy, "none")
        }
      }

      dynamic "lambda_function_association" {
        for_each = try(ordered_cache_behavior.value.lambda_key, null) != null ? [1] : []

        content {
          event_type   = try(ordered_cache_behavior.value.lambda_event_type, "viewer-request")
          lambda_arn   = aws_lambda_function.ordered_lambda_at_edge[ordered_cache_behavior.value.lambda_key].qualified_arn
          include_body = try(var.ordered_lambda_at_edge[ordered_cache_behavior.value.lambda_key].include_body, false)
        }
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.viewer_certificate.use_default_certificate
    acm_certificate_arn            = var.viewer_certificate.acm_certificate_arn
    ssl_support_method             = var.viewer_certificate.ssl_support_method
    minimum_protocol_version       = var.viewer_certificate.ssl_min_protocol_version
  }

  restrictions {
    geo_restriction {
      restriction_type = var.cloudfront.geo_restriction.restriction_type
      locations        = var.cloudfront.geo_restriction.locations
    }
  }

  dynamic "logging_config" {
    for_each = var.cloudfront.logging.enabled ? [1] : []

    content {
      bucket          = var.cloudfront.logging.bucket
      prefix          = var.cloudfront.logging.prefix
      include_cookies = var.cloudfront.logging.include_cookies
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-lambda-edge"
  })
}
