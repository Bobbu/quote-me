import json
import boto3
import os
import uuid
from datetime import datetime
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
ses_client = boto3.client('ses', region_name='us-east-1')
table_name = os.environ.get('TABLE_NAME', 'quote-me-proposed-quotes')
table = dynamodb.Table(table_name)
# Main quotes table for approved quotes
quotes_table_name = os.environ.get('QUOTES_TABLE_NAME', 'quote-me-quotes')
quotes_table = dynamodb.Table(quotes_table_name)
# Sender email for notifications
sender_email = os.environ.get('SENDER_EMAIL', 'noreply@anystupididea.com')

def decimal_default(obj):
    """Helper to convert Decimal to float for JSON serialization"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def send_decision_email(proposer_email, proposer_name, quote_text, author, action, feedback=None):
    """Send email notification about quote decision"""
    try:
        if action == 'approve':
            subject = "🎉 Great News! Your Quote Has Been Approved!"
            html_body = f"""
            <html>
            <head>
                <style>
                    body {{ font-family: 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; }}
                    .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                    .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px 10px 0 0; text-align: center; }}
                    .content {{ background: #f8f9fa; padding: 30px; border-radius: 0 0 10px 10px; }}
                    .quote-box {{ background: white; padding: 20px; border-left: 4px solid #667eea; margin: 20px 0; border-radius: 5px; }}
                    .celebration {{ text-align: center; font-size: 48px; margin: 20px 0; }}
                    .footer {{ text-align: center; margin-top: 30px; color: #666; font-size: 14px; }}
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="header">
                        <h1>🎉 Congratulations, {proposer_name or 'Quote Contributor'}!</h1>
                    </div>
                    <div class="content">
                        <div class="celebration">🌟✨🎊</div>
                        <p><strong>Fantastic news!</strong> Your proposed quote has been approved and is now part of our curated collection!</p>
                        
                        <div class="quote-box">
                            <p style="font-style: italic; font-size: 18px; margin: 0;">"{quote_text}"</p>
                            <p style="text-align: right; margin: 10px 0 0 0; color: #666;">— {author}</p>
                        </div>
                        
                        <p>Your contribution will inspire and enlighten countless readers. Thank you for sharing this wonderful piece of wisdom with our community!</p>
                        
                        {f'<p><strong>Admin note:</strong> {feedback}</p>' if feedback else ''}
                        
                        <p>Keep those amazing quotes coming! We love hearing from passionate contributors like you.</p>
                        
                        <div class="footer">
                            <p>With gratitude,<br>The Quote Me Team</p>
                            <p style="font-size: 12px; margin-top: 15px; color: #999;">
                                <a href="https://anystupididea.com" style="color: #999; text-decoration: none;">Any Stupid Idea</a> &middot;
                                <a href="https://anystupididea.com/privacy.html" style="color: #999; text-decoration: none;">Privacy</a> &middot;
                                <a href="https://anystupididea.com/terms.html" style="color: #999; text-decoration: none;">Terms</a>
                            </p>
                        </div>
                    </div>
                </div>
            </body>
            </html>
            """
        else:  # reject
            subject = "Thank You for Your Quote Submission"
            html_body = f"""
            <html>
            <head>
                <style>
                    body {{ font-family: 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; }}
                    .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                    .header {{ background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 30px; border-radius: 10px 10px 0 0; text-align: center; }}
                    .content {{ background: #f8f9fa; padding: 30px; border-radius: 0 0 10px 10px; }}
                    .quote-box {{ background: white; padding: 20px; border-left: 4px solid #f093fb; margin: 20px 0; border-radius: 5px; }}
                    .encouragement {{ background: #e8f4fd; padding: 20px; border-radius: 10px; margin: 20px 0; }}
                    .footer {{ text-align: center; margin-top: 30px; color: #666; font-size: 14px; }}
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="header">
                        <h1>Thank You, {proposer_name or 'Valued Contributor'}!</h1>
                    </div>
                    <div class="content">
                        <p>We truly appreciate you taking the time to submit a quote to our collection. Your engagement with our community means the world to us!</p>
                        
                        <div class="quote-box">
                            <p style="font-style: italic; font-size: 18px; margin: 0;">"{quote_text}"</p>
                            <p style="text-align: right; margin: 10px 0 0 0; color: #666;">— {author}</p>
                        </div>
                        
                        <p>After careful review, we've decided not to add this particular quote to our collection at this time. This doesn't diminish the value of your contribution or your eye for meaningful quotes!</p>
                        
                        {f'<div class="encouragement"><p><strong>Reviewer feedback:</strong> {feedback}</p></div>' if feedback else ''}
                        
                        <div class="encouragement">
                            <p><strong>💡 Keep exploring and sharing!</strong></p>
                            <p>We encourage you to continue submitting quotes that inspire you. Every submission helps us understand what resonates with our community, and we'd love to see more of your discoveries!</p>
                        </div>
                        
                        <p>Remember, curation is subjective, and what might not fit today could be perfect tomorrow. Please don't let this discourage you from sharing more wonderful quotes with us!</p>
                        
                        <div class="footer">
                            <p>With appreciation,<br>The Quote Me Team</p>
                            <p style="font-size: 12px; margin-top: 15px; color: #999;">
                                <a href="https://anystupididea.com" style="color: #999; text-decoration: none;">Any Stupid Idea</a> &middot;
                                <a href="https://anystupididea.com/privacy.html" style="color: #999; text-decoration: none;">Privacy</a> &middot;
                                <a href="https://anystupididea.com/terms.html" style="color: #999; text-decoration: none;">Terms</a>
                            </p>
                        </div>
                    </div>
                </div>
            </body>
            </html>
            """
        
        # Send the email
        response = ses_client.send_email(
            Source=sender_email,
            Destination={'ToAddresses': [proposer_email]},
            Message={
                'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                'Body': {'Html': {'Data': html_body, 'Charset': 'UTF-8'}}
            }
        )
        print(f"Email sent successfully to {proposer_email}: {response['MessageId']}")
        return True
        
    except Exception as e:
        print(f"Failed to send email to {proposer_email}: {str(e)}")
        return False

def lambda_handler(event, context):
    """
    Handle proposed quote operations:
    - POST: Create a new proposed quote
    - GET: Retrieve proposed quotes (admin only)
    """
    
    # Extract HTTP method and path
    http_method = event.get('httpMethod', '')
    path = event.get('path', '')
    
    # Parse the JWT claims from the authorizer
    claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
    user_email = claims.get('email', 'unknown')
    user_name = claims.get('name', user_email)
    cognito_groups = claims.get('cognito:groups', '')
    is_admin = 'Admins' in cognito_groups if cognito_groups else False
    
    # Handle CORS preflight
    if http_method == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
                'Access-Control-Allow-Credentials': 'true'
            },
            'body': ''
        }
    
    try:
        if http_method == 'POST' and path == '/propose-quote':
            # Create a new proposed quote
            body = json.loads(event.get('body', '{}'))
            
            # Validate required fields
            quote_text = body.get('quote', '').strip()
            author = body.get('author', '').strip()
            
            if not quote_text:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Quote text is required'})
                }
            
            if not author:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Author is required'})
                }
            
            # Create the proposed quote item
            quote_id = str(uuid.uuid4())
            timestamp = datetime.utcnow().isoformat() + 'Z'
            
            item = {
                'id': quote_id,
                'quote': quote_text,
                'author': author,
                'proposer_email': user_email,
                'proposer_name': user_name,
                'status': 'pending',  # pending, approved, rejected
                'created_date': timestamp,
                'updated_date': timestamp
            }
            
            # Optional fields
            if 'tags' in body and body['tags']:
                item['tags'] = body['tags']
            
            if 'notes' in body and body['notes']:
                item['notes'] = body['notes'].strip()
            
            # Save to DynamoDB
            table.put_item(Item=item)
            
            return {
                'statusCode': 201,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'message': 'Quote proposed successfully',
                    'id': quote_id,
                    'status': 'pending'
                })
            }
        
        elif http_method == 'PUT' and path.startswith('/proposed-quotes/'):
            # Admin approve/reject proposed quote
            if not is_admin:
                return {
                    'statusCode': 403,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Admin access required'})
                }
            
            # Extract quote ID from path
            quote_id = path.split('/')[-1]
            body = json.loads(event.get('body', '{}'))
            action = body.get('action')  # 'approve' or 'reject'
            feedback = body.get('feedback', '')
            
            if action not in ['approve', 'reject']:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Action must be approve or reject'})
                }
            
            try:
                # Get the proposed quote
                response = table.get_item(Key={'id': quote_id})
                if 'Item' not in response:
                    return {
                        'statusCode': 404,
                        'headers': {
                            'Access-Control-Allow-Origin': '*',
                            'Content-Type': 'application/json'
                        },
                        'body': json.dumps({'error': 'Proposed quote not found'})
                    }
                
                proposed_quote = response['Item']
                timestamp = datetime.utcnow().isoformat() + 'Z'
                
                # Update proposed quote status
                update_expression = 'SET #status = :status, updated_date = :updated_date, reviewed_by = :reviewed_by'
                expression_values = {
                    ':status': action + 'd',  # 'approved' or 'rejected'
                    ':updated_date': timestamp,
                    ':reviewed_by': user_email
                }
                expression_names = {'#status': 'status'}
                
                if feedback:
                    update_expression += ', admin_feedback = :feedback'
                    expression_values[':feedback'] = feedback
                
                # Update the proposed quote
                table.update_item(
                    Key={'id': quote_id},
                    UpdateExpression=update_expression,
                    ExpressionAttributeValues=expression_values,
                    ExpressionAttributeNames=expression_names
                )
                
                # Send email notification to proposer
                proposer_email = proposed_quote.get('proposer_email')
                proposer_name = proposed_quote.get('proposer_name')
                quote_text = proposed_quote.get('quote')
                quote_author = proposed_quote.get('author')
                
                if proposer_email:
                    send_decision_email(
                        proposer_email=proposer_email,
                        proposer_name=proposer_name,
                        quote_text=quote_text,
                        author=quote_author,
                        action=action,
                        feedback=feedback
                    )
                
                # If approved, add to main quotes table
                if action == 'approve':
                    # Create new quote in main table
                    new_quote_id = str(uuid.uuid4())
                    
                    quote_item = {
                        'PK': f'QUOTE#{new_quote_id}',
                        'SK': f'QUOTE#{new_quote_id}',
                        'id': new_quote_id,
                        'type': 'quote',
                        'quote': proposed_quote['quote'],
                        'author': proposed_quote['author'],
                        'quote_normalized': proposed_quote['quote'].lower(),
                        'author_normalized': proposed_quote['author'].lower(),
                        'created_at': timestamp,
                        'updated_at': timestamp,
                        'created_by': user_email,  # Admin who approved it
                        'proposed_by': proposed_quote['proposer_email'],
                        'approved_by': user_email,
                        'original_proposal_id': quote_id
                    }
                    
                    # Add tags if they exist
                    if 'tags' in proposed_quote and proposed_quote['tags']:
                        quote_item['tags'] = proposed_quote['tags']
                        
                        # Also create tag entries for each tag (following existing pattern)
                        for tag in proposed_quote['tags']:
                            quotes_table.put_item(Item={
                                'PK': f'TAG#{tag}',
                                'SK': f'QUOTE#{new_quote_id}',
                                'id': f'tag#{tag}#{new_quote_id}',
                                'type': 'tag_mapping',
                                'tag': tag,
                                'quote_id': new_quote_id,
                                'created_at': timestamp
                            })
                    
                    # Save to main quotes table
                    quotes_table.put_item(Item=quote_item)
                
                return {
                    'statusCode': 200,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({
                        'message': f'Quote {action}d successfully',
                        'status': action + 'd',
                        'new_quote_id': new_quote_id if action == 'approve' else None
                    })
                }
                
            except Exception as e:
                print(f"Error updating proposed quote: {str(e)}")
                return {
                    'statusCode': 500,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': f'Failed to {action} quote: {str(e)}'})
                }
        
        elif http_method == 'DELETE' and path.startswith('/proposed-quotes/'):
            # Admin delete proposed quote
            if not is_admin:
                return {
                    'statusCode': 403,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Admin access required'})
                }
            
            # Extract quote ID from path
            quote_id = path.split('/')[-1]
            
            try:
                # Delete the proposed quote
                response = table.delete_item(
                    Key={'id': quote_id},
                    ReturnValues='ALL_OLD'
                )
                
                if 'Attributes' not in response:
                    return {
                        'statusCode': 404,
                        'headers': {
                            'Access-Control-Allow-Origin': '*',
                            'Content-Type': 'application/json'
                        },
                        'body': json.dumps({'error': 'Proposed quote not found'})
                    }
                
                return {
                    'statusCode': 200,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({
                        'message': 'Quote deleted successfully',
                        'deleted_id': quote_id
                    })
                }
                
            except Exception as e:
                print(f"Error deleting proposed quote: {str(e)}")
                return {
                    'statusCode': 500,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': f'Failed to delete quote: {str(e)}'})
                }
        
        elif http_method == 'GET' and path == '/proposed-quotes':
            # Get proposed quotes
            # Regular users see only their own quotes
            # Admins see all quotes
            
            if is_admin:
                # Admin: get all proposed quotes (pending, approved, rejected)
                quotes = []
                
                # Get pending quotes first
                response = table.query(
                    IndexName='StatusIndex',
                    KeyConditionExpression='#status = :status',
                    ExpressionAttributeNames={
                        '#status': 'status'
                    },
                    ExpressionAttributeValues={
                        ':status': 'pending'
                    },
                    ScanIndexForward=False  # Most recent first
                )
                quotes.extend(response['Items'])
                
                # Get approved quotes
                response = table.query(
                    IndexName='StatusIndex',
                    KeyConditionExpression='#status = :status',
                    ExpressionAttributeNames={
                        '#status': 'status'
                    },
                    ExpressionAttributeValues={
                        ':status': 'approved'
                    },
                    ScanIndexForward=False,  # Most recent first
                    Limit=50  # Limit recent approved quotes
                )
                quotes.extend(response['Items'])
                
                # Get rejected quotes
                response = table.query(
                    IndexName='StatusIndex',
                    KeyConditionExpression='#status = :status',
                    ExpressionAttributeNames={
                        '#status': 'status'
                    },
                    ExpressionAttributeValues={
                        ':status': 'rejected'
                    },
                    ScanIndexForward=False,  # Most recent first
                    Limit=50  # Limit recent rejected quotes
                )
                quotes.extend(response['Items'])
                
                # Sort all quotes by updated_date descending
                quotes.sort(key=lambda x: x.get('updated_date', x.get('created_date', '')), reverse=True)
                
            else:
                # Regular user: get only their quotes
                response = table.query(
                    IndexName='ProposerEmailIndex',
                    KeyConditionExpression='proposer_email = :email',
                    ExpressionAttributeValues={
                        ':email': user_email
                    },
                    ScanIndexForward=False  # Most recent first
                )
                quotes = response['Items']
            
            return {
                'statusCode': 200,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'quotes': quotes,
                    'count': len(quotes),
                    'is_admin': is_admin
                }, default=decimal_default)
            }
        
        else:
            return {
                'statusCode': 404,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({'error': 'Not found'})
            }
    
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }