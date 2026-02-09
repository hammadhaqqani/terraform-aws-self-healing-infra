# =============================================================================
# Lambda Remediation Module
# =============================================================================
# Deploys Lambda functions for automated infrastructure remediation
# with least-privilege IAM roles scoped to specific resources.
# =============================================================================

locals {
  lambda_runtime = "python3.11"
  lambda_timeout = 60
}

# -----------------------------------------------------------------------------
# EC2 Auto-Restart Lambda
# -----------------------------------------------------------------------------
data "archive_file" "ec2_restart" {
  count       = var.enable_ec2_restart ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/ec2-auto-restart"
  output_path = "${path.module}/builds/ec2-auto-restart.zip"
}

resource "aws_lambda_function" "ec2_restart" {
  count = var.enable_ec2_restart ? 1 : 0

  function_name    = "${var.environment}-ec2-auto-restart"
  description      = "Automatically restart EC2 instances that fail status checks"
  runtime          = local.lambda_runtime
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.ec2_restart[0].arn
  timeout          = local.lambda_timeout
  filename         = data.archive_file.ec2_restart[0].output_path
  source_code_hash = data.archive_file.ec2_restart[0].output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = var.sns_topic_arn
      ENVIRONMENT   = var.environment
      INSTANCE_IDS  = join(",", var.ec2_instance_ids)
    }
  }

  tags = merge(var.tags, { Name = "${var.environment}-ec2-auto-restart" })
}

resource "aws_iam_role" "ec2_restart" {
  count = var.enable_ec2_restart ? 1 : 0
  name  = "${var.environment}-ec2-restart-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "ec2_restart" {
  count = var.enable_ec2_restart ? 1 : 0
  name  = "ec2-restart-policy"
  role  = aws_iam_role.ec2_restart[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances", "ec2:RebootInstances", "ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [var.sns_topic_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECS Auto-Scale Lambda
# -----------------------------------------------------------------------------
data "archive_file" "ecs_scale" {
  count       = var.enable_ecs_scale ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/ecs-auto-scale"
  output_path = "${path.module}/builds/ecs-auto-scale.zip"
}

resource "aws_lambda_function" "ecs_scale" {
  count = var.enable_ecs_scale ? 1 : 0

  function_name    = "${var.environment}-ecs-auto-scale"
  description      = "Automatically force new ECS deployment when tasks drop below desired count"
  runtime          = local.lambda_runtime
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.ecs_scale[0].arn
  timeout          = local.lambda_timeout
  filename         = data.archive_file.ecs_scale[0].output_path
  source_code_hash = data.archive_file.ecs_scale[0].output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = var.sns_topic_arn
      ENVIRONMENT   = var.environment
      CLUSTER_NAME  = var.ecs_cluster_name
      SERVICE_NAME  = var.ecs_service_name
    }
  }

  tags = merge(var.tags, { Name = "${var.environment}-ecs-auto-scale" })
}

resource "aws_iam_role" "ecs_scale" {
  count = var.enable_ecs_scale ? 1 : 0
  name  = "${var.environment}-ecs-scale-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "ecs_scale" {
  count = var.enable_ecs_scale ? 1 : 0
  name  = "ecs-scale-policy"
  role  = aws_iam_role.ecs_scale[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices", "ecs:DescribeClusters"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [var.sns_topic_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Security Group Remediation Lambda
# -----------------------------------------------------------------------------
data "archive_file" "sg_remediation" {
  count       = var.enable_sg_remediate ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/sg-remediation"
  output_path = "${path.module}/builds/sg-remediation.zip"
}

resource "aws_lambda_function" "sg_remediation" {
  count = var.enable_sg_remediate ? 1 : 0

  function_name    = "${var.environment}-sg-remediation"
  description      = "Automatically revoke insecure security group rules (0.0.0.0/0 ingress)"
  runtime          = local.lambda_runtime
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.sg_remediation[0].arn
  timeout          = local.lambda_timeout
  filename         = data.archive_file.sg_remediation[0].output_path
  source_code_hash = data.archive_file.sg_remediation[0].output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = var.sns_topic_arn
      ENVIRONMENT   = var.environment
    }
  }

  tags = merge(var.tags, { Name = "${var.environment}-sg-remediation" })
}

resource "aws_iam_role" "sg_remediation" {
  count = var.enable_sg_remediate ? 1 : 0
  name  = "${var.environment}-sg-remediation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "sg_remediation" {
  count = var.enable_sg_remediate ? 1 : 0
  name  = "sg-remediation-policy"
  role  = aws_iam_role.sg_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeSecurityGroups", "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [var.sns_topic_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# RDS Recovery Lambda
# -----------------------------------------------------------------------------
data "archive_file" "rds_recovery" {
  count       = var.enable_rds_recover ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/rds-recovery"
  output_path = "${path.module}/builds/rds-recovery.zip"
}

resource "aws_lambda_function" "rds_recovery" {
  count = var.enable_rds_recover ? 1 : 0

  function_name    = "${var.environment}-rds-recovery"
  description      = "Automatically recover RDS instances from failure using latest snapshot"
  runtime          = local.lambda_runtime
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.rds_recovery[0].arn
  timeout          = 300
  filename         = data.archive_file.rds_recovery[0].output_path
  source_code_hash = data.archive_file.rds_recovery[0].output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = var.sns_topic_arn
      ENVIRONMENT   = var.environment
      RDS_INSTANCE  = var.rds_instance_id
    }
  }

  tags = merge(var.tags, { Name = "${var.environment}-rds-recovery" })
}

resource "aws_iam_role" "rds_recovery" {
  count = var.enable_rds_recover ? 1 : 0
  name  = "${var.environment}-rds-recovery-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "rds_recovery" {
  count = var.enable_rds_recover ? 1 : 0
  name  = "rds-recovery-policy"
  role  = aws_iam_role.rds_recovery[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBSnapshots",
          "rds:RestoreDBInstanceFromDBSnapshot",
          "rds:RebootDBInstance",
          "rds:ModifyDBInstance"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [var.sns_topic_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
