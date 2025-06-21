#!/bin/bash

# CloudFormation deployment script for CloudOps infrastructure
set -e

# Configuration
STACK_NAME="cloudops-demo"
ADDONS_STACK_NAME="cloudops-demo-addons"
REGION="us-west-2"
TEMPLATE_FILE="main-template.yaml"
ADDONS_TEMPLATE_FILE="eks-addons.yaml"
PARAMETERS_FILE="parameters.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting CloudFormation deployment...${NC}"

# Function to check if stack exists
stack_exists() {
    aws cloudformation describe-stacks --stack-name $1 --region $REGION >/dev/null 2>&1
}

# Function to wait for stack operation to complete
wait_for_stack() {
    local stack_name=$1
    local operation=$2
    
    echo -e "${YELLOW}⏳ Waiting for stack $operation to complete...${NC}"
    
    aws cloudformation wait stack-${operation}-complete \
        --stack-name $stack_name \
        --region $REGION
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Stack $operation completed successfully${NC}"
    else
        echo -e "${RED}❌ Stack $operation failed${NC}"
        exit 1
    fi
}

# Validate CloudFormation templates
echo -e "${YELLOW}🔍 Validating CloudFormation templates...${NC}"

aws cloudformation validate-template \
    --template-body file://$TEMPLATE_FILE \
    --region $REGION

aws cloudformation validate-template \
    --template-body file://$ADDONS_TEMPLATE_FILE \
    --region $REGION

echo -e "${GREEN}✅ Templates validated successfully${NC}"

# Deploy main infrastructure stack
echo -e "${YELLOW}📦 Deploying main infrastructure stack...${NC}"

if stack_exists $STACK_NAME; then
    echo -e "${YELLOW}Stack exists, updating...${NC}"
    aws cloudformation update-stack \
        --stack-name $STACK_NAME \
        --template-body file://$TEMPLATE_FILE \
        --parameters file://$PARAMETERS_FILE \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION
    
    wait_for_stack $STACK_NAME "update"
else
    echo -e "${YELLOW}Creating new stack...${NC}"
    aws cloudformation create-stack \
        --stack-name $STACK_NAME \
        --template-body file://$TEMPLATE_FILE \
        --parameters file://$PARAMETERS_FILE \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION
    
    wait_for_stack $STACK_NAME "create"
fi

# Get outputs from main stack for addons stack
echo -e "${YELLOW}📋 Retrieving stack outputs...${NC}"

PROJECT_NAME=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query "Stacks[0].Parameters[?ParameterKey=='ProjectName'].ParameterValue" \
    --output text)

EKS_CLUSTER_NAME=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query "Stacks[0].Outputs[?OutputKey=='EKSClusterName'].OutputValue" \
    --output text)

VPC_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query "Stacks[0].Outputs[?OutputKey=='VPCId'].OutputValue" \
    --output text)

# Get OIDC issuer URL (this requires AWS CLI)
OIDC_ISSUER=$(aws eks describe-cluster \
    --name $EKS_CLUSTER_NAME \
    --region $REGION \
    --query "cluster.identity.oidc.issuer" \
    --output text | sed 's|https://||')

echo -e "${GREEN}📊 Stack outputs retrieved:${NC}"
echo -e "  Project Name: $PROJECT_NAME"
echo -e "  EKS Cluster: $EKS_CLUSTER_NAME"
echo -e "  VPC ID: $VPC_ID"
echo -e "  OIDC Issuer: $OIDC_ISSUER"

# Create parameters for addons stack
cat > addons-parameters.json << EOF
[
  {
    "ParameterKey": "ProjectName",
    "ParameterValue": "$PROJECT_NAME"
  },
  {
    "ParameterKey": "EKSClusterName",
    "ParameterValue": "$EKS_CLUSTER_NAME"
  },
  {
    "ParameterKey": "VPCId",
    "ParameterValue": "$VPC_ID"
  },
  {
    "ParameterKey": "EKSClusterOIDCIssuer",
    "ParameterValue": "$OIDC_ISSUER"
  }
]
EOF

# Deploy addons stack
echo -e "${YELLOW}🔧 Deploying EKS addons stack...${NC}"

if stack_exists $ADDONS_STACK_NAME; then
    echo -e "${YELLOW}Addons stack exists, updating...${NC}"
    aws cloudformation update-stack \
        --stack-name $ADDONS_STACK_NAME \
        --template-body file://$ADDONS_TEMPLATE_FILE \
        --parameters file://addons-parameters.json \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION
    
    wait_for_stack $ADDONS_STACK_NAME "update"
else
    echo -e "${YELLOW}Creating new addons stack...${NC}"
    aws cloudformation create-stack \
        --stack-name $ADDONS_STACK_NAME \
        --template-body file://$ADDONS_TEMPLATE_FILE \
        --parameters file://addons-parameters.json \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION
    
    wait_for_stack $ADDONS_STACK_NAME "create"
fi

# Clean up temporary parameters file
rm -f addons-parameters.json

# Configure kubectl
echo -e "${YELLOW}⚙️  Configuring kubectl...${NC}"
aws eks update-kubeconfig --region $REGION --name $EKS_CLUSTER_NAME

# Install AWS Load Balancer Controller using Helm
echo -e "${YELLOW}📦 Installing AWS Load Balancer Controller...${NC}"

# Add the EKS chart repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get the Load Balancer Controller role ARN
ALB_CONTROLLER_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name $ADDONS_STACK_NAME \
    --region $REGION \
    --query "Stacks[0].Outputs[?OutputKey=='AWSLoadBalancerControllerRoleArn'].OutputValue" \
    --output text)

# Install AWS Load Balancer Controller
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=$EKS_CLUSTER_NAME \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ALB_CONTROLLER_ROLE_ARN \
    --set vpcId=$VPC_ID \
    --set region=$REGION

echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo -e "${GREEN}📋 Summary:${NC}"
echo -e "  ✅ Main infrastructure stack: $STACK_NAME"
echo -e "  ✅ EKS addons stack: $ADDONS_STACK_NAME"
echo -e "  ✅ EKS cluster: $EKS_CLUSTER_NAME"
echo -e "  ✅ AWS Load Balancer Controller installed"
echo -e "  ✅ kubectl configured"

echo -e "${YELLOW}🔗 Useful commands:${NC}"
echo -e "  kubectl get nodes"
echo -e "  kubectl get pods -n kube-system"
echo -e "  aws eks describe-cluster --name $EKS_CLUSTER_NAME --region $REGION" 