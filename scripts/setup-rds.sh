#!/bin/bash

# CloudOps Demo - RDS Setup Script
# This script sets up AWS RDS PostgreSQL for the EKS application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"kube-cluster"}
REGION=${AWS_REGION:-"us-east-1"}
STACK_NAME="cloudops-demo-rds"
DB_PASSWORD=${DB_PASSWORD:-""}

echo -e "${BLUE}🗄️  Setting up AWS RDS PostgreSQL for CloudOps Demo${NC}"
echo "================================================="

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI is not installed${NC}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo -e "${RED}❌ AWS credentials not configured${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites met${NC}"
}

# Get EKS cluster information
get_eks_info() {
    echo -e "${YELLOW}🔍 Getting EKS cluster information...${NC}"
    
    # Get VPC ID
    VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
    if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
        echo -e "${RED}❌ Could not find VPC for EKS cluster: $CLUSTER_NAME${NC}"
        exit 1
    fi
    
    # Get private subnet IDs
    PRIVATE_SUBNETS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.subnetIds' --output text | tr '\t' ',')
    if [ -z "$PRIVATE_SUBNETS" ]; then
        echo -e "${RED}❌ Could not find private subnets for EKS cluster${NC}"
        exit 1
    fi
    
    # Get EKS worker node security group
    NODE_GROUP_NAME=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION --query 'nodegroups[0]' --output text)
    if [ "$NODE_GROUP_NAME" == "None" ] || [ -z "$NODE_GROUP_NAME" ]; then
        echo -e "${RED}❌ Could not find EKS node group${NC}"
        exit 1
    fi
    
    SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region $REGION --filters "Name=group-name,Values=eks-cluster-sg-$CLUSTER_NAME-*" --query 'SecurityGroups[0].GroupId' --output text)
    if [ "$SECURITY_GROUP_ID" == "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
        # Try alternative approach
        SECURITY_GROUP_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
    fi
    
    if [ "$SECURITY_GROUP_ID" == "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
        echo -e "${RED}❌ Could not find EKS security group${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ EKS Information gathered:${NC}"
    echo "  VPC ID: $VPC_ID"
    echo "  Private Subnets: $PRIVATE_SUBNETS"
    echo "  Security Group: $SECURITY_GROUP_ID"
}

# Get database password
get_db_password() {
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${YELLOW}🔐 Database password not provided${NC}"
        read -s -p "Enter database password (minimum 8 characters): " DB_PASSWORD
        echo
        
        if [ ${#DB_PASSWORD} -lt 8 ]; then
            echo -e "${RED}❌ Password must be at least 8 characters${NC}"
            exit 1
        fi
    fi
}

# Create RDS using CloudFormation
create_rds() {
    echo -e "${YELLOW}🏗️  Creating RDS PostgreSQL instance...${NC}"
    
    # Check if stack already exists
    if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Stack $STACK_NAME already exists. Updating...${NC}"
        OPERATION="update-stack"
    else
        echo -e "${YELLOW}📦 Creating new stack: $STACK_NAME${NC}"
        OPERATION="create-stack"
    fi
    
    # Deploy CloudFormation stack
    aws cloudformation $OPERATION \
        --stack-name $STACK_NAME \
        --template-body file://../infrastructure/rds-setup.yaml \
        --region $REGION \
        --parameters \
            ParameterKey=VPCId,ParameterValue=$VPC_ID \
            ParameterKey=PrivateSubnetIds,ParameterValue=\"$PRIVATE_SUBNETS\" \
            ParameterKey=EKSSecurityGroupId,ParameterValue=$SECURITY_GROUP_ID \
            ParameterKey=DBPassword,ParameterValue=$DB_PASSWORD \
        --capabilities CAPABILITY_IAM
    
    echo -e "${YELLOW}⏳ Waiting for stack deployment to complete...${NC}"
    aws cloudformation wait stack-${OPERATION%-stack}-complete --stack-name $STACK_NAME --region $REGION
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ RDS stack deployed successfully${NC}"
    else
        echo -e "${RED}❌ RDS stack deployment failed${NC}"
        exit 1
    fi
}

# Get RDS endpoint and update ConfigMap
update_configmap() {
    echo -e "${YELLOW}🔧 Updating Kubernetes ConfigMap...${NC}"
    
    # Get RDS endpoint from CloudFormation outputs
    DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' --output text)
    
    if [ -z "$DB_ENDPOINT" ]; then
        echo -e "${RED}❌ Could not retrieve RDS endpoint${NC}"
        exit 1
    fi
    
    # Update the ConfigMap file
    sed -i.bak "s/DB_HOST: \".*\"/DB_HOST: \"$DB_ENDPOINT\"/" ../k8s/01-configmap.yaml
    rm -f k8s/01-configmap.yaml.bak
    
    echo -e "${GREEN}✅ ConfigMap updated with RDS endpoint: $DB_ENDPOINT${NC}"
}

# Initialize database with schema
init_database() {
    echo -e "${YELLOW}🔄 Initializing database schema...${NC}"
    
    # Get RDS endpoint
    DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' --output text)
    
    # Create init script
    cat > /tmp/init_rds.sql << EOF
-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (name, email) VALUES 
    ('John Doe', 'john.doe@example.com'),
    ('Jane Smith', 'jane.smith@example.com'),
    ('Bob Johnson', 'bob.johnson@example.com'),
    ('Alice Brown', 'alice.brown@example.com')
ON CONFLICT (email) DO NOTHING;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
EOF
    
    echo -e "${BLUE}📝 Database initialization script created${NC}"
    echo -e "${YELLOW}⚠️  To initialize the database, run:${NC}"
    echo "psql -h $DB_ENDPOINT -U postgres -d cloudops_demo -f /tmp/init_rds.sql"
    echo -e "${YELLOW}💡 Or use a database client to connect and run the SQL commands${NC}"
}

# Show deployment information
show_info() {
    echo -e "${BLUE}📊 RDS Deployment Information${NC}"
    echo "================================="
    
    # Get stack outputs
    DB_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' --output text)
    DB_PORT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`DBPort`].OutputValue' --output text)
    DB_NAME=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`DBName`].OutputValue' --output text)
    
    echo -e "${YELLOW}Database Details:${NC}"
    echo "  Endpoint: $DB_ENDPOINT"
    echo "  Port: $DB_PORT"
    echo "  Database: $DB_NAME"
    echo "  Username: postgres"
    echo ""
    echo -e "${YELLOW}Connection String:${NC}"
    echo "postgresql://postgres:YOUR_PASSWORD@$DB_ENDPOINT:$DB_PORT/$DB_NAME"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Initialize the database schema (see above)"
    echo "2. Deploy your application: ./scripts/deploy.sh"
    echo "3. The ConfigMap has been updated with the RDS endpoint"
}

# Main execution
main() {
    check_prerequisites
    get_eks_info
    get_db_password
    create_rds
    update_configmap
    init_database
    show_info
    
    echo -e "\n${GREEN}🎉 RDS setup completed successfully!${NC}"
}

# Execute main function
main "$@" 
