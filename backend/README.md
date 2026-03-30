# Lambda visitor counter backend

This folder contains the AWS Lambda function code that powers the visitor counter for my Cloud Resume Challenge site.

## DynamoDB table

The function expects an existing DynamoDB table:

- **Table name:** `cloud-resume-visitor-count` (or whatever name is set in the environment variable `TABLE_NAME`)
- **Partition key:** `id` (String)

The table is pre‑seeded with a single item:

```json
{
  "id": "visitorCount",
  "visits": 0
}
```

The Lambda function atomically increments the `visits` attribute on this item each time it is invoked.

## Lambda function

File:

- `lambda_increment_visitor_count.py`

Key details:

- **Runtime:** Python 3.x
- Uses `boto3` to call `UpdateItem` with an atomic counter expression:
  - `SET visits = if_not_exists(visits, :start) + :inc`
- Returns an HTTP 200 response with JSON body:

```json
{
  "visits": <current_count>
}
```

### Environment variables

The function uses one environment variable:

- `TABLE_NAME` – name of the DynamoDB table (e.g. `cloud-resume-visitor-count`)

### IAM permissions

The Lambda execution role needs permission to read and update the DynamoDB table, for example:

- `dynamodb:GetItem`
- `dynamodb:UpdateItem`

For initial development, the managed policy `AmazonDynamoDBFullAccess` was attached to the function’s execution role.

## Next steps

This Lambda will be invoked via API Gateway and called from the resume site’s JavaScript to display the live visitor count.