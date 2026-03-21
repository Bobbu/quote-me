"""
User Analytics Report Handler

Generates comprehensive weekly reports on:
- User metrics (total, new, active, subscribers)
- Quote metrics (total, added, removed)
- Tag metrics (total, added, removed)

Sends email reports to admin users and stores snapshots for historical comparison.
"""

import json
import os
import boto3
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Dict, List, Any
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
cognito = boto3.client('cognito-idp')
ses = boto3.client('ses')

# Environment variables
USER_POOL_ID = os.environ['USER_POOL_ID']
QUOTES_TABLE_NAME = os.environ['QUOTES_TABLE_NAME']
TAGS_TABLE_NAME = os.environ['TAGS_TABLE_NAME']
SUBSCRIPTIONS_TABLE_NAME = os.environ['SUBSCRIPTIONS_TABLE_NAME']
REPORTS_TABLE_NAME = os.environ.get('REPORTS_TABLE_NAME', 'quote-me-analytics-reports')
FROM_EMAIL = os.environ.get('FROM_EMAIL', 'noreply@anystupididea.com')
ADMIN_GROUP_NAME = os.environ.get('ADMIN_GROUP_NAME', 'Admins')


class DecimalEncoder(json.JSONEncoder):
    """Helper class to convert Decimal to int/float for JSON serialization"""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)


def get_user_metrics() -> Dict[str, Any]:
    """Get comprehensive user metrics from Cognito"""
    logger.info("Fetching user metrics from Cognito...")

    metrics = {
        'total_users': 0,
        'confirmed_users': 0,
        'unconfirmed_users': 0,
        'users_by_auth_method': {
            'email': 0,
            'google': 0,
            'apple': 0
        },
        'new_users_this_week': 0
    }

    # Calculate week boundary
    one_week_ago = datetime.now() - timedelta(days=7)

    try:
        # Paginate through all users
        paginator = cognito.get_paginator('list_users')
        page_iterator = paginator.paginate(UserPoolId=USER_POOL_ID)

        for page in page_iterator:
            for user in page['Users']:
                metrics['total_users'] += 1

                # Check user status
                if user['UserStatus'] == 'CONFIRMED':
                    metrics['confirmed_users'] += 1
                else:
                    metrics['unconfirmed_users'] += 1

                # Check creation date for new users
                if user['UserCreateDate'].replace(tzinfo=None) > one_week_ago:
                    metrics['new_users_this_week'] += 1

                # Determine auth method
                identities = next((attr['Value'] for attr in user.get('Attributes', [])
                                 if attr['Name'] == 'identities'), None)
                if identities:
                    try:
                        identity_data = json.loads(identities)
                        if isinstance(identity_data, list) and len(identity_data) > 0:
                            provider = identity_data[0].get('providerName', '').lower()
                            if 'google' in provider:
                                metrics['users_by_auth_method']['google'] += 1
                            elif 'apple' in provider or 'signinwithapple' in provider:
                                metrics['users_by_auth_method']['apple'] += 1
                            else:
                                metrics['users_by_auth_method']['email'] += 1
                        else:
                            metrics['users_by_auth_method']['email'] += 1
                    except:
                        metrics['users_by_auth_method']['email'] += 1
                else:
                    metrics['users_by_auth_method']['email'] += 1

        logger.info(f"User metrics: {metrics}")
        return metrics

    except Exception as e:
        logger.error(f"Error fetching user metrics: {str(e)}")
        raise


def get_subscription_metrics() -> Dict[str, Any]:
    """Get Daily Nuggets subscription metrics"""
    logger.info("Fetching subscription metrics...")

    try:
        subscriptions_table = dynamodb.Table(SUBSCRIPTIONS_TABLE_NAME)
        response = subscriptions_table.scan()

        metrics = {
            'total_subscribers': 0,
            'active_subscribers': 0
        }

        for item in response.get('Items', []):
            if item.get('is_subscribed', False):
                metrics['active_subscribers'] += 1
            metrics['total_subscribers'] += 1

        logger.info(f"Subscription metrics: {metrics}")
        return metrics

    except Exception as e:
        logger.error(f"Error fetching subscription metrics: {str(e)}")
        return {'total_subscribers': 0, 'active_subscribers': 0}


