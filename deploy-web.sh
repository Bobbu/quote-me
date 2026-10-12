#!/bin/bash

# Flutter Web App AWS Deployment Script
# Automatically deploys a Flutter web app to S3 + CloudFront + Route53 with SSL

set -e

# Configuration (can be overridden via environment variables or arguments)
DOMAIN_NAME="${1:-${DOMAIN_NAME:-quote-me.anystupididea.com}}"
STACK_NAME="${2:-${STACK_NAME:-quote-me-web-app}}"
REGION="${3:-${REGION:-us-east-1}}"
FLUTTER_APP_DIR="${4:-${FLUTTER_APP_DIR:-dcc_mobile}}"

# Extract root domain from full domain
ROOT_DOMAIN=$(echo $DOMAIN_NAME | sed 's/^[^.]*\.//')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Flutter Web App AWS Deployment${NC}"
echo "================================================"
echo "Domain: $DOMAIN_NAME"
echo "Root Domain: $ROOT_DOMAIN"
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo "Flutter App Directory: $FLUTTER_APP_DIR"
echo "================================================"
echo ""

# Function to print step headers
print_step() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "----------------------------------------"
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to check if AWS CLI is configured
check_aws_cli() {
    print_step "Checking AWS CLI Configuration"
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI first."
        echo "Visit: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS CLI configured (Account: $AWS_ACCOUNT_ID)"
}

# Function to check if Flutter is installed
check_flutter() {
    print_step "Checking Flutter Installation"
    
    if ! command -v flutter &> /dev/null; then
        print_error "Flutter not found. Please install Flutter first."
        echo "Visit: https://flutter.dev/docs/get-started/install"
        exit 1
    fi
    
    FLUTTER_VERSION=$(flutter --version | head -1)
    print_success "Flutter installed: $FLUTTER_VERSION"
}

# Function to get or validate hosted zone
get_hosted_zone_id() {
    print_step "Finding Route53 Hosted Zone"
    
    # Try to find the hosted zone for the root domain
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
        --query "HostedZones[?Name=='${ROOT_DOMAIN}.'].Id" \
        --output text | sed 's|/hostedzone/||')
    
    if [ -z "$HOSTED_ZONE_ID" ]; then
        print_error "No hosted zone found for $ROOT_DOMAIN"
        echo ""
        echo "To fix this, you need to:"
        echo "1. Go to AWS Console -> Route53"
        echo "2. Create a hosted zone for $ROOT_DOMAIN"
        echo "3. Update your domain registrar's nameservers to point to Route53"
        echo ""
        echo "Or, if you have a different hosted zone, you can specify it:"
        read -p "Enter the Hosted Zone ID (or press Enter to exit): " MANUAL_ZONE_ID
        
        if [ -z "$MANUAL_ZONE_ID" ]; then
            exit 1
        fi
        HOSTED_ZONE_ID=$MANUAL_ZONE_ID
    fi
    
    print_success "Found hosted zone: $HOSTED_ZONE_ID"
}

# Function to build Flutter web app
build_flutter_app() {
    print_step "Building Flutter Web App"
    
    if [ ! -d "$FLUTTER_APP_DIR" ]; then
        print_error "Flutter app directory not found: $FLUTTER_APP_DIR"
        exit 1
    fi
    
    cd $FLUTTER_APP_DIR
    
    echo "Cleaning previous build..."
    flutter clean
    
    echo "Getting dependencies..."
    flutter pub get
    
    echo "Building for web (release mode)..."
    flutter build web --release
    
    if [ ! -d "build/web" ]; then
        print_error "Flutter web build failed - build/web directory not found"
        exit 1
    fi
    
    cd ..
    print_success "Flutter web app built successfully"
}

# Function to validate CloudFormation template
validate_template() {
    print_step "Validating CloudFormation Template"
    
    if [ ! -f "web-infrastructure.yaml" ]; then
        print_error "CloudFormation template not found: web-infrastructure.yaml"
        exit 1
    fi
    
    aws cloudformation validate-template \
        --template-body file://web-infrastructure.yaml \
        --region $REGION &> /dev/null
    
    if [ $? -eq 0 ]; then
        print_success "CloudFormation template is valid"
    else
        print_error "CloudFormation template validation failed"
        exit 1
    fi
}

