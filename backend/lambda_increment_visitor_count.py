import json
import os
import boto3
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ.get("TABLE_NAME", "cloud-resume-visitor-count"))

def lambda_handler(event, context):
    # Increment the counter atomically and get the new value
    response = table.update_item(
        Key={"id": "visitorCount"},
        UpdateExpression="SET visits = if_not_exists(visits, :start) + :inc",
        ExpressionAttributeValues={
            ":inc": Decimal(1),
            ":start": Decimal(0),
        },
        ReturnValues="UPDATED_NEW",
    )

    new_count = int(response["Attributes"]["visits"])

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"visits": new_count}),
    }