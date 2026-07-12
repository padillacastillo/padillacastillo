import json
import os
import re

import boto3

ses = boto3.client("ses")

CONTACT_EMAIL = os.environ["CONTACT_EMAIL"]
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
MAX_LEN = {"name": 100, "email": 200, "message": 2000}


def handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON body"})

    # Honeypot: real visitors never fill this in. Bots that auto-fill every
    # field will trip it; pretend success so they don't learn to skip it.
    if body.get("company"):
        return _response(200, {"ok": True})

    name = str(body.get("name", "")).strip()
    email = str(body.get("email", "")).strip()
    message = str(body.get("message", "")).strip()

    if not name or not email or not message:
        return _response(400, {"error": "Missing required field"})
    if not EMAIL_RE.match(email):
        return _response(400, {"error": "Invalid email address"})
    if len(name) > MAX_LEN["name"] or len(email) > MAX_LEN["email"] or len(message) > MAX_LEN["message"]:
        return _response(400, {"error": "Field too long"})

    ses.send_email(
        Source=CONTACT_EMAIL,
        Destination={"ToAddresses": [CONTACT_EMAIL]},
        ReplyToAddresses=[email],
        Message={
            "Subject": {"Data": f"padillacastillo.com contact form: {name}"},
            "Body": {"Text": {"Data": f"From: {name} <{email}>\n\n{message}"}},
        },
    )

    return _response(200, {"ok": True})


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
