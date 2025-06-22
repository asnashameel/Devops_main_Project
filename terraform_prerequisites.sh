#!/bin/bash

set -e

# Configuration
AWS_REGION="us-west-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROJECT_NAME="cloudops-demo"
BUCKET_NAME="${AWS_ACCOUNT_ID}-terraform-state-7736"
DYNAMODB_TABLE="terraform-locks"

echo "========================================="
echo "Setting up Terraform Prerequisites"
echo "========================================="
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET_NAME"
echo "DynamoDB Table: $DYNAMODB_TABLE"
echo "========================================="

# Create S3 bucket for Terraform state
echo "Creating S3 bucket for Terraform state..."
aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --region $AWS_REGION \
    --create-bucket-configuration LocationConstraint=$AWS_REGION \
    || echo "Bucket may already exist"

# Enable versioning on the bucket
echo "Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled

# Enable encryption on the bucket
echo "Enabling encryption on S3 bucket..."
aws s3api put-bucket-encryption \
    --bucket $BUCKET_NAME \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }'

# Block public access
echo "Blocking public access on S3 bucket..."
aws s3api put-public-access-block \
    --bucket $BUCKET_NAME \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
echo "Creating DynamoDB table for Terraform state locking..."
aws dynamodb create-table \
    --table-name $DYNAMODB_TABLE \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $AWS_REGION \
    || echo "DynamoDB table may already exist"

# Store DB password in Parameter Store
echo "Creating Parameter Store entry for DB password..."
aws ssm put-parameter \
    --name "/${PROJECT_NAME}/db-password" \
    --value "changeme-secure-password-123" \
    --type "SecureString" \
    --description "Database password for CloudOps demo" \
    --overwrite \
    || echo "Parameter may already exist"

echo "========================================="
echo "Prerequisites setup completed!"
echo "========================================="
echo "Next steps:"
echo "1. Update the DB password in Parameter Store if needed"
echo "2. Create CodePipeline manually in AWS Console"
echo "3. Use the buildspec-terraform.yml file"
echo "========================================="
