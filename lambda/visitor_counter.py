import hashlib
import hmac
import json
import os
from decimal import Decimal
from typing import cast

import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
secrets = boto3.client("secretsmanager")

TABLE_NAME = os.environ["TABLE_NAME"]
SECRET_ARN = os.environ["SECRET_ARN"]

table = dynamodb.Table(TABLE_NAME)

# Fetched once per cold start, reused across warm invocations.
_HMAC_KEY = secrets.get_secret_value(SecretId=SECRET_ARN)["SecretString"].encode()


def handler(event, context):
    source_ip = event["requestContext"]["http"]["sourceIp"]
    visitor_hash = hmac.new(_HMAC_KEY, source_ip.encode(), hashlib.sha256).hexdigest()

    if _record_visitor(visitor_hash):
        updated = table.update_item(
            Key={"pk": "COUNT"},
            UpdateExpression="ADD #c :incr",
            ExpressionAttributeNames={"#c": "count"},
            ExpressionAttributeValues={":incr": 1},
            ReturnValues="UPDATED_NEW",
        )
        count = cast(Decimal, updated["Attributes"]["count"])
    else:
        item = table.get_item(Key={"pk": "COUNT"}).get("Item")
        count = cast(Decimal, item["count"]) if item else Decimal(0)

    return _response(200, {"count": int(count)})


def _record_visitor(visitor_hash):
    # Conditional put only succeeds the first time this IP's hash is seen, so
    # repeat visits from the same IP never increment the count again.
    try:
        table.put_item(
            Item={"pk": f"VISITOR#{visitor_hash}"},
            ConditionExpression="attribute_not_exists(pk)",
        )
        return True
    except ClientError as err:
        if err.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            return False
        raise


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