# Function to deploy CloudFormation stack
deploy_infrastructure() {
    print_step "Deploying AWS Infrastructure"
    
    echo "This will create:"
    echo "  • SSL Certificate for $DOMAIN_NAME"
    echo "  • S3 Bucket for hosting"
    echo "  • CloudFront Distribution (CDN)"
    echo "  • Route53 DNS records"
    echo ""
    
    # Check if stack already exists
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null || echo "DOES_NOT_EXIST")
    
    if [ "$STACK_STATUS" != "DOES_NOT_EXIST" ]; then
        print_warning "Stack $STACK_NAME already exists with status: $STACK_STATUS"
        
        if [[ "$STACK_STATUS" == *"FAILED"* ]] || [[ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ]] || [[ "$STACK_STATUS" == *"ROLLBACK"* ]]; then
            echo "Stack is in a failed or rollback state. Would you like to delete and recreate it?"
            read -p "Delete and recreate? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Deleting stack..."
                aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
                echo "Waiting for stack deletion to complete..."
                aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION
                print_success "Stack deleted"
            else
                print_error "Cannot proceed with stack in current state"
                exit 1
            fi
        elif [[ "$STACK_STATUS" == *"IN_PROGRESS"* ]]; then
            print_error "Stack is currently in progress state: $STACK_STATUS"
            echo "Please wait for the current operation to complete or cancel it manually."
            echo "You can monitor the stack at:"
            echo "https://console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks/events?stackId=$STACK_NAME"
            exit 1
        elif [[ "$STACK_STATUS" == "CREATE_COMPLETE" ]] || [[ "$STACK_STATUS" == "UPDATE_COMPLETE" ]]; then
            echo "Stack exists and is healthy. Proceeding with update..."
        fi
    fi
    
    echo "Deploying CloudFormation stack..."
    aws cloudformation deploy \
        --template-file web-infrastructure.yaml \
        --stack-name $STACK_NAME \
        --parameter-overrides \
            DomainName=$DOMAIN_NAME \
            RootDomainName=$ROOT_DOMAIN \
            HostedZoneId=$HOSTED_ZONE_ID \
        --capabilities CAPABILITY_IAM \
        --region $REGION \
        --no-fail-on-empty-changeset
    
    if [ $? -eq 0 ]; then
        print_success "Infrastructure deployed successfully"
    else
        print_error "Infrastructure deployment failed"
        echo "Check CloudFormation console for details:"
        echo "https://console.aws.amazon.com/cloudformation/home?region=$REGION"
        exit 1
    fi
}

# Function to wait for certificate validation
wait_for_certificate() {
    print_step "Waiting for SSL Certificate Validation"
    
    # Get certificate ARN from stack
    CERT_ARN=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='SSLCertificateArn'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$CERT_ARN" ]; then
        echo "Certificate ARN: $CERT_ARN"
        echo "Waiting for DNS validation (this may take a few minutes)..."
        
        # Certificate validation is automatic with DNS validation in CloudFormation
        print_success "Certificate validation configured"
    fi
}

# Function to upload files to S3
upload_to_s3() {
    print_step "Uploading Files to S3"
    
    # Get S3 bucket name from CloudFormation output
    BUCKET_NAME=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='WebAppBucketName'].OutputValue" \
        --output text)
    
    if [ -z "$BUCKET_NAME" ]; then
        print_error "Could not retrieve S3 bucket name from stack outputs"
        exit 1
    fi
    
    echo "S3 Bucket: $BUCKET_NAME"
    
    # Upload static assets, revalidated on every load. Flutter's filenames
    # (main.dart.js, flutter_bootstrap.js, canvaskit/, assets/) are not
    # content-hashed, so a long max-age leaves browsers running stale code
    # after a deploy. Unchanged files cost only a 304 via their ETag.
    # cp (not sync) so every object gets these headers, even if its size is unchanged.
    echo "Uploading static assets..."
    aws s3 cp $FLUTTER_APP_DIR/build/web/ s3://$BUCKET_NAME/ \
        --recursive \
        --only-show-errors \
        --cache-control "public, max-age=0, must-revalidate" \
        --exclude "*.html" \
        --exclude "*.json" \
        --region $REGION

    # Upload HTML and JSON files with no-cache for SPA routing
    echo "Uploading HTML and JSON files..."
    aws s3 cp $FLUTTER_APP_DIR/build/web/ s3://$BUCKET_NAME/ \
        --recursive \
        --only-show-errors \
        --cache-control "no-cache, no-store, must-revalidate" \
        --exclude "*" \
        --include "*.html" \
        --include "*.json" \
        --region $REGION

    # Remove files no longer in the build (everything else is already uploaded)
    echo "Removing stale files..."
    aws s3 sync $FLUTTER_APP_DIR/build/web/ s3://$BUCKET_NAME/ \
        --delete \
        --size-only \
        --only-show-errors \
        --cache-control "public, max-age=0, must-revalidate" \
        --exclude "*.html" \
        --exclude "*.json" \
        --region $REGION
    
    print_success "Files uploaded to S3"
}

