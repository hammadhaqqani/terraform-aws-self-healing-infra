output "ec2_lambda_arn" {
  description = "ARN of EC2 auto-restart Lambda"
  value       = var.enable_ec2_restart ? aws_lambda_function.ec2_restart[0].arn : ""
}

output "ecs_lambda_arn" {
  description = "ARN of ECS auto-scale Lambda"
  value       = var.enable_ecs_scale ? aws_lambda_function.ecs_scale[0].arn : ""
}

output "sg_lambda_arn" {
  description = "ARN of security group remediation Lambda"
  value       = var.enable_sg_remediate ? aws_lambda_function.sg_remediation[0].arn : ""
}

output "rds_lambda_arn" {
  description = "ARN of RDS recovery Lambda"
  value       = var.enable_rds_recover ? aws_lambda_function.rds_recovery[0].arn : ""
}
