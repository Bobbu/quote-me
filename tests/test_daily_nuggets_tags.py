#!/usr/bin/env python3
"""
Live test: Daily Nuggets subscription tag filter (PUT /subscriptions/tags).

Uses a temporary Cognito user. The subscription is created with
is_subscribed=False so no scheduled email is ever sent to the fake address.
"""

import json
import subprocess
import sys
import time

import requests

BASE_URL = "https://dcc.anystupididea.com"
STACK_NAME = "quote-me-api"
TEST_EMAIL = f"test-nugget-tags-{int(time.time())}@dcc-test.com"
TEST_PASSWORD = "TempTestPass123!"


def aws(*args):
    return subprocess.run(['aws', *args], capture_output=True, text=True, check=True).stdout


def get_stack_output(key):
    """Read a CloudFormation output so the test survives a scorched-earth redeploy"""
    return aws('cloudformation', 'describe-stacks', '--stack-name', STACK_NAME,
               '--query', f"Stacks[0].Outputs[?OutputKey=='{key}'].OutputValue",
               '--output', 'text').strip()


USER_POOL_ID = get_stack_output('UserPoolId')
CLIENT_ID = get_stack_output('UserPoolClientId')


def create_user():
    aws('cognito-idp', 'admin-create-user', '--user-pool-id', USER_POOL_ID,
        '--username', TEST_EMAIL,
        '--user-attributes', f'Name=email,Value={TEST_EMAIL}', 'Name=email_verified,Value=true',
        '--temporary-password', TEST_PASSWORD, '--message-action', 'SUPPRESS')
    aws('cognito-idp', 'admin-set-user-password', '--user-pool-id', USER_POOL_ID,
        '--username', TEST_EMAIL, '--password', TEST_PASSWORD, '--permanent')


def delete_user():
    try:
        aws('cognito-idp', 'admin-delete-user', '--user-pool-id', USER_POOL_ID, '--username', TEST_EMAIL)
        print("🧹 Temporary user deleted")
    except subprocess.CalledProcessError as e:
        print(f"⚠️  Failed to delete temporary user: {e.stderr}")


def get_token():
    result = json.loads(aws('cognito-idp', 'initiate-auth', '--client-id', CLIENT_ID,
                            '--auth-flow', 'USER_PASSWORD_AUTH',
                            '--auth-parameters', f'USERNAME={TEST_EMAIL},PASSWORD={TEST_PASSWORD}'))
    return result['AuthenticationResult']['IdToken']


failures = []


def check(name, condition, detail=''):
    print(f"{'✅' if condition else '❌'} {name}{'' if condition else f' — {detail}'}")
    if not condition:
        failures.append(name)


def main():
    print("🧪 Testing Daily Nuggets tag filter")
    print("=" * 50)
    create_user()
    try:
        time.sleep(3)
        headers = {'Authorization': f'Bearer {get_token()}', 'Content-Type': 'application/json'}

        def put_tags(tags):
            return requests.put(f"{BASE_URL}/subscriptions/tags", headers=headers, json={'tags': tags})

        def put_subscription(**extra):
            body = {'is_subscribed': False, 'delivery_method': 'email',
                    'timezone': 'America/New_York', 'notification_preferences': {'deliveryHour': 8}, **extra}
            return requests.put(f"{BASE_URL}/subscriptions", headers=headers, json=body)

        def stored_tags():
            return requests.get(f"{BASE_URL}/subscriptions", headers=headers).json().get('tags')

        r = put_tags(['Humor'])
        check("Tag sync without a subscription is a no-op", r.status_code == 200 and 'No subscription' in r.json().get('message', ''), r.text)
        r = requests.get(f"{BASE_URL}/subscriptions", headers=headers)
        check("No subscription record was created", r.status_code == 404, r.text)

        r = put_subscription(tags=['Humor', 'Comedy', 'Comedian'])
        check("Subscribe with tags", r.status_code == 200, r.text)
        check("Tags stored on subscription", stored_tags() == ['Comedian', 'Comedy', 'Humor'], stored_tags())

        r = put_tags(['Humor'])
        check("Tag sync updates subscription", r.status_code == 200 and stored_tags() == ['Humor'], r.text)

        put_subscription()
        check("Profile save without tags preserves them", stored_tags() == ['Humor'], stored_tags())

        put_tags(['All'])
        check("'All' stored as empty filter", stored_tags() == [], stored_tags())

        r = put_tags('Humor')
        check("Non-array tags rejected", r.status_code == 400, r.text)

        r = requests.options(f"{BASE_URL}/subscriptions/tags")
        check("CORS preflight on /subscriptions/tags", r.status_code == 200, r.status_code)

        requests.delete(f"{BASE_URL}/subscriptions", headers=headers)
    finally:
        delete_user()

    print()
    if failures:
        print(f"❌ {len(failures)} check(s) failed: {failures}")
        sys.exit(1)
    print("🎉 All Daily Nuggets tag filter checks passed!")


if __name__ == "__main__":
    main()
