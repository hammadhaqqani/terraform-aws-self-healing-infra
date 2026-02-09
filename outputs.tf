# =============================================================================
# Root Module Outputs
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS notification topic"
  value       = module.notifications.topic_arn
}

output "ec2_lambda_arn" {
  description = "ARN of the EC2 auto-restart Lambda function"
  value       = var.enable_ec2_restart ? module.remediation.ec2_lambda_arn : null
}

output "ecs_lambda_arn" {
  description = "ARN of the ECS auto-scale Lambda function"
  value       = var.enable_ecs_scale ? module.remediation.ecs_lambda_arn : null
}

output "sg_lambda_arn" {
  description = "ARN of the security group remediation Lambda function"
  value       = var.enable_sg_remediate ? module.remediation.sg_lambda_arn : null
}

output "rds_lambda_arn" {
  description = "ARN of the RDS recovery Lambda function"
  value       = var.enable_rds_recover ? module.remediation.rds_lambda_arn : null
}

output "cloudwatch_alarm_arns" {
  description = "ARNs of all CloudWatch alarms"
  value       = module.alarms.alarm_arns
}
