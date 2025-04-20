############################################
# General Settings
############################################

variable "name" {
  description = "Base name used for naming Lambda functions and IAM roles"
  type        = string
}

variable "tags" {
  description = "A map of tags to use on all resources"
  type        = map(string)
  default     = {}
}

############################################
# Lambda@Edge Configuration
############################################

variable "lambda_at_edge" {
  description = "Configuration for each Lambda@Edge event type"
  type = object({
    viewer-request = optional(object({
      enabled      = bool
      zip_path     = string
      handler      = optional(string, "index.handler")
      runtime      = optional(string, "nodejs18.x")
      include_body = optional(bool, false)
    })),
    origin-request = optional(object({
      enabled      = bool
      zip_path     = string
      handler      = optional(string, "index.handler")
      runtime      = optional(string, "nodejs18.x")
      include_body = optional(bool, false)
    })),
    origin-response = optional(object({
      enabled      = bool
      zip_path     = string
      handler      = optional(string, "index.handler")
      runtime      = optional(string, "nodejs18.x")
      include_body = optional(bool, false)
    })),
    viewer-response = optional(object({
      enabled      = bool
      zip_path     = string
      handler      = optional(string, "index.handler")
      runtime      = optional(string, "nodejs18.x")
      include_body = optional(bool, false)
    }))
  })

  default = {}

  validation {
    condition = alltrue([
      for fn in [
        try(var.lambda_at_edge.viewer-response, null),
        try(var.lambda_at_edge.origin-response, null),
        try(var.lambda_at_edge.origin-request, null),
        try(var.lambda_at_edge.viewer-request, null)
        ] : (
        fn == null || contains([
          "nodejs18.x", "nodejs16.x", "nodejs14.x",
          "python3.9", "python3.8"
        ], try(fn.runtime, "nodejs18.x"))
      )
    ])
    error_message = "If runtime is specified, it must be one of: nodejs18.x, nodejs16.x, nodejs14.x, python3.9, python3.8"
  }

  validation {
    condition = alltrue([
      for fn in [
        try(var.lambda_at_edge.viewer_response, null),
        try(var.lambda_at_edge.origin_response, null),
        try(var.lambda_at_edge.origin_request, null),
        try(var.lambda_at_edge.viewer_request, null)
        ] : (
        fn == null || (
          can(fn.zip_path) &&
          length(trim(try(fn.zip_path, ""), " \t\r\n")) > 0 &&
          can(regex("\\.zip$", try(fn.zip_path, "")))
        )
      )
    ])
    error_message = "zip_path must be a non-empty string ending in .zip if defined"
  }
}

variable "ordered_lambda_at_edge" {
  description = "Lambda@Edge functions used in ordered cache behaviors"
  type = map(object({
    enabled      = bool
    zip_path     = string
    handler      = optional(string, "index.handler")
    runtime      = optional(string, "nodejs18.x")
    include_body = optional(bool, false)
  }))

  default = {}

  validation {
    condition = alltrue([
      for fn in values(var.ordered_lambda_at_edge) : (
        !fn.enabled || contains(
          ["nodejs18.x", "nodejs16.x", "nodejs14.x", "python3.9", "python3.8"],
          try(fn.runtime, "nodejs18.x")
        )
      )
    ])
    error_message = "If enabled, runtime must be one of: nodejs18.x, nodejs16.x, nodejs14.x, python3.9, python3.8"
  }

  validation {
    condition = alltrue([
      for fn in values(var.ordered_lambda_at_edge) : (
        !fn.enabled || (
          can(fn.zip_path) &&
          length(trim(fn.zip_path, " \t\r\n")) > 0 &&
          can(regex("\\.zip$", fn.zip_path))
        )
      )
    ])
    error_message = "zip_path must be a non-empty string ending in .zip if enabled"
  }
}

############################################
# CloudWatch Logging
############################################

variable "lambda_edge_log_prevent_destroy" {
  description = "Whether to prevent destroy for Lambda@Edge log groups"
  type        = bool
  default     = true
}

variable "lambda_edge_log_retention_days" {
  description = "Retention period in days for Lambda@Edge log groups"
  type        = number
  default     = 30
}

############################################
# CloudFront Distribution Configuration
############################################

