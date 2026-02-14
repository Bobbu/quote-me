import json
import logging
import os
import boto3
import urllib.parse
import requests
import time
import base64
import traceback
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# DynamoDB for success flag storage
dynamodb = boto3.resource('dynamodb')

# Cognito configuration
COGNITO_DOMAIN = "dcc-demo-sam-app-auth.auth.us-east-1.amazoncognito.com"
CLIENT_ID = "2idvhvlhgbheglr0hptel5j55"
REDIRECT_URI = "https://dcc.anystupididea.com/auth/callback"
WEB_APP_URL = "https://quote-me.anystupididea.com"

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Handle OAuth callback from Cognito with simplified approach"""
    try:
        logger.info(f"📥 OAuth callback received: {json.dumps(event, default=str)}")
        
        # Extract query parameters
        query_params = event.get('queryStringParameters', {}) or {}
        code = query_params.get('code')
        state = query_params.get('state', '')
        error = query_params.get('error')
        
        # Handle errors from Cognito
        if error:
            error_description = query_params.get('error_description', 'Authentication failed')
            logger.error(f"❌ OAuth error: {error} - {error_description}")
            return generate_response(400, error_html(error_description))
        
        # Validate authorization code
        if not code:
            logger.error("❌ No authorization code received")
            return generate_response(400, error_html("No authorization code received"))
        
        logger.info(f"🔑 Processing OAuth code: {code[:10]}...")
        
        # Exchange authorization code for tokens
        token_response = exchange_code_for_tokens(code)
        
        if 'error' in token_response:
            logger.error(f"❌ Token exchange failed: {token_response['error']}")
            return generate_response(400, error_html(f"Token exchange failed: {token_response.get('error_description', 'Unknown error')}"))
        
        # Extract tokens
        access_token = token_response.get('access_token')
        id_token = token_response.get('id_token')
        refresh_token = token_response.get('refresh_token')
        
        if not all([access_token, id_token]):
            logger.error("❌ Missing required tokens in response")
            return generate_response(400, error_html("Invalid token response"))
        
        logger.info("✅ Successfully exchanged code for tokens")
        
        # Extract user info from ID token and store simple success flag
        success_key = ""
        try:
            payload = id_token.split('.')[1]
            payload += '=' * (4 - len(payload) % 4)
            decoded = base64.urlsafe_b64decode(payload)
            user_info = json.loads(decoded)
            user_email = user_info.get('email', '')
            user_sub = user_info.get('sub', '')
            
            logger.info(f"🎯 OAuth completed for user: {user_email}")
            
            # Store simple success flag
            success_key = store_oauth_success_flag(user_email, user_sub)
            logger.info(f"✅ Stored OAuth success flag with key: {success_key}")
            
        except Exception as e:
            logger.error(f"⚠️ Failed to extract user info: {e}")
        
        # Determine if mobile based on user agent
        user_agent = event.get('headers', {}).get('User-Agent', '').lower()
        is_mobile = any(device in user_agent for device in ['iphone', 'ipad', 'android', 'mobile'])
        
        # Generate simplified success HTML
        html = create_success_page(is_mobile, success_key)
        
        return generate_response(200, html)
        
    except Exception as e:
        logger.error(f"❌ Unexpected error: {str(e)}")
        logger.error(traceback.format_exc())
        return generate_response(500, error_html(f"Internal server error: {str(e)}"))

def store_oauth_success_flag(user_email: str, user_sub: str) -> str:
    """Store a simple OAuth success flag in DynamoDB"""
    try:
        timestamp = int(time.time())
        success_key = f"oauth_success_{timestamp}_{user_sub[-8:]}"
        
        # Store simple success flag with 5-minute TTL
        table = dynamodb.Table(os.environ.get('QUOTES_TABLE_NAME', 'quote-me-quotes'))
        table.put_item(
            Item={
                'id': success_key,
                'token_type': 'oauth_success',
                'user_email': user_email,
                'user_sub': user_sub,
                'created_at': timestamp,
                'ttl': timestamp + 300  # 5 minutes
            }
        )
        
        logger.info(f"✅ Stored OAuth success flag: {success_key} for {user_email}")
        return success_key
        
    except Exception as e:
        logger.error(f"❌ Failed to store success flag: {e}")
        return ""

def check_oauth_success(success_key: str) -> Dict[str, Any]:
    """Check if OAuth was successful for a given key"""
    try:
        if not success_key:
            return {'success': False, 'error': 'Missing success key'}
        
        table = dynamodb.Table(os.environ.get('QUOTES_TABLE_NAME', 'quote-me-quotes'))
        response = table.get_item(Key={'id': success_key})
        
        if 'Item' not in response:
            return {'success': False, 'error': 'Success flag not found or expired'}
        
        item = response['Item']
        
        if item.get('token_type') != 'oauth_success':
            return {'success': False, 'error': 'Invalid flag type'}
        
        # Delete the flag after check (one-time use)
        table.delete_item(Key={'id': success_key})
        
        return {
            'success': True,
            'user_email': item.get('user_email'),
            'user_sub': item.get('user_sub')
        }
        
    except Exception as e:
        logger.error(f"❌ OAuth success check error: {e}")
        return {'success': False, 'error': 'Internal server error'}

def exchange_code_for_tokens(code: str) -> Dict[str, Any]:
    """Exchange authorization code for tokens via Cognito token endpoint"""
    token_url = f"https://{COGNITO_DOMAIN}/oauth2/token"
    
    # Prepare token request
    token_data = {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': CLIENT_ID,
        'redirect_uri': REDIRECT_URI
    }
    
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded'
    }
    
    logger.info(f"Exchanging code for tokens at {token_url}")
    
    try:
        response = requests.post(
            token_url,
            data=urllib.parse.urlencode(token_data),
            headers=headers,
            timeout=10
        )
        
        response_data = response.json()
        
        if response.status_code != 200:
            logger.error(f"Token exchange failed with status {response.status_code}: {response_data}")
            return response_data
        
        logger.info("Token exchange successful")
        return response_data
        
    except Exception as e:
        logger.error(f"Token exchange request failed: {str(e)}")
        return {'error': 'token_exchange_failed', 'error_description': str(e)}

def create_success_page(is_mobile: bool, success_key: str = "") -> str:
    """Generate simplified success HTML page"""
    # Mobile deep link with success flag
    mobile_deep_link = f"quoteme://auth-success?success_key={success_key}" if success_key else "quoteme://auth-success"
    
    # Web redirect URL
    web_redirect_url = f"{WEB_APP_URL}?auth=success"
    
    mobile_display = "block" if is_mobile else "none"
    web_display = "none" if is_mobile else "block"
    mobile_bool = "true" if is_mobile else "false"
    
    return f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Authentication Successful - Quote Me</title>
        <style>
            body {{
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                display: flex;
                justify-content: center;
                align-items: center;
                min-height: 100vh;
                margin: 0;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            }}
            .container {{
                text-align: center;
                background: white;
                padding: 2.5rem;
                border-radius: 16px;
                box-shadow: 0 20px 40px rgba(0,0,0,0.1);
                max-width: 420px;
                margin: 1rem;
            }}
            .success-icon {{
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                font-size: 3rem;
                width: 80px;
                height: 80px;
                border-radius: 50%;
                display: inline-flex;
                align-items: center;
                justify-content: center;
                margin-bottom: 1.5rem;
            }}
            h1 {{
                color: #333;
                margin-bottom: 1rem;
                font-size: 1.8rem;
            }}
            p {{
                color: #666;
                line-height: 1.6;
                margin-bottom: 1.5rem;
            }}
            .btn {{
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 14px 28px;
                border: none;
                border-radius: 8px;
                cursor: pointer;
                font-size: 16px;
                font-weight: 600;
                text-decoration: none;
                display: inline-block;
                transition: transform 0.2s;
                margin: 0.5rem;
            }}
            .btn:hover {{
                transform: translateY(-2px);
            }}
            .btn-secondary {{
                background: #e0e0e0;
                color: #333;
            }}
            .loading {{
                color: #666;
                margin-top: 1rem;
            }}
            .spinner {{
                display: inline-block;
                width: 20px;
                height: 20px;
                border: 3px solid #f3f3f3;
                border-top: 3px solid #667eea;
                border-radius: 50%;
                animation: spin 1s linear infinite;
                margin-right: 10px;
                vertical-align: middle;
            }}
            @keyframes spin {{
                0% {{ transform: rotate(0deg); }}
                100% {{ transform: rotate(360deg); }}
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="success-icon">✓</div>
            <h1>Welcome to Quote Me!</h1>
            <p>You've successfully signed in with Google.</p>
            
            <div id="mobile-instructions" style="display: {mobile_display};">
                <p><strong>For mobile users:</strong><br>
                Return to the Quote Me app - you should now be signed in!</p>
                <a href="{mobile_deep_link}" class="btn">Open Quote Me App</a>
            </div>
            
            <div id="web-instructions" style="display: {web_display};">
                <p>Redirecting to Quote Me...</p>
                <div class="loading">
                    <span class="spinner"></span>
                    <span>Loading your quotes...</span>
                </div>
            </div>
            
            <br>
            <a href="{web_redirect_url}" class="btn btn-secondary">Continue to Quote Me</a>
        </div>

        <script>
            console.log('🎯 OAuth success page loaded');
            console.log('📱 Is mobile:', {mobile_bool});
            console.log('🔑 Success key:', '{success_key}');
            
            try {{
                // Set simple success flag for web app
                localStorage.setItem('oauth_success', 'true');
                localStorage.setItem('oauth_timestamp', Date.now().toString());
                
                // For web users, redirect after 3 seconds
                if (!{mobile_bool}) {{
                    setTimeout(() => {{
                        console.log('🌐 Redirecting web user...');
                        window.location.href = '{web_redirect_url}';
                    }}, 3000);
                }}
                
                // For mobile users, attempt deep link after 1 second
                if ({mobile_bool}) {{
                    setTimeout(() => {{
                        console.log('📱 Attempting mobile deep link...');
                        window.location.href = '{mobile_deep_link}';
                    }}, 1000);
                }}
                
            }} catch (e) {{
                console.error('❌ Script error:', e);
            }}
        </script>
    </body>
    </html>
    """

