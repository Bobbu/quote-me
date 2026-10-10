#!/usr/bin/env python3

import requests
import json
import subprocess
import sys
import time

# Configuration
BASE_URL = "https://dcc.anystupididea.com"
STACK_NAME = "quote-me-api"


def get_stack_output(key):
    """Read a CloudFormation output so the test survives a scorched-earth redeploy"""
    return subprocess.run(
        ['aws', 'cloudformation', 'describe-stacks', '--stack-name', STACK_NAME,
         '--query', f"Stacks[0].Outputs[?OutputKey=='{key}'].OutputValue", '--output', 'text'],
        capture_output=True, text=True, check=True
    ).stdout.strip()


USER_POOL_ID = get_stack_output('UserPoolId')
CLIENT_ID = get_stack_output('UserPoolClientId')
ADMIN_GROUP = "Admins"

# Generate unique test user credentials
import time
TEST_USERNAME = f"test-tag-cleanup-{int(time.time())}@dcc-test.com"
TEST_PASSWORD = "TempTestPass123!"

def create_test_user():
    """Create temporary admin user for testing"""
    print(f"👤 Creating temporary admin user: {TEST_USERNAME}")
    
    try:
        # Create user
        cmd1 = [
            'aws', 'cognito-idp', 'admin-create-user',
            '--user-pool-id', USER_POOL_ID,
            '--username', TEST_USERNAME,
            '--user-attributes', f'Name=email,Value={TEST_USERNAME}',
            '--temporary-password', TEST_PASSWORD,
            '--message-action', 'SUPPRESS'
        ]
        
        result1 = subprocess.run(cmd1, capture_output=True, text=True)
        if result1.returncode != 0:
            print(f"❌ Failed to create test user: {result1.stderr}")
            return False
        
        # Set permanent password
        cmd2 = [
            'aws', 'cognito-idp', 'admin-set-user-password',
            '--user-pool-id', USER_POOL_ID,
            '--username', TEST_USERNAME,
            '--password', TEST_PASSWORD,
            '--permanent'
        ]
        
        result2 = subprocess.run(cmd2, capture_output=True, text=True)
        if result2.returncode != 0:
            print(f"❌ Failed to set permanent password: {result2.stderr}")
            return False
        
        # Add to admin group
        cmd3 = [
            'aws', 'cognito-idp', 'admin-add-user-to-group',
            '--user-pool-id', USER_POOL_ID,
            '--username', TEST_USERNAME,
            '--group-name', ADMIN_GROUP
        ]
        
        result3 = subprocess.run(cmd3, capture_output=True, text=True)
        if result3.returncode != 0:
            print(f"❌ Failed to add user to admin group: {result3.stderr}")
            return False
        
        print("✅ Temporary admin user created successfully")
        return True
        
    except Exception as e:
        print(f"❌ Error creating test user: {e}")
        return False

def cleanup_test_user():
    """Cleanup temporary admin user"""
    print(f"🧹 Cleaning up temporary admin user: {TEST_USERNAME}")
    
    try:
        cmd = [
            'aws', 'cognito-idp', 'admin-delete-user',
            '--user-pool-id', USER_POOL_ID,
            '--username', TEST_USERNAME
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print("✅ Temporary user deleted successfully")
        else:
            print(f"⚠️  Note: Manual cleanup may be needed for user: {TEST_USERNAME}")
    except Exception as e:
        print(f"⚠️  Error during cleanup: {e}")

def get_admin_token():
    """Get admin authentication token"""
    try:
        cmd = [
            'aws', 'cognito-idp', 'initiate-auth',
            '--client-id', CLIENT_ID,
            '--auth-flow', 'USER_PASSWORD_AUTH',
            '--auth-parameters', f'USERNAME={TEST_USERNAME},PASSWORD={TEST_PASSWORD}'
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            response = json.loads(result.stdout)
            return response['AuthenticationResult']['IdToken']
        else:
            print(f"❌ Failed to authenticate: {result.stderr}")
            return None
            
    except Exception as e:
        print(f"❌ Error getting token: {e}")
        return None

def test_get_tags(token):
    """Test getting current tags"""
    print("📋 Getting current tags...")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    response = requests.get(f"{BASE_URL}/admin/tags", headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        # Map tag name -> number of quotes using it (counted server-side across all quotes)
        tags = {t['name']: t.get('quote_count', 0) for t in data.get('tags', [])}
        print(f"✅ Found {len(tags)} tags")
        return tags
    else:
        print(f"❌ Failed to get tags: {response.status_code} - {response.text}")
        return None

def test_cleanup_unused_tags(token):
    """Test cleaning up unused tags"""
    print("🧹 Testing tag cleanup...")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    response = requests.delete(f"{BASE_URL}/admin/tags/unused", headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        message = data.get('message', '')
        removed_tags = data.get('removed_tags', [])
        remaining_tags = data.get('remaining_tags', [])
        count_removed = data.get('count_removed', 0)
        count_remaining = data.get('count_remaining', 0)
        
        print(f"✅ Cleanup result: {message}")
        print(f"   - Removed {count_removed} tags: {removed_tags}")
        print(f"   - Remaining {count_remaining} tags: {remaining_tags}")
        
        return True
    else:
        print(f"❌ Failed to cleanup tags: {response.status_code} - {response.text}")
        return False

def main():
    print("🧪 Testing Tag Cleanup Functionality")
    print("=" * 50)
    
    # Setup: Create temporary admin user
    if not create_test_user():
        print("❌ Failed to create temporary test user")
        sys.exit(1)
    
    try:
        # Wait for user creation to propagate
        print("⏳ Waiting for user creation to propagate...")
        time.sleep(3)
        
        # Get admin token
        token = get_admin_token()
        if not token:
            print("❌ Cannot proceed without admin token")
            sys.exit(1)
        
        print("✅ Successfully authenticated as admin")
        print()
        
        # Step 1: Get current tags with usage counts
        current_tags = test_get_tags(token)
        if current_tags is None:
            sys.exit(1)
        used_tags = {name for name, count in current_tags.items() if count > 0}
        unused_tags = set(current_tags) - used_tags
        print()
        
        # Step 2: Show which tags should be cleaned up
        if unused_tags:
            print(f"🗑️  Unused tags that will be cleaned up: {sorted(unused_tags)}")
        else:
            print("✨ No unused tags found - all tags are being used!")
        print()
        
        # Step 3: Run cleanup
        if not test_cleanup_unused_tags(token):
            sys.exit(1)
        print()
        
        # Step 4: Verify no tag in use was removed and every unused tag is gone
        print("🔍 Verifying final state...")
        final_tags = test_get_tags(token)
        if final_tags is None:
            sys.exit(1)
        lost = used_tags - set(final_tags)
        lingering = unused_tags & set(final_tags)
        if lost:
            print(f"❌ Cleanup removed tags that are still in use: {sorted(lost)}")
            sys.exit(1)
        if lingering:
            print(f"❌ Unused tags were not removed: {sorted(lingering)}")
            sys.exit(1)
        print(f"✅ All {len(used_tags)} tags in use were kept; {len(unused_tags)} unused removed")
        print()
        print("🎉 Tag cleanup test completed!")
        
    finally:
        # Cleanup: Delete temporary user
        cleanup_test_user()

if __name__ == "__main__":
    main()