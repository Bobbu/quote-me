import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal
import gzip
from io import BytesIO

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
cognito = boto3.client('cognito-idp')

# Environment variables
TABLE_NAME = os.environ.get('QUOTES_TABLE_NAME', 'quote-me-quotes')
EXPORT_BUCKET = os.environ.get('EXPORT_BUCKET', 'quote-me-app-db-exports')
USER_POOL_ID = os.environ.get('USER_POOL_ID')

# Helper class to handle Decimal serialization
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return str(obj)
        return super(DecimalEncoder, self).default(obj)

def get_user_email_from_token(event):
    """Extract user email from the JWT token in the request"""
    try:
        # The authorizer adds the claims to the request context
        claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
        return claims.get('email', 'unknown')
    except Exception as e:
        print(f"Error extracting email from token: {e}")
        return 'unknown'

def export_to_s3(data, user_email, export_type='quotes', format='json'):
    """Export data to S3 and return a pre-signed URL"""
    try:
        # Generate timestamp and file path
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        file_extension = 'json.gz' if format == 'json' else 'csv.gz'
        file_key = f"exports/{user_email}/{timestamp}/{export_type}.{file_extension}"
        
        # Prepare data based on format
        if format == 'json':
            content = json.dumps(data, cls=DecimalEncoder, indent=2)
        else:  # CSV format
            # Convert to CSV format
            import csv
            from io import StringIO
            
            csv_buffer = StringIO()
            if export_type == 'quotes' and 'quotes' in data:
                writer = csv.DictWriter(csv_buffer, 
                    fieldnames=['id', 'quote', 'author', 'tags', 'created_date', 'created_by'])
                writer.writeheader()
                for quote in data['quotes']:
                    row = {
                        'id': quote.get('id', ''),
                        'quote': quote.get('quote', ''),
                        'author': quote.get('author', ''),
                        'tags': ', '.join(quote.get('tags', [])),
                        'created_date': quote.get('created_date', ''),
                        'created_by': quote.get('created_by', '')
                    }
                    writer.writerow(row)
            content = csv_buffer.getvalue()
        
        # Compress the content
        compressed_buffer = BytesIO()
        with gzip.GzipFile(fileobj=compressed_buffer, mode='wb') as gz_file:
            gz_file.write(content.encode('utf-8'))
        compressed_content = compressed_buffer.getvalue()
        
        # Upload to S3
        s3.put_object(
            Bucket=EXPORT_BUCKET,
            Key=file_key,
            Body=compressed_content,
            ContentType='application/gzip',
            Metadata={
                'user-email': user_email,
                'export-type': export_type,
                'format': format,
                'timestamp': timestamp,
                'original-size': str(len(content)),
                'compressed-size': str(len(compressed_content))
            }
        )
        
        # Generate pre-signed URL (valid for 48 hours)
        presigned_url = s3.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': EXPORT_BUCKET,
                'Key': file_key,
                'ResponseContentDisposition': f'attachment; filename="{export_type}_{timestamp}.{file_extension}"'
            },
            ExpiresIn=172800  # 48 hours
        )
        
        return {
            'success': True,
            'url': presigned_url,
            'key': file_key,
            'expires_in': '48 hours',
            'size': {
                'original': len(content),
                'compressed': len(compressed_content)
            },
            'format': format
        }
        
    except Exception as e:
        print(f"Error exporting to S3: {e}")
        return {
            'success': False,
            'error': str(e)
        }

def get_all_quotes():
    """Retrieve all quotes from DynamoDB"""
    table = dynamodb.Table(TABLE_NAME)
    quotes = []
    
    try:
        # Use scan with pagination
        last_evaluated_key = None
        while True:
            if last_evaluated_key:
                response = table.scan(
                    FilterExpression='attribute_exists(quote) AND attribute_exists(author)',
                    ExclusiveStartKey=last_evaluated_key
                )
            else:
                response = table.scan(
                    FilterExpression='attribute_exists(quote) AND attribute_exists(author)'
                )
            
            quotes.extend(response.get('Items', []))
            
            last_evaluated_key = response.get('LastEvaluatedKey')
            if not last_evaluated_key:
                break
        
        # Sort by creation date (newest first)
        quotes.sort(key=lambda x: x.get('created_date', ''), reverse=True)
        
        return quotes
        
    except Exception as e:
        print(f"Error retrieving quotes: {e}")
        raise

