############################################
# Outputs: Lambda@Edge Functions
############################################

output "lambda_edge_function_arns" {
  description = "Qualified ARNs for each enabled Lambda@Edge function"
  value = {
    for k in keys(try(aws_lambda_function.lambda_edge, {})) :
    k => try(aws_lambda_function.lambda_edge[k].qualified_arn, null)
  }
}

output "lambda_edge_function_names" {
  description = "Function names for each enabled Lambda@Edge function"
  value = {
    for k in keys(try(aws_lambda_function.lambda_edge, {})) :
    k => try(aws_lambda_function.lambda_edge[k].function_name, null)
  }
}

output "lambda_edge_log_groups" {
  description = "Log group names for each enabled Lambda@Edge function"
  value = concat(
    [for lg in values(try(aws_cloudwatch_log_group.lambda_logs_prevent_destroy, {})) : lg.name],
    [for lg in values(try(aws_cloudwatch_log_group.lambda_logs_no_prevent_destroy, {})) : lg.name]
  )
}

output "lambda_edge_iam_role_arn" {
  description = "IAM Role ARN used by Lambda@Edge functions (if created)"
  value       = try(aws_iam_role.lambda_edge[0].arn, null)
}

output "lambda_edge_iam_policy_name" {
  description = "IAM policy name for log permissions (if created)"
  value       = try(aws_iam_role_policy.lambda_edge_logs[0].name, null)
}

############################################
# Outputs: CloudFront Distribution
############################################

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = try(aws_cloudfront_distribution.this.id, null)
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = try(aws_cloudfront_distribution.this.arn, null)
}

output "cloudfront_distribution_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = try(aws_cloudfront_distribution.this.domain_name, null)
}

output "cloudfront_distribution_status" {
  description = "Deployment status of the CloudFront distribution"
  value       = try(aws_cloudfront_distribution.this.status, null)
}