# Function to invalidate CloudFront cache
invalidate_cloudfront() {
    print_step "Invalidating CloudFront Cache"
    
    # Get CloudFront distribution ID from CloudFormation output
    DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
        --output text)
    
    if [ -z "$DISTRIBUTION_ID" ]; then
        print_error "Could not retrieve CloudFront distribution ID"
        exit 1
    fi
    
    echo "CloudFront Distribution: $DISTRIBUTION_ID"
    
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id $DISTRIBUTION_ID \
        --paths "/*" \
        --region $REGION \
        --query "Invalidation.Id" \
        --output text)
    
    print_success "CloudFront cache invalidation started: $INVALIDATION_ID"
}

# Function to display final information
show_completion_info() {
    print_step "Deployment Complete!"
    
    # Get all outputs from stack
    WEB_URL=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='WebAppURL'].OutputValue" \
        --output text)
    
    CF_DOMAIN=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDomainName'].OutputValue" \
        --output text)
    
    echo ""
    echo -e "${GREEN}🎉 Your Flutter web app has been deployed successfully!${NC}"
    echo ""
    echo "📋 Deployment Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• App URL: $WEB_URL"
    echo "• CloudFront Domain: https://$CF_DOMAIN"
    echo "• S3 Bucket: $BUCKET_NAME"
    echo "• Distribution ID: $DISTRIBUTION_ID"
    echo "• Stack Name: $STACK_NAME"
    echo "• Region: $REGION"
    echo ""
    echo "⏰ Notes:"
    echo "• DNS propagation may take 5-15 minutes"
    echo "• CloudFront distribution may take 15-20 minutes to fully deploy"
    echo "• SSL certificate is automatically validated via DNS"
    echo ""
    echo "🔄 To update your app in the future:"
    echo "1. Make changes to your Flutter app"
    echo "2. Run this script again: ./deploy-web.sh"
    echo ""
    echo "📊 Monitor your deployment:"
    echo "• CloudFormation: https://console.aws.amazon.com/cloudformation/home?region=$REGION"
    echo "• CloudFront: https://console.aws.amazon.com/cloudfront/"
    echo "• S3: https://s3.console.aws.amazon.com/s3/buckets/$BUCKET_NAME"
}

# Function to handle errors
handle_error() {
    print_error "Deployment failed at step: $1"
    echo ""
    echo "💡 Troubleshooting tips:"
    echo "1. Check AWS CloudFormation console for detailed error messages"
    echo "2. Ensure your AWS credentials have necessary permissions"
    echo "3. Verify the domain name and hosted zone are correct"
    echo "4. Check CloudFormation events for specific failure reasons"
    echo ""
    echo "📚 Resources:"
    echo "• CloudFormation: https://console.aws.amazon.com/cloudformation/"
    echo "• Documentation: https://docs.aws.amazon.com/cloudformation/"
    exit 1
}

# Main deployment flow
main() {
    echo -e "${BLUE}Starting deployment process...${NC}"
    echo ""
    
    # Set error trap
    trap 'handle_error "$STEP"' ERR
    
    STEP="AWS CLI Check"
    check_aws_cli
    
    STEP="Flutter Check"
    check_flutter
    
    STEP="Hosted Zone Lookup"
    get_hosted_zone_id
    
    STEP="Template Validation"
    validate_template
    
    STEP="Flutter Build"
    build_flutter_app
    
    STEP="Infrastructure Deployment"
    deploy_infrastructure
    
    STEP="Certificate Validation"
    wait_for_certificate
    
    STEP="S3 Upload"
    upload_to_s3
    
    STEP="CloudFront Invalidation"
    invalidate_cloudfront
    
    # Clear error trap
    trap - ERR
    
    show_completion_info
}

# Show usage information
show_usage() {
    echo "Usage: $0 [DOMAIN_NAME] [STACK_NAME] [REGION] [FLUTTER_APP_DIR]"
    echo ""
    echo "Deploy a Flutter web app to AWS with S3, CloudFront, Route53, and SSL"
    echo ""
    echo "Arguments:"
    echo "  DOMAIN_NAME      - Full domain for your app (default: quote-me.anystupididea.com)"
    echo "  STACK_NAME       - CloudFormation stack name (default: quote-me-web-app)"
    echo "  REGION           - AWS region (default: us-east-1)"
    echo "  FLUTTER_APP_DIR  - Flutter app directory (default: dcc_mobile)"
    echo ""
    echo "Environment variables (optional):"
    echo "  DOMAIN_NAME, STACK_NAME, REGION, FLUTTER_APP_DIR"
    echo ""
    echo "Examples:"
    echo "  $0                                          # Use all defaults"
    echo "  $0 myapp.example.com                        # Custom domain"
    echo "  $0 myapp.example.com my-app-stack           # Custom domain and stack"
    echo ""
}

# Check if help is requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Run main deployment
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi