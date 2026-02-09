"""
RDS Recovery Lambda
===================
Automatically recovers RDS instances from failure states by
rebooting or restoring from the latest automated snapshot.

Triggered by EventBridge RDS instance state change events.

Flow:
  1. Receive RDS failure event
  2. Check instance status
  3. Attempt reboot first (less disruptive)
  4. If reboot fails, identify latest snapshot for manual restore
  5. Notify via SNS with recovery status
"""

import json
import logging
import os
import time

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds = boto3.client("rds")
sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "unknown")
RDS_INSTANCE = os.environ.get("RDS_INSTANCE", "")


def lambda_handler(event, context):
    """Main handler for RDS recovery."""
    logger.info("Received event: %s", json.dumps(event))

    db_instance_id = extract_instance_id(event)
    if not db_instance_id:
        logger.info("No RDS instance ID found, using configured: %s", RDS_INSTANCE)
        db_instance_id = RDS_INSTANCE

    if not db_instance_id:
        return {"statusCode": 200, "body": "No RDS instance to process"}

    return remediate_rds(db_instance_id)


def extract_instance_id(event):
    """Extract RDS instance identifier from EventBridge event."""
    try:
        detail = event.get("detail", {})
        source_id = detail.get("SourceIdentifier", "")
        if source_id:
            return source_id

        # Try ARN-based extraction
        source_arn = detail.get("SourceArn", "")
        if ":db:" in source_arn:
            return source_arn.split(":")[-1]
    except (KeyError, TypeError):
        pass
    return ""


def remediate_rds(db_instance_id):
    """Attempt to recover an RDS instance."""
    logger.info("Checking RDS instance: %s", db_instance_id)

    try:
        response = rds.describe_db_instances(DBInstanceIdentifier=db_instance_id)
        instances = response.get("DBInstances", [])

        if not instances:
            return {
                "statusCode": 404,
                "body": f"RDS instance {db_instance_id} not found",
            }

        instance = instances[0]
        status = instance.get("DBInstanceStatus", "unknown")
        engine = instance.get("Engine", "unknown")

        logger.info("RDS %s status: %s, engine: %s", db_instance_id, status, engine)

        if status == "available":
            msg = f"RDS instance {db_instance_id} is available. No action needed."
            logger.info(msg)
            return {"statusCode": 200, "body": msg}

        if status in ("failed", "incompatible-restore", "incompatible-network"):
            return handle_failed_state(db_instance_id, status, engine)

        if status in ("rebooting", "modifying", "backing-up", "creating"):
            msg = f"RDS instance {db_instance_id} is in '{status}' state. Monitoring."
            logger.info(msg)
            send_notification(db_instance_id, "MONITORING", msg)
            return {"statusCode": 200, "body": msg}

        if status == "stopped":
            return start_rds_instance(db_instance_id)

        # For any other state, attempt a reboot
        return reboot_rds_instance(db_instance_id)

    except ClientError as e:
        error_msg = f"Error checking RDS instance {db_instance_id}: {e}"
        logger.error(error_msg)
        return {"statusCode": 500, "body": error_msg}


def reboot_rds_instance(db_instance_id):
    """Reboot an RDS instance."""
    try:
        logger.info("Rebooting RDS instance: %s", db_instance_id)
        rds.reboot_db_instance(
            DBInstanceIdentifier=db_instance_id,
            ForceFailover=False,
        )
        msg = f"Successfully initiated reboot of RDS instance {db_instance_id}"
        logger.info(msg)
        send_notification(db_instance_id, "REBOOTED", msg)
        return {"statusCode": 200, "body": msg}
    except ClientError as e:
        error_msg = f"Failed to reboot RDS instance {db_instance_id}: {e}"
        logger.error(error_msg)
        send_notification(db_instance_id, "REBOOT_FAILED", error_msg)
        return {"statusCode": 500, "body": error_msg}


def start_rds_instance(db_instance_id):
    """Start a stopped RDS instance."""
    try:
        logger.info("Starting RDS instance: %s", db_instance_id)
        rds.start_db_instance(DBInstanceIdentifier=db_instance_id)
        msg = f"Successfully initiated start of RDS instance {db_instance_id}"
        logger.info(msg)
        send_notification(db_instance_id, "STARTED", msg)
        return {"statusCode": 200, "body": msg}
    except ClientError as e:
        error_msg = f"Failed to start RDS instance {db_instance_id}: {e}"
        logger.error(error_msg)
        return {"statusCode": 500, "body": error_msg}


def handle_failed_state(db_instance_id, status, engine):
    """Handle RDS instances in a failed state by finding the latest snapshot."""
    logger.warning("RDS %s in failed state: %s", db_instance_id, status)

    try:
        # Find the latest automated snapshot
        snapshots = rds.describe_db_snapshots(
            DBInstanceIdentifier=db_instance_id,
            SnapshotType="automated",
        ).get("DBSnapshots", [])

        if not snapshots:
            msg = (
                f"RDS instance {db_instance_id} is in '{status}' state "
                f"but no automated snapshots found. MANUAL INTERVENTION REQUIRED."
            )
            logger.error(msg)
            send_notification(db_instance_id, "NO_SNAPSHOTS", msg)
            return {"statusCode": 500, "body": msg}

        # Sort by creation time, newest first
        snapshots.sort(key=lambda s: s.get("SnapshotCreateTime", ""), reverse=True)
        latest = snapshots[0]
        snapshot_id = latest["DBSnapshotIdentifier"]
        snapshot_time = str(latest.get("SnapshotCreateTime", "unknown"))

        msg = (
            f"RDS instance {db_instance_id} is in '{status}' state. "
            f"Latest snapshot: {snapshot_id} (created: {snapshot_time}). "
            f"Automated restore is available but requires manual approval for safety. "
            f"Use: aws rds restore-db-instance-from-db-snapshot "
            f"--db-instance-identifier {db_instance_id}-restored "
            f"--db-snapshot-identifier {snapshot_id}"
        )
        logger.info(msg)
        send_notification(db_instance_id, "SNAPSHOT_IDENTIFIED", msg)
        return {"statusCode": 200, "body": msg}

    except ClientError as e:
        error_msg = f"Error finding snapshots for {db_instance_id}: {e}"
        logger.error(error_msg)
        return {"statusCode": 500, "body": error_msg}


def send_notification(db_instance_id, action, message):
    """Send remediation notification via SNS."""
    if not SNS_TOPIC_ARN:
        return
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[{ENVIRONMENT.upper()}] RDS Auto-Heal: {action} - {db_instance_id}",
            Message=json.dumps(
                {
                    "environment": ENVIRONMENT,
                    "rds_instance": db_instance_id,
                    "action": action,
                    "message": message,
                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                },
                indent=2,
            ),
        )
    except ClientError as e:
        logger.error("Failed to send SNS notification: %s", e)