variable "cloudfront" {
  description = "Full configuration for the CloudFront distribution"
  type = object({
    aliases             = optional(list(string), [])
    comment             = optional(string, "Managed by Terraform")
    enabled             = optional(bool, true)
    http_version        = optional(string, "http2")
    ipv6_enabled        = optional(bool, true)
    price_class         = optional(string, "PriceClass_All")
    wait_for_deployment = optional(bool, true)
    web_acl_id          = optional(string, null)
    default_root_object = optional(string, "index.html")

    logging = optional(object({
      enabled         = optional(bool, false)
      bucket          = optional(string, "")
      prefix          = optional(string, "")
      include_cookies = optional(bool, false)
      }), {
      enabled         = false
      bucket          = ""
      prefix          = ""
      include_cookies = false
    })

    geo_restriction = optional(object({
      restriction_type = optional(string, "none")
      locations        = optional(list(string), [])
      }), {
      restriction_type = "none"
      locations        = []
    })
  })

  validation {
    condition     = var.viewer_certificate.use_default_certificate || length(var.cloudfront.aliases) > 0
    error_message = "You must provide at least one alias when use_default_certificate is false."
  }

  validation {
    condition = (
      try(var.viewer_certificate.use_default_certificate, true) ||
      length(try(var.cloudfront.aliases, [])) > 0
    )
    error_message = "You must provide at least one alias when use_default_certificate is false."
  }

  validation {
    condition = contains(
      ["http1.1", "http2", "http3"],
      try(var.cloudfront.http_version, "http2")
    )
    error_message = "http_version must be one of: http1.1, http2, http3."
  }

  validation {
    condition = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"],
      try(var.cloudfront.price_class, "PriceClass_All")
    )
    error_message = "price_class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }

  validation {
    condition = (!try(var.cloudfront.logging.enabled, false) ||
    length(trim(try(var.cloudfront.logging.bucket, ""), " \t\n")) > 0)
    error_message = "If cloudfront_logging.enabled is true, bucket must be set."
  }

  validation {
    condition = (
      try(var.cloudfront.logging.enabled, false) ||
      try(var.cloudfront.logging.prefix, "") == ""
    )
    error_message = "Prefix must be empty when logging is disabled."
  }

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], try(var.cloudfront.geo_restriction.restriction_type, "none"))
    error_message = "geo_restriction.restriction_type must be one of: none, whitelist, blacklist."
  }

  validation {
    condition = (
      (try(var.cloudfront.geo_restriction.restriction_type, "none") == "none" && length(try(var.cloudfront.geo_restriction.locations, [])) == 0) ||
      (try(var.cloudfront.geo_restriction.restriction_type, "none") != "none" && length(try(var.cloudfront.geo_restriction.locations, [])) > 0)
    )
    error_message = "geo_restriction.locations must be empty if type is 'none', or non-empty if type is 'whitelist' or 'blacklist'."
  }
}

variable "origin" {
  description = "Origin configuration for the CloudFront distribution"

  type = object({
    domain_name     = string
    origin_id       = optional(string, "origin-1")
    http_port       = optional(number, 80)
    https_port      = optional(number, 443)
    protocol_policy = optional(string, "http-only")
    ssl_protocols   = optional(list(string), ["TLSv1.2"])
  })

  validation {
    condition = contains(
      ["http-only", "https-only", "match-viewer"],
      try(var.origin.protocol_policy, "http-only")
    )
    error_message = "protocol_policy must be one of: http-only, https-only, match-viewer."
  }

  validation {
    condition = alltrue([
      for p in try(var.origin.ssl_protocols, ["TLSv1.2"]) :
      contains(["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"], p)
    ])
    error_message = "ssl_protocols must only include: SSLv3, TLSv1, TLSv1.1, TLSv1.2."
  }
}

variable "default_cache_behavior" {
  description = "Configuration for CloudFront default cache behavior"
  type = object({
    target_origin_id       = optional(string, "origin-1")
    viewer_protocol_policy = optional(string, "redirect-to-https")
    allowed_methods        = optional(list(string), ["GET", "HEAD"])
    cached_methods         = optional(list(string), ["GET", "HEAD"])
    compress               = optional(bool, true)
    forward_query_string   = optional(bool, false)
    cookie_forward_policy  = optional(string, "none")
  })

  default = {}

  validation {
    condition = contains(
      ["none", "all", "whitelist"],
      try(var.default_cache_behavior.cookie_forward_policy, "none")
    )
    error_message = "cookie_forward_policy must be one of: none, all, whitelist."
  }

  validation {
    condition = contains(
      ["allow-all", "redirect-to-https", "https-only"],
      try(var.default_cache_behavior.viewer_protocol_policy, "redirect-to-https")
    )
    error_message = "viewer_protocol_policy must be one of: allow-all, redirect-to-https, https-only."
  }

  validation {
    condition = alltrue([
      for m in try(var.default_cache_behavior.allowed_methods, ["GET", "HEAD"]) :
      contains(["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"], m)
    ])
    error_message = "allowed_methods can only include: GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE."
  }

  validation {
    condition = alltrue([
      for m in try(var.default_cache_behavior.cached_methods, ["GET", "HEAD"]) :
      contains(["GET", "HEAD"], m)
    ])
    error_message = "cached_methods can only include: GET and HEAD."
  }
}

