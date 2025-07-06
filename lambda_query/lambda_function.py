import boto3
import json
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DDB_TABLE'])

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj == int(obj) else float(obj)
        return super().default(obj)

def lambda_handler(event, context):
    try:
        response = table.scan()
        items = response.get('Items', [])

        if not items:
            return {
                'statusCode': 200,
                'headers': {"Access-Control-Allow-Origin": "*"},
                'body': json.dumps([])
            }

        # Find the latest upload_time
        latest_time = max(item.get('upload_time', 0) for item in items)

        # Filter only those rows
        filtered_items = [item for item in items if item.get('upload_time') == latest_time]

        return {
            'statusCode': 200,
            'headers': {
                "Access-Control-Allow-Origin": "*",
                "Content-Type": "application/json"
            },
            'body': json.dumps(filtered_items, cls=DecimalEncoder)
        }

    except Exception as e:
        print("❌ Lambda Exception:", str(e))
        return {
            'statusCode': 500,
            'headers': {"Access-Control-Allow-Origin": "*"},
            'body': json.dumps({"error": str(e)})
        }
