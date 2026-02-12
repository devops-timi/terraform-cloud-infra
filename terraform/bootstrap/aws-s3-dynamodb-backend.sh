#!/bin/bash

set -e # Exit immediately if a command fails

# Set your region
AWS_REGION="us-east-1"

# Create S3 bucket for Terraform state (MUST be globally unique)
# Replace with your own unique name
BUCKET_NAME="infra-terraform-state"

aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $AWS_REGION

# Enable versioning (allows state recovery)
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access (security)
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION

# Save your bucket name (you'll need it)
echo "Your S3 bucket name: $BUCKET_NAME"
echo "Save this name - you'll use it in backend.tf"

