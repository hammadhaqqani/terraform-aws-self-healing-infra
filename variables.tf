# =============================================================================
# Root Module Variables
# =============================================================================

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "ec2_instance_ids" {
  description = "List of EC2 instance IDs to monitor and auto-heal"
  type        = list(string)
  default     = []
}

variable "ecs_cluster_name" {
  description = "ECS cluster name to monitor"
  type        = string
  default     = ""
}

variable "ecs_service_name" {
  description = "ECS service name to monitor"
  type        = string
  default     = ""
}

variable "rds_instance_id" {
  description = "RDS instance identifier to monitor"
  type        = string
  default     = ""
}

variable "notification_emails" {
  description = "List of email addresses for alert notifications"
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for SNS topic encryption (optional, uses AWS managed key if not set)"
  type        = string
  default     = ""
}

variable "enable_ec2_restart" {
  description = "Enable automatic EC2 instance restart on failure"
  type        = bool
  default     = true
}

variable "enable_ecs_scale" {
  description = "Enable automatic ECS service scaling on task failures"
  type        = bool
  default     = true
}

variable "enable_sg_remediate" {
  description = "Enable automatic security group remediation"
  type        = bool
  default     = true
}

variable "enable_rds_recover" {
  description = "Enable automatic RDS recovery from failures"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Project   = "self-healing-infra"
  }
}
