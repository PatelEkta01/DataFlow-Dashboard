# import boto3
# import csv
# import uuid
# import os
# import time
# import datetime  # ⏰ Add time module to store timestamps

# sns = boto3.client('sns')
# TOPIC_ARN = 'arn:aws:sns:us-east-1:314310821739:dataflow-etl-summary'

# s3 = boto3.client('s3')
# dynamodb = boto3.resource('dynamodb')
# table_name = os.environ['DDB_TABLE']
# table = dynamodb.Table(table_name)

# def lambda_handler(event, context):
#     print("✅ Received event:", event)

#     bucket = event['Records'][0]['s3']['bucket']['name']
#     key = event['Records'][0]['s3']['object']['key']
#     filename = key.split('/')[-1]  # e.g., "data.csv"
#     upload_time = int(time.time())  # 🕓 Add upload timestamp

#     obj = s3.get_object(Bucket=bucket, Key=key)
#     lines = obj['Body'].read().decode('utf-8').splitlines()
#     reader = csv.DictReader(lines)

#     if reader.fieldnames is None or None in reader.fieldnames:
#         print("❌ Invalid CSV: missing or malformed headers.")
#         return {"statusCode": 400, "body": "CSV file missing valid headers."}

#     count = 0
#     skipped = 0  # ✅ Count malformed rows

#     for row in reader:
#         if not isinstance(row, dict) or None in row.keys():
#             print("⚠️ Skipping malformed row:", row)
#             skipped += 1  # ✅ Track skipped rows
#             continue

#         row['record_id'] = str(uuid.uuid4())
#         row['file_name'] = filename
#         row['upload_time'] = upload_time  # 🆕 Add timestamp
#         table.put_item(Item=row)
#         count += 1

#     # ✅ Send Enhanced ETL summary to SNS (non-blocking)
#     try:
#         sns.publish(
#             TopicArn=TOPIC_ARN,
#             Subject="✅ ETL Process Completed with Technical Details",
#             Message=(
#                 f"✅ ETL Summary - Technical Report\n"
#                 f"File: {filename}\n"
#                 f"Bucket: {bucket}\n"
#                 f"Key: {key}\n"
#                 f"Lambda ID: {context.aws_request_id}\n"
#                 f"Upload Time: {datetime.datetime.utcnow().isoformat()} UTC\n\n"
#                 f"--- ETL Operations ---\n"
#                 f"• Total rows processed: {count}\n"
#                 f"• Skipped rows (malformed): {skipped}\n"
#                 f"• UUIDs generated: {count}\n"
#                 f"• Fields added: record_id, file_name, upload_time\n"
#                 f"• Timestamp format: UNIX (epoch seconds)\n"
#                 f"• Headers in file: {', '.join(reader.fieldnames)}"
#             )
#         )
#     except Exception as e:
#         print("⚠️ SNS publish failed:", e)

#     return {
#         "statusCode": 200,
#         "body": f"✅ {count} rows from {filename} processed successfully."
#     }
import boto3
import csv
import uuid
import os
import time
import datetime 
from decimal import Decimal, InvalidOperation


sns = boto3.client('sns')
TOPIC_ARN = 'arn:aws:sns:us-east-1:314310821739:dataflow-etl-summary'

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DDB_TABLE'])

def lambda_handler(event, context):
    print("✅ Received event:", event)

    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    filename = key.split('/')[-1]
    upload_time = int(time.time())

    obj = s3.get_object(Bucket=bucket, Key=key)
    lines = obj['Body'].read().decode('utf-8').splitlines()
    reader = csv.DictReader(lines)

    if reader.fieldnames is None or None in reader.fieldnames:
        print("❌ Invalid CSV: missing or malformed headers.")
        return {"statusCode": 400, "body": "CSV file missing valid headers."}

    count = 0
    skipped = 0

    for row in reader:
        # 🧼 Normalize keys and trim values
        row = {
            k.lower(): v.strip() if isinstance(v, str) else v
            for k, v in row.items()
        }

        notes = []

        # ✅ Handle missing fields
        if not row.get('name'):
            row['name'] = "Unknown"
            notes.append("missing name")
        if not row.get('email'):
            row['email'] = "noemail@example.com"
            notes.append("missing email")

        # ✅ Clean + validate amount
        try:
             row['amount'] = Decimal(row.get('amount', '').strip())
        except (InvalidOperation, ValueError, TypeError, AttributeError):
            row['amount'] = Decimal("0.0")
        notes.append("invalid or missing amount, set to 0.0")

        # ✅ Normalize fields
        row['name'] = row['name'].title()
        row['email'] = row['email'].lower()

        # ✅ Enrich with system metadata
        row['record_id'] = str(uuid.uuid4())
        row['file_name'] = filename
        row['upload_time'] = upload_time
        row['etl_notes'] = ", ".join(notes) if notes else "clean"

        try:
            table.put_item(Item=row)
            count += 1
        except Exception as e:
            print(f"❌ Failed to insert row: {e}")
            skipped += 1
            continue

    # 📬 Send ETL summary via SNS
    try:
       sns.publish(
    TopicArn=TOPIC_ARN,
    Subject="✅ ETL Process Completed with Technical Cleanup",
    Message=(
        f"✅ ETL Summary - Technical Cleanup Report\n"
        f"File: {filename}\n"
        f"Bucket: {bucket}\n"
        f"Key: {key}\n"
        f"Lambda ID: {context.aws_request_id}\n"
        f"Upload Time: {datetime.datetime.utcnow().isoformat()} UTC\n\n"
        f"--- ETL Transformations ---\n"
        f"• Total rows inserted: {count}\n"
        f"• Rows skipped (DynamoDB write failures): {skipped}\n"
        f"• Fields cleaned: name → title case, email → lowercase\n"
        f"• amount: converted to Decimal, defaulted to 0.0 if invalid\n"
        f"• Field 'etl_notes' tracks cleaning actions per row\n"
        f"• Metadata added: record_id, file_name, upload_time\n"
        f"• Timestamp format: UNIX epoch\n"
        f"• Original headers: {', '.join(reader.fieldnames)}"
    )
)

    except Exception as e:
        print("⚠️ SNS publish failed:", e)

    return {
        "statusCode": 200,
        "body": f"✅ {count} rows from {filename} cleaned and processed successfully."
    }