def get_quote_metrics() -> Dict[str, Any]:
    """Get quote statistics from DynamoDB"""
    logger.info("Fetching quote metrics...")

    try:
        quotes_table = dynamodb.Table(QUOTES_TABLE_NAME)
        response = quotes_table.scan(Select='COUNT')

        metrics = {
            'total_quotes': response.get('Count', 0)
        }

        logger.info(f"Quote metrics: {metrics}")
        return metrics

    except Exception as e:
        logger.error(f"Error fetching quote metrics: {str(e)}")
        return {'total_quotes': 0}


def get_tag_metrics() -> Dict[str, Any]:
    """Get tag statistics from DynamoDB"""
    logger.info("Fetching tag metrics...")

    try:
        tags_table = dynamodb.Table(TAGS_TABLE_NAME)
        response = tags_table.scan()

        # Tags table has metadata item with all tags
        metadata_item = next((item for item in response.get('Items', [])
                            if item.get('tag') == '__metadata__'), None)

        if metadata_item and 'all_tags' in metadata_item:
            total_tags = len(metadata_item['all_tags'])
        else:
            # Fallback: count items (excluding metadata)
            total_tags = response.get('Count', 0) - 1

        metrics = {
            'total_tags': total_tags
        }

        logger.info(f"Tag metrics: {metrics}")
        return metrics

    except Exception as e:
        logger.error(f"Error fetching tag metrics: {str(e)}")
        return {'total_tags': 0}


def get_previous_snapshot() -> Dict[str, Any]:
    """Get the previous week's snapshot for comparison"""
    logger.info("Fetching previous snapshot...")

    try:
        reports_table = dynamodb.Table(REPORTS_TABLE_NAME)
        response = reports_table.scan(
            Limit=1,
            ScanIndexForward=False
        )

        items = response.get('Items', [])
        if items:
            # Sort by timestamp to get most recent
            items.sort(key=lambda x: x.get('timestamp', ''), reverse=True)
            logger.info(f"Found previous snapshot from {items[0].get('timestamp')}")
            return items[0]
        else:
            logger.info("No previous snapshot found")
            return None

    except Exception as e:
        logger.error(f"Error fetching previous snapshot: {str(e)}")
        return None


def save_snapshot(data: Dict[str, Any]) -> None:
    """Save current metrics snapshot for future comparisons"""
    logger.info("Saving snapshot...")

    try:
        reports_table = dynamodb.Table(REPORTS_TABLE_NAME)

        snapshot = {
            'report_id': f"report-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
            'timestamp': datetime.now().isoformat(),
            'data': data
        }

        reports_table.put_item(Item=snapshot)
        logger.info(f"Snapshot saved: {snapshot['report_id']}")

    except Exception as e:
        logger.error(f"Error saving snapshot: {str(e)}")


def calculate_changes(current: Dict[str, Any], previous: Dict[str, Any]) -> Dict[str, Any]:
    """Calculate week-over-week changes"""
    if not previous or 'data' not in previous:
        return {}

    prev_data = previous['data']
    changes = {}

    # User changes
    if 'users' in current and 'users' in prev_data:
        changes['users_added'] = current['users']['total_users'] - prev_data['users']['total_users']
        changes['users_growth_pct'] = (
            (changes['users_added'] / prev_data['users']['total_users'] * 100)
            if prev_data['users']['total_users'] > 0 else 0
        )

    # Quote changes
    if 'quotes' in current and 'quotes' in prev_data:
        changes['quotes_added'] = current['quotes']['total_quotes'] - prev_data['quotes']['total_quotes']

    # Tag changes
    if 'tags' in current and 'tags' in prev_data:
        changes['tags_added'] = current['tags']['total_tags'] - prev_data['tags']['total_tags']

    # Subscription changes
    if 'subscriptions' in current and 'subscriptions' in prev_data:
        changes['subscribers_added'] = (
            current['subscriptions']['active_subscribers'] -
            prev_data['subscriptions']['active_subscribers']
        )

    return changes


