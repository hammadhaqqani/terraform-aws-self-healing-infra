variable "environment" {
  description = "Environment name"
  type        = string
}

variable "notification_emails" {
  description = "Email addresses for notifications"
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack webhook URL"
  type        = string
  default     = ""
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for SNS encryption"
  type        = string
  default     = ""
}
