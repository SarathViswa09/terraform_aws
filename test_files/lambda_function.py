import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    for record in event.get('Records', []):
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        message = f"A new file is uploaded to S3: bucket={bucket}, key={key}"
        logger.info(message)
        print(message)
    return {
        'statusCode': 200,
        'body': json.dumps('Processed')
    }
