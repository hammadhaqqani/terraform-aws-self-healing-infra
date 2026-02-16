# Terraform AWS Self-Healing Infrastructure

[![Terraform](https://github.com/hammadhaqqani/terraform-aws-self-healing-infra/actions/workflows/terraform.yml/badge.svg)](https://github.com/hammadhaqqani/terraform-aws-self-healing-infra/actions/workflows/terraform.yml)
[![GitHub Pages](https://github.com/hammadhaqqani/terraform-aws-self-healing-infra/actions/workflows/pages.yml/badge.svg)](https://hammadhaqqani.github.io/terraform-aws-self-healing-infra/)
[![Terraform](https://img.shields.io/badge/Terraform-1.5+-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-CloudWatch%20%7C%20Lambda%20%7C%20EventBridge-FF9900?logo=amazonaws)](https://aws.amazon.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Production-ready Terraform modules for building **self-healing AWS infrastructure**. Automatically detect, respond to, and remediate common infrastructure failures using CloudWatch, Lambda, EventBridge, and SNS.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    AWS Self-Healing Architecture                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────────┐  │
│  │  CloudWatch  │───▶│  EventBridge │───▶│  Lambda Functions  │  │
│  │   Alarms     │    │    Rules     │    │  (Remediation)     │  │
│  └──────┬──────┘    └──────────────┘    └────────┬───────────┘  │
│         │                                         │              │
│         ▼                                         ▼              │
│  ┌─────────────┐                         ┌───────────────────┐  │
│  │     SNS      │                         │  Target Services  │  │
│  │  (Alerts)    │                         │  EC2 | ECS | RDS  │  │
│  └──────┬──────┘                         │  Security Groups  │  │
│         │                                 └───────────────────┘  │
│         ▼                                                        │
│  ┌─────────────┐                                                 │
│  │ Slack/Email  │                                                │
│  │ PagerDuty   │                                                 │
│  └─────────────┘                                                 │
└──────────────────────────────────────────────────────────────────┘
```

## What It Does

| Failure Scenario | Detection | Auto-Remediation |
|---|---|---|
| EC2 instance stops unexpectedly | CloudWatch StatusCheckFailed | Lambda restarts the instance |
| ECS service drops below desired count | CloudWatch RunningTaskCount | Lambda forces new deployment |
| Security group opened to 0.0.0.0/0 | EventBridge Config change | Lambda revokes the offending rule |
| RDS instance enters failed state | EventBridge RDS event | Lambda restores from latest snapshot |

## Quick Start

```bash
git clone https://github.com/hammadhaqqani/terraform-aws-self-healing-infra.git
cd terraform-aws-self-healing-infra/examples/complete

# Configure your environment
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

## Module Structure

```
.
├── modules/
│   ├── cloudwatch-alarms/      # CloudWatch alarm definitions
│   ├── sns-notifications/      # SNS topics and subscriptions
│   ├── lambda-remediation/     # Lambda function deployment + IAM
│   └── eventbridge-rules/      # EventBridge rules for event-driven healing
├── lambdas/
│   ├── ec2-auto-restart/       # Auto-restart stopped/failed EC2 instances
│   ├── ecs-auto-scale/         # Auto-scale ECS services on task failures
│   ├── sg-remediation/         # Revert unauthorized security group changes
│   └── rds-recovery/           # Auto-recover failed RDS instances
├── examples/
│   └── complete/               # Full working example
└── .github/
    └── workflows/              # CI/CD with Terraform validation
```

## Modules

### CloudWatch Alarms

Creates CloudWatch alarms for EC2, ECS, and RDS health monitoring.

```hcl
module "alarms" {
  source = "./modules/cloudwatch-alarms"

  ec2_instance_ids = ["i-0abc123def456"]
  ecs_cluster_name = "production"
  ecs_service_name = "web-api"
  rds_instance_id  = "prod-database"
  sns_topic_arn    = module.notifications.topic_arn
}
```

### Lambda Remediation

Deploys Lambda functions with least-privilege IAM roles for auto-remediation.

```hcl
module "remediation" {
  source = "./modules/lambda-remediation"

  environment        = "production"
  sns_topic_arn      = module.notifications.topic_arn
  enable_ec2_restart = true
  enable_ecs_scale   = true
  enable_sg_remediate = true
  enable_rds_recover = true
}
```

### EventBridge Rules

Creates EventBridge rules for event-driven remediation (security group changes, RDS failures).

```hcl
module "eventbridge" {
  source = "./modules/eventbridge-rules"

  sg_remediation_lambda_arn  = module.remediation.sg_lambda_arn
  rds_recovery_lambda_arn    = module.remediation.rds_lambda_arn
}
```

## Configuration

| Variable | Description | Default |
|---|---|---|
| `environment` | Environment name (production, staging) | `"production"` |
| `ec2_instance_ids` | List of EC2 instance IDs to monitor | `[]` |
| `ecs_cluster_name` | ECS cluster name | `""` |
| `ecs_service_name` | ECS service name | `""` |
| `rds_instance_id` | RDS instance identifier | `""` |
| `notification_emails` | Email addresses for alerts | `[]` |
| `slack_webhook_url` | Slack webhook for notifications | `""` |
| `enable_auto_remediation` | Master switch for auto-remediation | `true` |

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate credentials
- Python 3.11+ (for Lambda functions)
- AWS account with permissions for CloudWatch, Lambda, EventBridge, SNS, EC2, ECS, RDS, IAM

## Security

- All Lambda functions use **least-privilege IAM policies** scoped to specific resources
- SNS topics are encrypted with AWS KMS
- Lambda functions run in your VPC (optional) with security groups
- All actions are logged to CloudWatch Logs for audit trails
- EventBridge rules use resource-based policies

## Testing

```bash
# Validate Terraform
cd examples/complete
terraform validate

# Test Lambda functions locally
cd lambdas/ec2-auto-restart
pip install -r requirements.txt
python -m pytest tests/
```

## Related Blog Post

This project accompanies my blog post: [Building Self-Healing Infrastructure: Claude Code + CloudWatch + Lambda](https://hammadhaqqani.com/blog/building-self-healing-infrastructure-claude-code)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

**Hammad Haqqani** - DevOps Architect & AI Infrastructure Engineer

- Website: [hammadhaqqani.com](https://hammadhaqqani.com)
- LinkedIn: [linkedin.com/in/haqqani](https://linkedin.com/in/haqqani)
- GitHub: [github.com/hammadhaqqani](https://github.com/hammadhaqqani)
---

## Support

If you find this useful, consider buying me a coffee!

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/hammadhaqqani)