def get_export_statistics(quotes):
    """Generate statistics about the export"""
    try:
        # Collect unique authors and tags
        authors = set()
        tags = set()
        
        for quote in quotes:
            if 'author' in quote:
                authors.add(quote['author'])
            if 'tags' in quote:
                for tag in quote['tags']:
                    tags.add(tag)
        
        return {
            'total_quotes': len(quotes),
            'unique_authors': len(authors),
            'unique_tags': len(tags),
            'authors': sorted(list(authors)),
            'tags': sorted(list(tags))
        }
    except Exception as e:
        print(f"Error generating statistics: {e}")
        return {}

def get_cors_headers(event):
    """Get appropriate CORS headers based on origin"""
    origin = event.get('headers', {}).get('origin') or event.get('headers', {}).get('Origin')
    
    allowed_origins = [
        'https://quote-me.anystupididea.com',
        'https://dcc.anystupididea.com',
        'http://localhost:3000',
        'http://127.0.0.1:3000'
    ]
    
    if origin in allowed_origins:
        allow_origin = origin
    else:
        allow_origin = '*'
    
    return {
        'Access-Control-Allow-Origin': allow_origin,
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'OPTIONS,POST,GET',
        'Access-Control-Allow-Credentials': 'true'
    }

def lambda_handler(event, context):
    """Handle export requests"""
    
    cors_headers = get_cors_headers(event)
    
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        export_type = body.get('type', 'quotes')  # quotes, tags, or full
        format = body.get('format', 'json')  # json or csv
        destination = body.get('destination', 's3')  # s3, clipboard, or download
        
        # Get user email from token
        user_email = get_user_email_from_token(event)
        
        # For S3 exports, we always export to S3 first
        if destination == 's3':
            # Get all quotes
            quotes = get_all_quotes()
            
            # Generate statistics
            stats = get_export_statistics(quotes)
            
            # Prepare export data
            export_data = {
                'export_metadata': {
                    'timestamp': datetime.utcnow().isoformat() + 'Z',
                    'user': user_email,
                    'format': format,
                    'type': export_type,
                    **stats
                },
                'quotes': quotes
            }
            
            # Export to S3
            result = export_to_s3(export_data, user_email, export_type, format)
            
            if result['success']:
                return {
                    'statusCode': 200,
                    'headers': {
                        'Content-Type': 'application/json',
                        **cors_headers
                    },
                    'body': json.dumps({
                        'success': True,
                        'message': 'Export completed successfully',
                        'download_url': result['url'],
                        's3_key': result['key'],
                        'expires_in': result['expires_in'],
                        'size': result['size'],
                        'statistics': stats
                    })
                }
            else:
                return {
                    'statusCode': 500,
                    'headers': {
                        'Content-Type': 'application/json',
                        **cors_headers
                    },
                    'body': json.dumps({
                        'success': False,
                        'message': 'Export failed',
                        'error': result.get('error', 'Unknown error')
                    })
                }
        
        # For clipboard or download destinations, return the data directly
        elif destination in ['clipboard', 'download']:
            # Get all quotes
            quotes = get_all_quotes()
            
            # Generate statistics
            stats = get_export_statistics(quotes)
            
            # Prepare export data
            export_data = {
                'export_metadata': {
                    'timestamp': datetime.utcnow().isoformat() + 'Z',
                    'user': user_email,
                    'format': format,
                    'type': export_type,
                    **stats
                },
                'quotes': quotes
            }
            
            # Return data for client-side handling
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    **cors_headers
                },
                'body': json.dumps({
                    'success': True,
                    'destination': destination,
                    'data': export_data,
                    'statistics': stats
                }, cls=DecimalEncoder)
            }
        
        else:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    **cors_headers
                },
                'body': json.dumps({
                    'success': False,
                    'message': f'Invalid destination: {destination}'
                })
            }
            
    except Exception as e:
        print(f"Error in lambda_handler: {e}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                **cors_headers
            },
            'body': json.dumps({
                'success': False,
                'message': 'Internal server error',
                'error': str(e)
            })
        }