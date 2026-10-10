#!/bin/bash

# Quote Me Admin API Regression Tests
# Tests all admin endpoints with authentication

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
# Read Cognito IDs from the stack so the tests survive a scorched-earth redeploy
STACK_NAME="quote-me-api"
get_stack_output() {
    aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
USER_POOL_ID=$(get_stack_output UserPoolId)
CLIENT_ID=$(get_stack_output UserPoolClientId)
BASE_URL="https://dcc.anystupididea.com"
ADMIN_GROUP="Admins"

# Test user credentials (temporary)
TEST_USERNAME="test-admin-$(date +%s)@dcc-test.com"
TEST_PASSWORD="TempTestPass123!"

echo -e "${BLUE}🧪 DCC Admin API Regression Tests${NC}"
echo "=================================="

# Function to create temporary admin user
create_test_user() {
    echo -e "${YELLOW}👤 Creating temporary admin user: $TEST_USERNAME${NC}"
    
    # Create user
    aws cognito-idp admin-create-user \
        --user-pool-id $USER_POOL_ID \
        --username $TEST_USERNAME \
        --user-attributes Name=email,Value=$TEST_USERNAME \
        --temporary-password $TEST_PASSWORD \
        --message-action SUPPRESS >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to create test user${NC}"
        return 1
    fi
    
    # Set permanent password
    aws cognito-idp admin-set-user-password \
        --user-pool-id $USER_POOL_ID \
        --username $TEST_USERNAME \
        --password $TEST_PASSWORD \
        --permanent >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to set permanent password${NC}"
        return 1
    fi
    
    # Add to admin group
    aws cognito-idp admin-add-user-to-group \
        --user-pool-id $USER_POOL_ID \
        --username $TEST_USERNAME \
        --group-name $ADMIN_GROUP >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to add user to admin group${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Temporary admin user created successfully${NC}"
    return 0
}

# Function to cleanup temporary user
cleanup_test_user() {
    echo -e "${YELLOW}🧹 Cleaning up temporary admin user: $TEST_USERNAME${NC}"
    
    aws cognito-idp admin-delete-user \
        --user-pool-id $USER_POOL_ID \
        --username $TEST_USERNAME >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Temporary user deleted successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Note: Manual cleanup may be needed for user: $TEST_USERNAME${NC}"
    fi
}

# Function to get admin token
get_admin_token() {
    local username=$1
    local password=$2
    
    echo -e "${YELLOW}🔐 Getting authentication token for $username...${NC}"
    
    TOKEN=$(aws cognito-idp initiate-auth \
        --client-id $CLIENT_ID \
        --auth-flow USER_PASSWORD_AUTH \
        --auth-parameters USERNAME=$username,PASSWORD=$password \
        --query 'AuthenticationResult.IdToken' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$TOKEN" ] && [ "$TOKEN" != "None" ]; then
        echo -e "${GREEN}✅ Authentication successful${NC}"
        return 0
    else
        echo -e "${RED}❌ Authentication failed${NC}"
        return 1
    fi
}

# Function to test API endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local expected_status=$3
    local description=$4
    local data=$5
    
    echo -e "${YELLOW}📡 Testing $method $endpoint - $description${NC}"
    
    if [ -z "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X $method \
            "$BASE_URL$endpoint" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json")
    else
        response=$(curl -s -w "\n%{http_code}" -X $method \
            "$BASE_URL$endpoint" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data")
    fi
    
    # Split response and status code (macOS compatible)
    body=$(echo "$response" | sed '$d')
    status_code=$(echo "$response" | tail -n 1)
    
    if [ "$status_code" -eq "$expected_status" ]; then
        echo -e "${GREEN}✅ Status: $status_code (Expected: $expected_status)${NC}"
        echo -e "${GREEN}✅ Response: $body${NC}"
        echo
        return 0
    else
        echo -e "${RED}❌ Status: $status_code (Expected: $expected_status)${NC}"
        echo -e "${RED}❌ Response: $body${NC}"
        echo
        return 1
    fi
}

# Trap to ensure cleanup happens even if script fails
trap cleanup_test_user EXIT

# Main test execution
main() {
    echo -e "${BLUE}Step 1: Test Setup${NC}"
    echo "=================="
    
    # Create temporary admin user
    if ! create_test_user; then
        echo -e "${RED}❌ Failed to create temporary test user${NC}"
        exit 1
    fi
    
    # Wait a moment for user creation to propagate
    echo -e "${YELLOW}⏳ Waiting for user creation to propagate...${NC}"
    sleep 3
    
    echo -e "${BLUE}Step 2: Authentication${NC}"
    echo "======================"
    
    # Authenticate with temporary user
    if ! get_admin_token "$TEST_USERNAME" "$TEST_PASSWORD"; then
        echo -e "${RED}❌ Could not authenticate with temporary admin user${NC}"
        exit 1
    fi
    
    echo
    echo -e "${BLUE}Step 3: Admin API Tests${NC}"
    echo "======================="
    
    # Test 1: List all quotes
    test_endpoint "GET" "/admin/quotes" 200 "List all quotes"
    
    # Test 2: Get all available tags
    test_endpoint "GET" "/admin/tags" 200 "Get all available tags"
    
    # Test 3: Create new quote
    # Unique tag names so cleanup never touches real tags
    TEST_TAG_PREFIX="zz-test-$(date +%s)"
    TEST_TAGS=("$TEST_TAG_PREFIX-a" "$TEST_TAG_PREFIX-b" "$TEST_TAG_PREFIX-updated")
    NEW_QUOTE_DATA="{
        \"quote\": \"Test quote for regression testing\",
        \"author\": \"Test Author\",
        \"tags\": [\"${TEST_TAGS[0]}\", \"${TEST_TAGS[1]}\"]
    }"
    test_endpoint "POST" "/admin/quotes" 201 "Create new quote" "$NEW_QUOTE_DATA"
    
    # Extract quote ID from the create response for update/delete tests
    CREATED_QUOTE_ID=$(echo "$body" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['quote']['id'])
except:
    print('ERROR')
" 2>/dev/null)
    
    if [ "$CREATED_QUOTE_ID" != "ERROR" ] && [ ! -z "$CREATED_QUOTE_ID" ]; then
        echo -e "${GREEN}✅ Created quote ID: $CREATED_QUOTE_ID${NC}"
        
        # Test 4: Try to create the same quote again (should fail with 409)
        echo -e "${BLUE}Test 4: Duplicate detection${NC}"
        echo -e "${YELLOW}Testing duplicate prevention by trying to create same quote again...${NC}"
        test_endpoint "POST" "/admin/quotes" 409 "Duplicate detection (should block)" "$NEW_QUOTE_DATA"
        
        # Test 6: Update the quote
        UPDATE_QUOTE_DATA="{
            \"quote\": \"Updated test quote for regression testing\",
            \"author\": \"Updated Test Author\",
            \"tags\": [\"${TEST_TAGS[0]}\", \"${TEST_TAGS[1]}\", \"${TEST_TAGS[2]}\"]
        }"
        test_endpoint "PUT" "/admin/quotes/$CREATED_QUOTE_ID" 200 "Update quote" "$UPDATE_QUOTE_DATA"
        
        # Test 7: Verify tags from created/updated quotes were registered in the TagsTable
        test_endpoint "GET" "/admin/tags" 200 "Verify tags list includes new quote tags"
        missing_tags=$(echo "$body" | python3 -c "
import sys, json
names = {t['name'] for t in json.load(sys.stdin)['tags']}
print(' '.join(t for t in sys.argv[1:] if t not in names))
" "${TEST_TAGS[@]}")
        if [ -z "$missing_tags" ]; then
            echo -e "${GREEN}✅ All new quote tags registered${NC}"
        else
            echo -e "${RED}❌ Tags missing from tags list: $missing_tags${NC}"
            exit 1
        fi
        
        # Test 8: Delete the quote and its test tags (cleanup)
        test_endpoint "DELETE" "/admin/quotes/$CREATED_QUOTE_ID" 200 "Delete quote"
        for tag in "${TEST_TAGS[@]}"; do
            test_endpoint "DELETE" "/admin/tags/$tag" 200 "Delete test tag $tag"
        done
    else
        echo -e "${RED}❌ Could not extract quote ID, skipping update/delete tests${NC}"
    fi
    
    # Test 9: List all users (new users endpoint)
    test_endpoint "GET" "/admin/users" 200 "List all users with attributes"
    
    echo
    echo -e "${BLUE}Step 4: Security Tests${NC}"
    echo "====================="
    
    # Test unauthorized access (without token)
    echo -e "${YELLOW}🔒 Testing unauthorized access to quotes endpoint...${NC}"
    unauth_response=$(curl -s -w "\n%{http_code}" -X GET \
        "$BASE_URL/admin/quotes" \
        -H "Content-Type: application/json")
    
    unauth_status=$(echo "$unauth_response" | tail -n 1)
    if [ "$unauth_status" -eq 401 ]; then
        echo -e "${GREEN}✅ Unauthorized access properly blocked (401)${NC}"
    else
        echo -e "${RED}❌ Security issue: Unauthorized access returned $unauth_status${NC}"
    fi
    
    # Test unauthorized access to users endpoint
    echo -e "${YELLOW}🔒 Testing unauthorized access to users endpoint...${NC}"
    unauth_users_response=$(curl -s -w "\n%{http_code}" -X GET \
        "$BASE_URL/admin/users" \
        -H "Content-Type: application/json")
    
    unauth_users_status=$(echo "$unauth_users_response" | tail -n 1)
    if [ "$unauth_users_status" -eq 401 ]; then
        echo -e "${GREEN}✅ Unauthorized access to users properly blocked (401)${NC}"
    else
        echo -e "${RED}❌ Security issue: Unauthorized users access returned $unauth_users_status${NC}"
    fi
    
    echo
    echo -e "${GREEN}🎉 Admin API Regression Tests Complete!${NC}"
    echo "======================================"
}

# Handle script arguments
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "DCC Admin API Regression Tests"
    echo "Usage: $0 [--help]"
    echo
    echo "This script tests all admin API endpoints:"
    echo "  - Authentication with Cognito"
    echo "  - CRUD operations on quotes"
    echo "  - Tags metadata management"
    echo "  - Security (unauthorized access)"
    echo
    echo "Prerequisites:"
    echo "  - AWS CLI configured"
    echo "  - Admin user exists in Cognito User Pool"
    echo "  - API deployed and accessible"
    exit 0
fi

# Run main tests
main