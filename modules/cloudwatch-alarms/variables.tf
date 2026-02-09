variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ec2_instance_ids" {
  description = "List of EC2 instance IDs to monitor"
  type        = list(string)
  default     = []
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = ""
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
  default     = ""
}

variable "rds_instance_id" {
  description = "RDS instance identifier"
  type        = string
  default     = ""
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
}

variable "ec2_lambda_arn" {
  description = "ARN of EC2 remediation Lambda (empty to disable)"
  type        = string
  default     = ""
}

variable "ecs_lambda_arn" {
  description = "ARN of ECS remediation Lambda (empty to disable)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