def error_html(error_message: str) -> str:
    """Generate error HTML page"""
    return f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Authentication Failed - Quote Me</title>
        <style>
            body {{
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                display: flex;
                justify-content: center;
                align-items: center;
                min-height: 100vh;
                margin: 0;
                background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            }}
            .container {{
                text-align: center;
                background: white;
                padding: 2.5rem;
                border-radius: 16px;
                box-shadow: 0 20px 40px rgba(0,0,0,0.1);
                max-width: 420px;
                margin: 1rem;
            }}
            .error-icon {{
                background: #f5576c;
                color: white;
                font-size: 3rem;
                width: 80px;
                height: 80px;
                border-radius: 50%;
                display: inline-flex;
                align-items: center;
                justify-content: center;
                margin-bottom: 1.5rem;
            }}
            h1 {{
                color: #333;
                margin-bottom: 1rem;
            }}
            p {{
                color: #666;
                line-height: 1.6;
                margin-bottom: 1.5rem;
            }}
            .error-details {{
                background: #ffebee;
                border-left: 4px solid #f5576c;
                padding: 1rem;
                text-align: left;
                margin: 1rem 0;
                border-radius: 4px;
            }}
            .btn {{
                background: #f5576c;
                color: white;
                padding: 14px 28px;
                border: none;
                border-radius: 8px;
                cursor: pointer;
                font-size: 16px;
                font-weight: 600;
                text-decoration: none;
                display: inline-block;
                transition: transform 0.2s;
            }}
            .btn:hover {{
                transform: translateY(-2px);
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="error-icon">✕</div>
            <h1>Authentication Failed</h1>
            <p>We couldn't complete your sign-in.</p>
            <div class="error-details">
                <strong>Error:</strong><br>
                {error_message}
            </div>
            <a href="{WEB_APP_URL}" class="btn">Back to Quote Me</a>
        </div>
    </body>
    </html>
    """

def generate_response(status_code: int, html_body: str) -> Dict[str, Any]:
    """Generate API Gateway response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'text/html',
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,Authorization',
            'Access-Control-Allow-Methods': 'GET,OPTIONS'
        },
        'body': html_body
    }