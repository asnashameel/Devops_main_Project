# CloudFormation Templates for CloudOps Infrastructure

This directory contains comprehensive CloudFormation templates that provide the same infrastructure as the Terraform configuration, including:

- **VPC** with public, private, and intra subnets across 3 AZs
- **EKS Cluster** with managed node groups
- **RDS PostgreSQL** database with enhanced monitoring
- **ECR Repositories** for container images
- **IAM Roles** for CodeBuild, EBS CSI driver, and Load Balancer Controller
- **EKS Addons** including EBS CSI driver
- **AWS Load Balancer Controller** via Helm

## 📁 Files Structure

```
cloudformation/
├── main-template.yaml          # Main infrastructure template
├── eks-addons.yaml            # EKS addons and service roles
├── parameters.json            # Parameter values for deployment
├── deploy.sh                  # Automated deployment script
├── cleanup.sh                 # Cleanup script
└── README.md                  # This file
```

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI** configured with appropriate permissions
   ```bash
   aws configure
   ```

2. **Helm** installed for AWS Load Balancer Controller
   ```bash
   # macOS
   brew install helm
   
   # Linux
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

3. **kubectl** for Kubernetes management
   ```bash
   # macOS
   brew install kubectl
   
   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   ```

### Deployment Steps

1. **Clone and navigate to cloudformation directory**
   ```bash
   cd cloudformation
   ```

2. **Update parameters**
   Edit `parameters.json` and **change the database password**:
   ```json
   {
     "ParameterKey": "DBPassword",
     "ParameterValue": "YourSecurePassword123!"
   }
   ```

3. **Make scripts executable**
   ```bash
   chmod +x deploy.sh cleanup.sh
   ```

4. **Deploy infrastructure**
   ```bash
   ./deploy.sh
   ```

The deployment script will:
- ✅ Validate CloudFormation templates
- ✅ Deploy main infrastructure stack
- ✅ Deploy EKS addons stack
- ✅ Configure kubectl
- ✅ Install AWS Load Balancer Controller

## 📋 Template Details

### Main Template (`main-template.yaml`)

**Parameters:**
- `ProjectName`: Project name for resource naming (default: cloudops-demo)
- `Environment`: Environment name (dev/staging/prod/demo)
- `KubernetesVersion`: EKS cluster version (default: 1.27)
- `NodeGroupInstanceType`: EC2 instance type (default: t3.medium)
- `NodeGroupMinSize/MaxSize/DesiredSize`: Node group scaling config
- `DBName/DBUsername/DBPassword`: RDS configuration

**Key Resources:**
- **VPC**: 10.0.0.0/16 CIDR with proper subnet layout
- **EKS Cluster**: Managed cluster with OIDC provider
- **EKS Node Group**: Managed node group in private subnets
- **RDS Instance**: PostgreSQL 15.4 with enhanced monitoring
- **ECR Repositories**: For frontend and backend images
- **Security Groups**: Properly configured for EKS and RDS
- **IAM Roles**: For EKS cluster, node group, and CodeBuild

### EKS Addons Template (`eks-addons.yaml`)

**Resources:**
- **EBS CSI Driver**: IAM role and EKS addon
- **AWS Load Balancer Controller**: IAM role with comprehensive policies
- **IRSA Configuration**: Service account roles with OIDC

## 🔧 Manual Deployment

If you prefer manual deployment instead of using the script:

1. **Deploy main stack**
   ```bash
   aws cloudformation create-stack \
     --stack-name cloudops-demo \
     --template-body file://main-template.yaml \
     --parameters file://parameters.json \
     --capabilities CAPABILITY_NAMED_IAM \
     --region us-west-2
   ```

2. **Wait for completion**
   ```bash
   aws cloudformation wait stack-create-complete \
     --stack-name cloudops-demo \
     --region us-west-2
   ```

3. **Get OIDC issuer**
   ```bash
   aws eks describe-cluster \
     --name cloudops-demo \
     --region us-west-2 \
     --query "cluster.identity.oidc.issuer" \
     --output text
   ```

4. **Deploy addons stack** (update parameters with OIDC issuer)
   ```bash
   aws cloudformation create-stack \
     --stack-name cloudops-demo-addons \
     --template-body file://eks-addons.yaml \
     --parameters ParameterKey=EKSClusterOIDCIssuer,ParameterValue=<OIDC_ISSUER> \
     --capabilities CAPABILITY_NAMED_IAM \
     --region us-west-2
   ```

## 📊 Outputs

After successful deployment, you'll have access to:

**Main Stack Outputs:**
- VPC ID and subnet IDs
- EKS cluster name and endpoint
- RDS endpoint and port
- ECR repository URIs
- CodeBuild role ARN

**Key Resources Created:**
- EKS cluster: `cloudops-demo`
- RDS instance: `cloudops-demo-postgres`
- ECR repos: `cloudops-frontend`, `cloudops-backend`
- VPC: `cloudops-demo-vpc`

## 🎯 Post-Deployment

1. **Verify cluster access**
   ```bash
   kubectl get nodes
   kubectl get pods -n kube-system
   ```

2. **Check AWS Load Balancer Controller**
   ```bash
   kubectl get deployment -n kube-system aws-load-balancer-controller
   ```

3. **Verify EBS CSI driver**
   ```bash
   kubectl get pods -n kube-system -l app=ebs-csi-controller
   ```

## 🗑️ Cleanup

To delete all resources:

```bash
./cleanup.sh
```

Or manually:
```bash
# Delete addons stack first
aws cloudformation delete-stack --stack-name cloudops-demo-addons --region us-west-2

# Wait for completion
aws cloudformation wait stack-delete-complete --stack-name cloudops-demo-addons --region us-west-2

# Delete main stack
aws cloudformation delete-stack --stack-name cloudops-demo --region us-west-2
```

## 🔐 IAM Permissions Required

Your AWS user/role needs these permissions:
- `AmazonEKSClusterPolicy`
- `AmazonEKSWorkerNodePolicy`
- `AmazonEKS_CNI_Policy`
- `AmazonEC2ContainerRegistryFullAccess`
- `AmazonRDSFullAccess`
- `AmazonVPCFullAccess`
- `CloudFormationFullAccess`
- `IAMFullAccess`

## 🆚 Terraform vs CloudFormation

| Feature | Terraform | CloudFormation |
|---------|-----------|----------------|
| **Syntax** | HCL (more readable) | JSON/YAML |
| **State Management** | External state file | AWS managed |
| **Multi-cloud** | ✅ Yes | ❌ AWS only |
| **Modules** | Flexible modules | Nested stacks |
| **Drift Detection** | Manual | Built-in |
| **Cost** | Free (open source) | Free |
| **Learning Curve** | Moderate | Steep |

## 🚨 Important Notes

1. **Security**: Change the default database password before deployment
2. **Costs**: The infrastructure will incur AWS charges (EKS, RDS, EC2, etc.)
3. **Cleanup**: Always run cleanup when done to avoid ongoing charges
4. **Monitoring**: RDS has enhanced monitoring enabled (additional cost)
5. **Regions**: Templates are configured for us-west-2 by default

## 🔗 Useful Commands

```bash
# List all stacks
aws cloudformation list-stacks --region us-west-2

# Get stack outputs
aws cloudformation describe-stacks --stack-name cloudops-demo --region us-west-2 --query "Stacks[0].Outputs"

# Check kubectl configuration
kubectl config current-context

# View EKS cluster info
aws eks describe-cluster --name cloudops-demo --region us-west-2
``` 