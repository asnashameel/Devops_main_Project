Complete Terraform Configuration Overview:
Main Configuration (main.tf)
Providers: AWS, Kubernetes, Helm with proper versioning
VPC Module: Creates VPC with public/private/intra subnets, NAT gateway
EKS Cluster: Managed EKS cluster with node groups
RDS: PostgreSQL database in private subnets
ECR: Container registries for your applications
IAM: CodeBuild role for CI/CD
EKS Addons: EBS CSI driver for persistent volumes
Load Balancer Controller: AWS Load Balancer Controller via Helm
Modules Created:
modules/rds/
PostgreSQL RDS instance with security groups
Enhanced monitoring and Performance Insights
Automatic backups and maintenance windows
modules/ecr/
ECR repositories for frontend and backend
Lifecycle policies for image cleanup
Vulnerability scanning enabled
modules/iam/
CodeBuild service role
Permissions for ECR, EKS, and S3
modules/ebs-csi-role/
IAM role for EBS CSI driver
IRSA (IAM Roles for Service Accounts) configuration
modules/load-balancer-controller/
AWS Load Balancer Controller installation
IAM role with web identity federation
Helm chart deployment
Key Features:
Security: Non-root containers, private subnets, security groups
High Availability: Multi-AZ deployment, auto-scaling
Monitoring: Enhanced RDS monitoring, Performance Insights
CI/CD Ready: CodeBuild integration, ECR repositories
Kubernetes Native: Load balancer controller, EBS CSI driver
Usage:
Copy terraform.tfvars.example to terraform.tfvars
Update the database password and other values as needed
Run:
Apply to terraform.tf...
Run
apply
After Deployment:
Configure kubectl: aws eks update-kubeconfig --region us-west-2 --name cloudops-demo
Your ECR repositories will be ready for pushing container images
RDS database will be accessible from the EKS cluster
Load balancer controller will handle ingress resources
The configuration is now complete and production-ready with all necessary components for your CloudOps project!