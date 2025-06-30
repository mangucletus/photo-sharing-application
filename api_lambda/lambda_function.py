import json
import boto3
from boto3.dynamodb.conditions import Key
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['METADATA_TABLE'])

def decimal_default(obj):
    """JSON serializer for DynamoDB Decimal types"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    try:
        # Enable CORS
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
        }
        
        # Handle preflight requests
        if event['httpMethod'] == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': ''
            }
        
        # Get user ID from query parameters or path
        user_id = None
        
        # Try to get user_id from query parameters
        query_params = event.get('queryStringParameters') or {}
        user_id = query_params.get('user_id')
        
        # Try to get user_id from path parameters
        if not user_id:
            path_params = event.get('pathParameters') or {}
            user_id = path_params.get('user_id')
        
        # Try to get user_id from body (for POST requests)
        if not user_id and event.get('body'):
            try:
                body = json.loads(event['body'])
                user_id = body.get('user_id')
            except:
                pass
        
        if not user_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({
                    'error': 'user_id is required',
                    'message': 'Please provide user_id in query parameters, path, or request body'
                })
            }
        
        # Handle different HTTP methods
        if event['httpMethod'] == 'GET':
            return get_user_images(user_id, headers)
        else:
            return {
                'statusCode': 405,
                'headers': headers,
                'body': json.dumps({'error': 'Method not allowed'})
            }
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }

def get_user_images(user_id, headers):
    """Fetch all images for a specific user"""
    try:
        # Query DynamoDB for user's images using GSI
        response = table.query(
            IndexName='user-id-index',
            KeyConditionExpression=Key('user_id').eq(user_id),
            ScanIndexForward=False,  # Sort by sort key descending (newest first)
            FilterExpression='attribute_exists(thumbnail_key) AND #status = :status',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':status': 'processed'}
        )
        
        images = response['Items']
        
        # Process images to add thumbnail URLs and format data
        processed_images = []
        thumbnail_bucket = os.environ.get('THUMBNAIL_BUCKET')
        region = os.environ.get('AWS_REGION', 'eu-west-1')
        
        for image in images:
            thumbnail_url = f"https://{thumbnail_bucket}.s3.{region}.amazonaws.com/{image['thumbnail_key']}"
            
            processed_image = {
                'id': image['image_id'],
                'originalKey': image['original_key'],
                'thumbnailKey': image['thumbnail_key'],
                'thumbnailUrl': thumbnail_url,
                'originalName': image.get('original_name', image['original_key']),
                'uploadTime': image['upload_time'],
                'processedTime': image.get('processed_time'),
                'size': image.get('original_size', 0),
                'originalWidth': image.get('original_width'),
                'originalHeight': image.get('original_height'),
                'thumbnailWidth': image.get('thumbnail_width'),
                'thumbnailHeight': image.get('thumbnail_height'),
                'contentType': image.get('content_type', 'image/jpeg')
            }
            
            processed_images.append(processed_image)
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'images': processed_images,
                'count': len(processed_images),
                'user_id': user_id
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error fetching images for user {user_id}: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({
                'error': 'Failed to fetch images',
                'message': str(e)
            })
        }