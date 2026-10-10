#!/usr/bin/env python3

"""
Test script to verify Daily Nuggets subscription data synchronization
"""

import boto3
import json
from decimal import Decimal

# DynamoDB client
dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
subscriptions_table = dynamodb.Table('quote-me-subscriptions')

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def check_subscription(email):
    """Check subscription status in DynamoDB"""
    print(f"🔍 Checking subscription for: {email}")
    print("=" * 50)
    
    try:
        response = subscriptions_table.get_item(
            Key={'email': email}
        )
        
        if 'Item' in response:
            item = response['Item']
            print("✅ Subscription found in database:")
            print(f"  Email: {item.get('email')}")
            print(f"  Subscribed: {item.get('is_subscribed')}")
            print(f"  Delivery Method: {item.get('delivery_method')}")
            print(f"  Timezone: {item.get('timezone')}")
            print(f"  Tag filter: {item.get('tags') or 'All'}")
            print(f"  Created: {item.get('created_at')}")
            print(f"  Updated: {item.get('updated_at')}")
            print("\nRaw data:")
            print(json.dumps(item, indent=2, default=decimal_default))
            return item
        else:
            print("❌ No subscription found in database")
            return None
            
    except Exception as e:
        print(f"❌ Error checking subscription: {e}")
        return None

def list_all_subscriptions():
    """List all subscriptions in the database"""
    print("\n📋 All subscriptions in database:")
    print("=" * 50)
    
    try:
        response = subscriptions_table.scan()
        items = response.get('Items', [])
        while 'LastEvaluatedKey' in response:
            response = subscriptions_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            items.extend(response.get('Items', []))
        
        if not items:
            print("No subscriptions found")
            return
        
        active_count = 0
        for item in items:
            email = item.get('email', 'unknown')
            is_subscribed = item.get('is_subscribed', False)
            if is_subscribed:
                active_count += 1
            status = "✅ ACTIVE" if is_subscribed else "⭕ INACTIVE"
            print(f"  {status} {email} — tags: {item.get('tags') or 'All'}")
        
        print(f"\nTotal: {len(items)} users, {active_count} active subscriptions")
        
    except Exception as e:
        print(f"❌ Error listing subscriptions: {e}")

if __name__ == "__main__":
    print("🧪 Daily Nuggets Subscription Sync Test")
    print("=" * 50)
    
    # Test with admin user
    admin_email = "admin@dcc.com"
    check_subscription(admin_email)
    
    # List all subscriptions
    list_all_subscriptions()
    
    print("\n📌 What to check:")
    print("1. Is the subscription showing as 'is_subscribed': True in DB?")
    print("2. Does the timestamp show a recent update?")
    print("3. Are there multiple entries for the same user?")
    print("\nIf subscription is True in DB but shows as Off in web app,")
    print("there may be a JWT token or authorization issue.")