variable "ordered_cache_behaviors" {
  description = "List of ordered cache behaviors"
  type = list(object({
    path_pattern           = string
    target_origin_id       = optional(string, "origin-1")
    viewer_protocol_policy = optional(string, "redirect-to-https")
    allowed_methods        = optional(list(string), ["GET", "HEAD"])
    cached_methods         = optional(list(string), ["GET", "HEAD"])
    compress               = optional(bool, true)
    forward_query_string   = optional(bool, false)
    cookie_forward_policy  = optional(string, "none")
    lambda_key             = optional(string)
    lambda_event_type      = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for cb in var.ordered_cache_behaviors :
      contains(["none", "all", "whitelist"], try(cb.cookie_forward_policy, "none"))
    ])
    error_message = "cookie_forward_policy must be one of: none, all, whitelist."
  }

  validation {
    condition = alltrue([
      for cb in var.ordered_cache_behaviors :
      contains(["allow-all", "redirect-to-https", "https-only"], try(cb.viewer_protocol_policy, "redirect-to-https"))
    ])
    error_message = "viewer_protocol_policy must be one of: allow-all, redirect-to-https, https-only."
  }

  validation {
    condition = alltrue([
      for cb in var.ordered_cache_behaviors :
      alltrue([
        for m in try(cb.allowed_methods, ["GET", "HEAD"]) :
        contains(["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"], m)
      ])
    ])
    error_message = "allowed_methods can only include: GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE."
  }

  validation {
    condition = alltrue([
      for cb in var.ordered_cache_behaviors :
      alltrue([
        for m in try(cb.cached_methods, ["GET", "HEAD"]) :
        contains(["GET", "HEAD"], m)
      ])
    ])
    error_message = "cached_methods can only include: GET and HEAD."
  }

  validation {
    condition     = length(var.ordered_cache_behaviors) <= 25
    error_message = "A maximum of 25 ordered_cache_behavior entries are allowed in CloudFront."
  }
}

variable "viewer_certificate" {
  description = "Viewer certificate configuration for CloudFront"
  type = object({
    use_default_certificate  = bool
    acm_certificate_arn      = optional(string)
    ssl_support_method       = optional(string)
    ssl_min_protocol_version = optional(string, "TLSv1")
  })

  default = {
    use_default_certificate  = true
    acm_certificate_arn      = null
    ssl_support_method       = null
    ssl_min_protocol_version = "TLSv1"
  }

  # ACM ARN must be valid and in us-east-1 if not using default certificate
  validation {
    condition = var.viewer_certificate.use_default_certificate || (
      can(trim(var.viewer_certificate.acm_certificate_arn, " \t\n")) &&
      (
        can(regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/[a-zA-Z0-9-]+$", var.viewer_certificate.acm_certificate_arn)) ?
        regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/[a-zA-Z0-9-]+$", var.viewer_certificate.acm_certificate_arn) != null :
        false
      )
    )
    error_message = "acm_certificate_arn must be a valid ACM certificate ARN from us-east-1 when use_default_certificate is false."
  }

  # ssl_support_method required if using custom certificate
  validation {
    condition = var.viewer_certificate.use_default_certificate || (
      var.viewer_certificate.ssl_support_method != null ?
      contains(["vip", "sni-only", "static-ip"], var.viewer_certificate.ssl_support_method) :
      false
    )
    error_message = "ssl_support_method must be one of vip, sni-only, or static-ip if use_default_certificate is false."
  }

  # ssl_min_protocol_version must match allowed values
  validation {
    condition = contains([
      "SSLv3",
      "TLSv1",
      "TLSv1_2016",
      "TLSv1.1_2016",
      "TLSv1.2_2018",
      "TLSv1.2_2019",
      "TLSv1.2_2021"
    ], try(var.viewer_certificate.ssl_min_protocol_version, ""))
    error_message = "ssl_min_protocol_version must be a valid CloudFront value: SSLv3, TLSv1, TLSv1_2016, TLSv1.1_2016, TLSv1.2_2018, TLSv1.2_2019, TLSv1.2_2021"
  }

  # if use_default_certificate = true, ssl_min_protocol_version must be TLSv1
  validation {
    condition = (
      var.viewer_certificate.use_default_certificate ?
      var.viewer_certificate.ssl_min_protocol_version == "TLSv1" :
      true
    )
    error_message = "If use_default_certificate is true, ssl_min_protocol_version must be TLSv1."
  }

  # if using VIP, only SSLv3 or TLSv1 allowed
  validation {
    condition = (
      try(var.viewer_certificate.ssl_support_method, "") != "vip" ||
      contains(["SSLv3", "TLSv1"], try(var.viewer_certificate.ssl_min_protocol_version, ""))
    )
    error_message = "If ssl_support_method is 'vip', ssl_min_protocol_version must be SSLv3 or TLSv1."
  }

  # if using sni-only, must be TLSv1 or later
  validation {
    condition = (
      try(var.viewer_certificate.ssl_support_method, "") != "sni-only" ||
      contains([
        "TLSv1",
        "TLSv1_2016",
        "TLSv1.1_2016",
        "TLSv1.2_2018",
        "TLSv1.2_2019",
        "TLSv1.2_2021"
      ], try(var.viewer_certificate.ssl_min_protocol_version, ""))
    )
    error_message = "If ssl_support_method is 'sni-only', ssl_min_protocol_version must be TLSv1 or later."
  }
}
