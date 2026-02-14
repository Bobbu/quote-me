import json
import boto3
import os
from html import escape

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('QUOTES_TABLE_NAME', 'quote-me-quotes'))

def get_quote_by_id(quote_id):
    """Get a specific quote by its ID."""
    try:
        if quote_id == 'TAGS_METADATA':
            return None
            
        response = table.get_item(Key={'id': quote_id})
        item = response.get('Item')
        
        if item and item.get('id') != 'TAGS_METADATA':
            return item
        return None
        
    except Exception as e:
        print(f"Error fetching quote by ID {quote_id}: {e}")
        return None

def generate_tag_meta_tags(tags):
    """Generate meta tags for article tags."""
    if not tags:
        return ""
    
    meta_tags = []
    for tag in tags:
        escaped_tag = escape(tag)
        meta_tags.append(f'<meta property="article:tag" content="{escaped_tag}">')
    
    return '\n    '.join(meta_tags)

def generate_html_page(quote_data):
    """Generate HTML page with Open Graph/Twitter Card meta tags for a quote."""
    
    if not quote_data:
        # Return a fallback page for non-existent quotes
        return generate_fallback_page()
    
    # Escape HTML characters to prevent XSS
    quote_text = escape(quote_data.get('quote', ''))
    author = escape(quote_data.get('author', 'Unknown'))
    quote_id = escape(quote_data.get('id', ''))
    tags = quote_data.get('tags', [])
    tags_str = escape(', '.join(tags)) if tags else ''
    
    # Create a shortened version for social media descriptions (max 160 chars)
    description = f'"{quote_text[:100]}..." - {author}'
    if len(quote_text) <= 100:
        description = f'"{quote_text}" - {author}'
    
    # Generate the HTML with meta tags
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    
    <!-- Primary Meta Tags -->
    <title>{author} - Quote Me</title>
    <meta name="title" content="{author} - Quote Me">
    <meta name="description" content="{description}">
    
    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="article">
    <meta property="og:url" content="https://quote-me.anystupididea.com/quote/{quote_id}">
    <meta property="og:title" content="Quote by {author}">
    <meta property="og:description" content="{description}">
    <meta property="og:image" content="https://quote-me.anystupididea.com/images/preview.png">
    <meta property="og:image:width" content="1200">
    <meta property="og:image:height" content="630">
    <meta property="og:image:type" content="image/png">
    <meta property="og:site_name" content="Quote Me">
    <meta property="og:locale" content="en_US">
    
    <!-- Twitter -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:site" content="@quoteme">
    <meta name="twitter:creator" content="@quoteme">
    <meta name="twitter:url" content="https://quote-me.anystupididea.com/quote/{quote_id}">
    <meta name="twitter:title" content="Quote by {author}">
    <meta name="twitter:description" content="{description}">
    <meta name="twitter:image" content="https://quote-me.anystupididea.com/images/preview.png">
    <meta name="twitter:image:alt" content="Quote Me - Share inspiring quotes">
    
    <!-- Additional meta tags -->
    <meta property="article:author" content="{author}">
    {generate_tag_meta_tags(tags)}
    
    <!-- Redirect to app after a delay -->
    <meta http-equiv="refresh" content="5;url=https://quote-me.anystupididea.com">
    
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            padding: 20px;
        }}
        .container {{
            max-width: 800px;
            text-align: center;
            background: rgba(255, 255, 255, 0.1);
            padding: 40px;
            border-radius: 20px;
            backdrop-filter: blur(10px);
        }}
        .quote {{
            font-size: 1.5em;
            font-style: italic;
            margin-bottom: 20px;
            line-height: 1.6;
        }}
        .author {{
            font-size: 1.2em;
            font-weight: bold;
            margin-bottom: 30px;
        }}
        .tags {{
            font-size: 0.9em;
            opacity: 0.9;
            margin-bottom: 30px;
        }}
        .redirect {{
            font-size: 0.9em;
            opacity: 0.8;
        }}
        a {{
            color: white;
            text-decoration: underline;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="quote">"{quote_text}"</div>
        <div class="author">— {author}</div>
        {f'<div class="tags">Tags: {tags_str}</div>' if tags else ''}
        <div class="redirect">
            Redirecting to Quote Me app... 
            <a href="https://quote-me.anystupididea.com">Click here if not redirected</a>
        </div>
    </div>
</body>
</html>"""
    
    return html

def generate_fallback_page():
    """Generate a fallback HTML page for non-existent quotes."""
    
    html = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    
    <!-- Primary Meta Tags -->
    <title>Quote Me - Share Inspiring Quotes</title>
    <meta name="title" content="Quote Me - Share Inspiring Quotes">
    <meta name="description" content="Discover and share inspiring, witty, and wise quotes with Quote Me.">
    
    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="website">
    <meta property="og:url" content="https://quote-me.anystupididea.com">
    <meta property="og:title" content="Quote Me - Share Inspiring Quotes">
    <meta property="og:description" content="Discover and share inspiring, witty, and wise quotes with Quote Me.">
    <meta property="og:image" content="https://quote-me.anystupididea.com/images/preview.png">
    
    <!-- Twitter -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:url" content="https://quote-me.anystupididea.com">
    <meta name="twitter:title" content="Quote Me - Share Inspiring Quotes">
    <meta name="twitter:description" content="Discover and share inspiring, witty, and wise quotes with Quote Me.">
    <meta name="twitter:image" content="https://quote-me.anystupididea.com/images/preview.png">
    
    <!-- Redirect to main app -->
    <meta http-equiv="refresh" content="5;url=https://quote-me.anystupididea.com">
    
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            padding: 20px;
        }
        .container {
            max-width: 600px;
            text-align: center;
            background: rgba(255, 255, 255, 0.1);
            padding: 40px;
            border-radius: 20px;
            backdrop-filter: blur(10px);
        }
        h1 {
            margin-bottom: 20px;
        }
        a {
            color: white;
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Quote Not Found</h1>
        <p>The quote you're looking for doesn't exist or has been removed.</p>
        <p>Redirecting to Quote Me... <a href="https://quote-me.anystupididea.com">Click here if not redirected</a></p>
    </div>
</body>
</html>"""
    
    return html

def lambda_handler(event, context):
    """
    AWS Lambda handler for serving HTML pages with meta tags for social sharing.
    This is meant to handle requests from social media crawlers.
    """
    try:
        # Extract quote ID from path
        path_parameters = event.get('pathParameters') or {}
        quote_id = path_parameters.get('id')
        
        print(f"Quote ID requested: {quote_id}")
        
        # Check User-Agent to detect social media crawlers
        headers = event.get('headers') or {}
        user_agent = headers.get('User-Agent', '').lower()
        
        print(f"User-Agent: {user_agent}")
        
        # List of known social media bot user agents
        social_bots = [
            'facebookexternalhit',
            'facebookcatalog',
            'twitterbot',
            'linkedinbot',
            'whatsapp',
            'slackbot',
            'discordbot',
            'telegrambot',
            'pinterest',
            'skypeuripreview',
            'outbrain',
            'vkshare',
            'w3c_validator',
            'imessage',
            'messages',
            'com.apple.mobilesms',
            'applebot'
        ]
        
        # Check if this is a social media crawler or if 'html' is in query params
        query_params = event.get('queryStringParameters') or {}
        force_html = query_params.get('format') == 'html'
        is_social_bot = any(bot in user_agent for bot in social_bots)
        
        if is_social_bot or force_html:
            # Serve HTML page with meta tags
            quote_data = None
            if quote_id:
                quote_data = get_quote_by_id(quote_id)
                if not quote_data:
                    print(f"Quote not found for ID: {quote_id}")
            
            html_content = generate_html_page(quote_data)
            
            return {
                "statusCode": 200 if quote_data else 404,
                "headers": {
                    "Content-Type": "text/html; charset=utf-8",
                    "Cache-Control": "public, max-age=3600",  # Cache for 1 hour
                    "Access-Control-Allow-Origin": "*"
                },
                "body": html_content
            }
        else:
            # For regular browsers/apps, serve the HTML page (same as social bots)
            # This allows anyone to view the quote in a nice format
            print(f"Regular browser detected, serving HTML page")
            quote_data = None
            if quote_id:
                quote_data = get_quote_by_id(quote_id)
                if not quote_data:
                    print(f"Quote not found for ID: {quote_id}")
            
            html_content = generate_html_page(quote_data)
            
            return {
                "statusCode": 200 if quote_data else 404,
                "headers": {
                    "Content-Type": "text/html; charset=utf-8",
                    "Cache-Control": "public, max-age=3600",  # Cache for 1 hour
                    "Access-Control-Allow-Origin": "*"
                },
                "body": html_content
            }
        
    except Exception as e:
        print(f"Lambda error: {e}")
        
        # Return a basic error page
        error_html = """<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Error - Quote Me</title>
</head>
<body>
    <h1>Error</h1>
    <p>An error occurred while loading this quote.</p>
    <p><a href="https://quote-me.anystupididea.com">Go to Quote Me</a></p>
</body>
</html>"""
        
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "text/html; charset=utf-8",
                "Access-Control-Allow-Origin": "*"
            },
            "body": error_html
        }