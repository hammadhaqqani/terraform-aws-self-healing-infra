"""
Security Group Remediation Lambda
==================================
Automatically revokes insecure security group rules that allow
ingress from 0.0.0.0/0 or ::/0 on sensitive ports.

Triggered by EventBridge when AuthorizeSecurityGroupIngress or
ModifySecurityGroupRules API calls are detected via CloudTrail.

Flow:
  1. Receive EventBridge event with security group change details
  2. Inspect the security group for overly permissive rules
  3. Revoke any rules allowing 0.0.0.0/0 or ::/0 on restricted ports
  4. Notify via SNS
"""

import json
import logging
import os
import time

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "unknown")

# Ports that should never be open to the internet
RESTRICTED_PORTS = {22, 3389, 3306, 5432, 1433, 6379, 27017, 9200, 5601}
OPEN_CIDRS = {"0.0.0.0/0", "::/0"}


def lambda_handler(event, context):
    """Main handler for security group remediation."""
    logger.info("Received event: %s", json.dumps(event))

    sg_id = extract_security_group_id(event)
    if not sg_id:
        logger.info("No security group ID found in event")
        return {"statusCode": 200, "body": "No security group to process"}

    return remediate_security_group(sg_id)


def extract_security_group_id(event):
    """Extract security group ID from EventBridge/CloudTrail event."""
    try:
        detail = event.get("detail", {})
        request_params = detail.get("requestParameters", {})

        # AuthorizeSecurityGroupIngress
        sg_id = request_params.get("groupId", "")
        if sg_id:
            return sg_id

        # Check response elements
        response = detail.get("responseElements", {})
        if response and isinstance(response, dict):
            sg_id = response.get("groupId", "")
            if sg_id:
                return sg_id

    except (KeyError, TypeError) as e:
        logger.error("Error extracting SG ID: %s", e)

    return None


def remediate_security_group(sg_id):
    """Check and revoke insecure ingress rules."""
    logger.info("Checking security group: %s", sg_id)

    try:
        response = ec2.describe_security_groups(GroupIds=[sg_id])
        security_groups = response.get("SecurityGroups", [])

        if not security_groups:
            return {"statusCode": 404, "body": f"Security group {sg_id} not found"}

        sg = security_groups[0]
        sg_name = sg.get("GroupName", "unknown")
        revoked_rules = []

        for permission in sg.get("IpPermissions", []):
            from_port = permission.get("FromPort", 0)
            to_port = permission.get("ToPort", 65535)
            protocol = permission.get("IpProtocol", "-1")

            # Check IPv4 ranges
            for ip_range in permission.get("IpRanges", []):
                cidr = ip_range.get("CidrIp", "")
                if cidr in OPEN_CIDRS and is_restricted(from_port, to_port, protocol):
                    revoke_rule(sg_id, permission, "ipv4", cidr)
                    revoked_rules.append(
                        f"{protocol}:{from_port}-{to_port} from {cidr}"
                    )

            # Check IPv6 ranges
            for ip_range in permission.get("Ipv6Ranges", []):
                cidr = ip_range.get("CidrIpv6", "")
                if cidr in OPEN_CIDRS and is_restricted(from_port, to_port, protocol):
                    revoke_rule(sg_id, permission, "ipv6", cidr)
                    revoked_rules.append(
                        f"{protocol}:{from_port}-{to_port} from {cidr}"
                    )

        if revoked_rules:
            msg = (
                f"Revoked {len(revoked_rules)} insecure rule(s) from {sg_id} ({sg_name}): "
                + "; ".join(revoked_rules)
            )
            logger.info(msg)
            send_notification(sg_id, sg_name, "RULES_REVOKED", msg, revoked_rules)
        else:
            msg = f"No insecure rules found in {sg_id} ({sg_name})"
            logger.info(msg)

        return {"statusCode": 200, "body": msg, "revoked": len(revoked_rules)}

    except ClientError as e:
        error_msg = f"Error processing security group {sg_id}: {e}"
        logger.error(error_msg)
        return {"statusCode": 500, "body": error_msg}


def is_restricted(from_port, to_port, protocol):
    """Check if a port range includes restricted ports or is fully open."""
    if protocol == "-1":  # All traffic
        return True
    if from_port == 0 and to_port == 65535:
        return True
    for port in RESTRICTED_PORTS:
        if from_port <= port <= to_port:
            return True
    return False


def revoke_rule(sg_id, permission, ip_version, cidr):
    """Revoke a specific ingress rule."""
    try:
        if ip_version == "ipv4":
            ec2.revoke_security_group_ingress(
                GroupId=sg_id,
                IpPermissions=[
                    {
                        "IpProtocol": permission["IpProtocol"],
                        "FromPort": permission.get("FromPort", 0),
                        "ToPort": permission.get("ToPort", 65535),
                        "IpRanges": [{"CidrIp": cidr}],
                    }
                ],
            )
        else:
            ec2.revoke_security_group_ingress(
                GroupId=sg_id,
                IpPermissions=[
                    {
                        "IpProtocol": permission["IpProtocol"],
                        "FromPort": permission.get("FromPort", 0),
                        "ToPort": permission.get("ToPort", 65535),
                        "Ipv6Ranges": [{"CidrIpv6": cidr}],
                    }
                ],
            )
        logger.info("Revoked %s rule from %s: %s", ip_version, sg_id, cidr)
    except ClientError as e:
        logger.error("Failed to revoke rule from %s: %s", sg_id, e)


def send_notification(sg_id, sg_name, action, message, revoked_rules):
    """Send remediation notification via SNS."""
    if not SNS_TOPIC_ARN:
        return
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[{ENVIRONMENT.upper()}] SG Auto-Heal: {action} - {sg_id}",
            Message=json.dumps(
                {
                    "environment": ENVIRONMENT,
                    "security_group_id": sg_id,
                    "security_group_name": sg_name,
                    "action": action,
                    "revoked_rules": revoked_rules,
                    "message": message,
                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                },
                indent=2,
            ),
        )
    except ClientError as e:
        logger.error("Failed to send SNS notification: %s", e)
