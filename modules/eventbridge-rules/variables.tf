variable "environment" {
  type = string
}

variable "sg_remediation_lambda_arn" {
  type    = string
  default = ""
}

variable "rds_recovery_lambda_arn" {
  type    = string
  default = ""
}

variable "enable_sg_remediation" {
  type    = bool
  default = true
}

variable "enable_rds_recovery" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
