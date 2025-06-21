#!/bin/bash

# CloudFormation cleanup script for CloudOps infrastructure
set -e

# Configuration
STACK_NAME="cloudops-demo"
ADDONS_STACK_NAME="cloudops-demo-addons"
REGION="us-west-2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🧹 Starting CloudFormation cleanup...${NC}"

# Function to check if stack exists
stack_exists() {
    aws cloudformation describe-stacks --stack-name $1 --region $REGION >/dev/null 2>&1
}

# Function to wait for stack deletion to complete
wait_for_stack_deletion() {
    local stack_name=$1

    echo -e "${YELLOW}⏳ Waiting for stack deletion to complete...${NC}"

    aws cloudformation wait stack-delete-complete \
        --stack-name $stack_name \
        --region $REGION

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Stack deleted successfully${NC}"
    else
        echo -e "${RED}❌ Stack deletion failed${NC}"
        exit 1
    fi
}

# Uninstall AWS Load Balancer Controller first
echo -e "${YELLOW}📦 Uninstalling AWS Load Balancer Controller...${NC}"
if command -v helm &> /dev/null; then
    helm uninstall aws-load-balancer-controller -n kube-system || echo "AWS Load Balancer Controller not found"
else
    echo "Helm not found, skipping Load Balancer Controller cleanup"
fi

# Delete addons stack first
if stack_exists $ADDONS_STACK_NAME; then
    echo -e "${YELLOW}🔧 Deleting EKS addons stack...${NC}"
    aws cloudformation delete-stack \
        --stack-name $ADDONS_STACK_NAME \
        --region $REGION

    wait_for_stack_deletion $ADDONS_STACK_NAME
else
    echo -e "${GREEN}✅ Addons stack doesn't exist${NC}"
fi

# Delete main infrastructure stack
if stack_exists $STACK_NAME; then
    echo -e "${YELLOW}📦 Deleting main infrastructure stack...${NC}"
    aws cloudformation delete-stack \
        --stack-name $STACK_NAME \
        --region $REGION

    wait_for_stack_deletion $STACK_NAME
else
    echo -e "${GREEN}✅ Main stack doesn't exist${NC}"
fi

echo -e "${GREEN}🎉 Cleanup completed successfully!${NC}"
echo -e "${GREEN}📋 Summary:${NC}"
echo -e "  ✅ EKS addons stack deleted: $ADDONS_STACK_NAME"
echo -e "  ✅ Main infrastructure stack deleted: $STACK_NAME"
echo -e "  ✅ AWS Load Balancer Controller uninstalled"

echo -e "${YELLOW}ℹ️  Note: ECR repositories may still contain images${NC}"
echo -e "${YELLOW}ℹ️  Manual cleanup may be required for:${NC}"
echo -e "  - ECR repository images"
echo -e "  - RDS snapshots (if any)"
echo -e "  - CloudWatch logs"