def generate_html_report(data: Dict[str, Any], changes: Dict[str, Any]) -> str:
    """Generate HTML email report"""

    # Helper for change indicators
    def change_indicator(value):
        if value > 0:
            return f'<span style="color: #22c55e;">▲ +{value}</span>'
        elif value < 0:
            return f'<span style="color: #ef4444;">▼ {value}</span>'
        else:
            return f'<span style="color: #6b7280;">— {value}</span>'

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #1f2937; }}
            .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
            .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 8px 8px 0 0; }}
            .header h1 {{ margin: 0; font-size: 28px; }}
            .header p {{ margin: 10px 0 0 0; opacity: 0.9; }}
            .section {{ background: white; padding: 25px; border: 1px solid #e5e7eb; }}
            .section:last-child {{ border-radius: 0 0 8px 8px; }}
            .section h2 {{ color: #667eea; margin-top: 0; font-size: 20px; border-bottom: 2px solid #667eea; padding-bottom: 10px; }}
            .metric-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin: 15px 0; }}
            .metric {{ background: #f9fafb; padding: 15px; border-radius: 6px; border-left: 3px solid #667eea; }}
            .metric-label {{ font-size: 13px; color: #6b7280; text-transform: uppercase; letter-spacing: 0.5px; }}
            .metric-value {{ font-size: 28px; font-weight: bold; color: #1f2937; margin: 5px 0; }}
            .metric-change {{ font-size: 14px; margin-top: 5px; }}
            .footer {{ text-align: center; margin-top: 20px; padding: 20px; color: #6b7280; font-size: 13px; }}
            .breakdown {{ background: #f3f4f6; padding: 10px 15px; border-radius: 4px; margin: 10px 0; }}
            .breakdown-item {{ display: flex; justify-content: space-between; padding: 5px 0; }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>📊 Quote Me Weekly Report</h1>
                <p>Week ending {datetime.now().strftime('%B %d, %Y')}</p>
            </div>

            <div class="section">
                <h2>👥 User Metrics</h2>
                <div class="metric-grid">
                    <div class="metric">
                        <div class="metric-label">Total Users</div>
                        <div class="metric-value">{data['users']['total_users']:,}</div>
                        {f'<div class="metric-change">{change_indicator(changes.get("users_added", 0))} this week</div>' if changes else ''}
                    </div>
                    <div class="metric">
                        <div class="metric-label">New This Week</div>
                        <div class="metric-value">{data['users']['new_users_this_week']}</div>
                    </div>
                </div>

                <div class="breakdown">
                    <div class="breakdown-item">
                        <span>✅ Confirmed</span>
                        <strong>{data['users']['confirmed_users']:,}</strong>
                    </div>
                    <div class="breakdown-item">
                        <span>⏳ Unconfirmed</span>
                        <strong>{data['users']['unconfirmed_users']:,}</strong>
                    </div>
                </div>

                <div class="breakdown">
                    <strong style="display: block; margin-bottom: 8px;">Auth Methods:</strong>
                    <div class="breakdown-item">
                        <span>📧 Email</span>
                        <strong>{data['users']['users_by_auth_method']['email']:,}</strong>
                    </div>
                    <div class="breakdown-item">
                        <span>🔵 Google</span>
                        <strong>{data['users']['users_by_auth_method']['google']:,}</strong>
                    </div>
                    <div class="breakdown-item">
                        <span>🍎 Apple</span>
                        <strong>{data['users']['users_by_auth_method']['apple']:,}</strong>
                    </div>
                </div>
            </div>

            <div class="section">
                <h2>📬 Daily Nuggets Subscriptions</h2>
                <div class="metric-grid">
                    <div class="metric">
                        <div class="metric-label">Active Subscribers</div>
                        <div class="metric-value">{data['subscriptions']['active_subscribers']:,}</div>
                        {f'<div class="metric-change">{change_indicator(changes.get("subscribers_added", 0))} this week</div>' if changes else ''}
                    </div>
                </div>
            </div>

            <div class="section">
                <h2>💬 Quote Metrics</h2>
                <div class="metric-grid">
                    <div class="metric">
                        <div class="metric-label">Total Quotes</div>
                        <div class="metric-value">{data['quotes']['total_quotes']:,}</div>
                        {f'<div class="metric-change">{change_indicator(changes.get("quotes_added", 0))} this week</div>' if changes else ''}
                    </div>
                </div>
            </div>

            <div class="section">
                <h2>🏷️ Tag Metrics</h2>
                <div class="metric-grid">
                    <div class="metric">
                        <div class="metric-label">Total Tags</div>
                        <div class="metric-value">{data['tags']['total_tags']:,}</div>
                        {f'<div class="metric-change">{change_indicator(changes.get("tags_added", 0))} this week</div>' if changes else ''}
                    </div>
                </div>
            </div>

            <div class="footer">
                <p>🤖 Generated automatically by Quote Me Analytics</p>
                <p>Report generated at {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}</p>
                <p style="font-size: 12px; margin-top: 15px; color: #9ca3af;">
                    <a href="https://anystupididea.com" style="color: #9ca3af; text-decoration: none;">Any Stupid Idea</a> &middot;
                    <a href="https://anystupididea.com/privacy.html" style="color: #9ca3af; text-decoration: none;">Privacy</a> &middot;
                    <a href="https://anystupididea.com/terms.html" style="color: #9ca3af; text-decoration: none;">Terms</a>
                </p>
            </div>
        </div>
    </body>
    </html>
    """

    return html


def get_admin_emails() -> List[str]:
    """Get email addresses of all admin users"""
    logger.info("Fetching admin emails...")

    try:
        response = cognito.list_users_in_group(
            UserPoolId=USER_POOL_ID,
            GroupName=ADMIN_GROUP_NAME
        )

        emails = []
        for user in response.get('Users', []):
            email = next((attr['Value'] for attr in user.get('Attributes', [])
                         if attr['Name'] == 'email'), None)
            if email:
                emails.append(email)

        logger.info(f"Found {len(emails)} admin emails")
        return emails

    except Exception as e:
        logger.error(f"Error fetching admin emails: {str(e)}")
        return []


def send_email_report(html_content: str, recipient_emails: List[str]) -> None:
    """Send email report via SES"""
    if not recipient_emails:
        logger.warning("No recipient emails provided, skipping email send")
        return

    logger.info(f"Sending email report to {len(recipient_emails)} recipients...")

    try:
        for email in recipient_emails:
            ses.send_email(
                Source=FROM_EMAIL,
                Destination={'ToAddresses': [email]},
                Message={
                    'Subject': {
                        'Data': f"📊 Quote Me Weekly Report - {datetime.now().strftime('%B %d, %Y')}",
                        'Charset': 'UTF-8'
                    },
                    'Body': {
                        'Html': {
                            'Data': html_content,
                            'Charset': 'UTF-8'
                        }
                    }
                }
            )
            logger.info(f"Email sent to {email}")

    except Exception as e:
        logger.error(f"Error sending email: {str(e)}")
        raise


def lambda_handler(event, context):
    """Main Lambda handler for user analytics report"""
    logger.info("Starting user analytics report generation...")
    logger.info(f"Event: {json.dumps(event)}")

    try:
        # Collect all metrics
        user_metrics = get_user_metrics()
        subscription_metrics = get_subscription_metrics()
        quote_metrics = get_quote_metrics()
        tag_metrics = get_tag_metrics()

        # Compile current data
        current_data = {
            'users': user_metrics,
            'subscriptions': subscription_metrics,
            'quotes': quote_metrics,
            'tags': tag_metrics
        }

        # Get previous snapshot for comparison
        previous_snapshot = get_previous_snapshot()

        # Calculate changes
        changes = calculate_changes(current_data, previous_snapshot)

        # Generate HTML report
        html_report = generate_html_report(current_data, changes)

        # Get admin emails
        admin_emails = get_admin_emails()

        # Send email report
        if admin_emails:
            send_email_report(html_report, admin_emails)
        else:
            logger.warning("No admin emails found, report not sent")

        # Save current snapshot for next week's comparison
        save_snapshot(current_data)

        logger.info("Report generation completed successfully")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Report generated successfully',
                'recipients': len(admin_emails),
                'data': current_data,
                'changes': changes
            }, cls=DecimalEncoder)
        }

    except Exception as e:
        logger.error(f"Error generating report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
