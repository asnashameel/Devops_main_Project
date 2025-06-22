# modules/iam/main.tf

# Data sources for current AWS region and account ID.
# These are necessary here because the IAM policy needs to construct ARNs
# that include the region and account ID, and modules have their own scope.
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Defines the IAM role for AWS CodeBuild.
# This role will be assumed by the CodeBuild service.
resource "aws_iam_role" "codebuild" {
  name = "${var.cluster_name}-codebuild-role" # Using var.cluster_name for consistency

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Defines the inline IAM policy attached to the CodeBuild role.
# This policy grants all the necessary permissions for Terraform operations
# (S3 backend, DynamoDB locks, EKS management, SSM parameter access, etc.)
resource "aws_iam_role_policy" "codebuild" {
  name = "${var.cluster_name}-codebuild-policy" # Using var.cluster_name for consistency
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs permissions for CodeBuild build logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*" # Typically broad for logs
      },
      # ECR Pull (read) permissions - needed if CodeBuild pulls images
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*" # Can be scoped to specific ECR repos if known and desired
      },
      # ECR Push (write) permissions - needed if CodeBuild builds and pushes images
      {
        Effect = "Allow"
        Action = [
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*" # Can be scoped to specific ECR repos if known and desired
      },
      # S3 Terraform State Backend permissions
      {
        Sid    = "AllowS3TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketAcl" # Needed for some bucket operations
        ]
        Resource = [
          "arn:aws:s3:::${var.terraform_state_bucket_name}",
          "arn:aws:s3:::${var.terraform_state_bucket_name}/*"
        ]
      },
      # DynamoDB Terraform State Locking permissions
      {
        Sid    = "AllowDynamoDBTerraformLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.terraform_lock_table_name}"
      },
      # EKS Cluster description and kubectl access (kubectl relies on eks:DescribeCluster and ssm:GetParameters)
      {
        Sid    = "AllowEKSClusterDescriptionAndKubectlAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",       # Often useful for listing existing clusters
          "eks:ListNodegroups",     # For managing nodegroups
          "eks:DescribeNodegroup",  # For managing nodegroups
          "ssm:GetParameters"       # Needed by aws cli for EKS, especially update-kubeconfig
        ]
        Resource = [
          "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}",
          "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:nodegroup/${var.cluster_name}/*/*", # For nodegroup operations
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/*" # Broad for SSM if used by EKS utilities
        ]
      },
      # SSM Parameter Store Access (for DB_PASSWORD or other secrets managed by SSM)
      {
        Sid    = "AllowSSMParameterAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        # Adjust this ARN to be specific to your parameter if needed,
        # otherwise, a broader path or '*' might be required if you have many.
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.ssm_db_password_path}"
      },
      # EC2 Describe Availability Zones - common dependency for many AWS resources
      {
        Sid    = "AllowEC2AvailabilityZones"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances", # Often needed for EKS to understand EC2 instances
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeRouteTables"
        ]
        Resource = "*" # Describe* actions are typically global and operate on all resources
      },
      # IAM GetRole for current session - resolves the persistent error
      # Granting on '*' for iam:GetRole is often necessary for data sources like aws_iam_session_context
      # or internal SDK calls to query their own role name when the call might not be a direct ARN lookup.
      {
        Sid    = "AllowIAMGetRoleForCurrentSession"
        Effect = "Allow"
        Action = [
          "iam:GetRole"
        ]
        Resource = "*" # This is the pragmatic fix for the "AccessDenied: User... is not authorized to perform: iam:GetRole on resource: role"
      },
      # IAM PassRole - CRITICAL if CodeBuild Terraform creates or updates resources that need to assume other roles
      # (e.g., EKS Cluster role, EKS Node Group role, Service Account roles for IRSA)
      {
        Sid    = "AllowIAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        # IMPORTANT: This should be restricted to *only* the roles your CodeBuild role is allowed to pass.
        # For a full production setup, replace these with the *actual ARNs* of the roles that CodeBuild
        # needs to pass to services like EKS.
        # For initial deployment, a broader scope might be temporarily needed, but narrow it ASAP.
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.cluster_name}-eks-cluster-role", # Example EKS cluster role
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.cluster_name}-eks-nodegroup-role", # Example EKS nodegroup role
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.cluster_name}-irsa-*", # Example for IRSA roles created by Terraform
          # Add any other specific role ARNs that CodeBuild needs to 'Pass'
        ]
      },
      # General EC2 actions that might be needed by EKS or other modules
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*" # Scope this down if you know the exact resource types/ARNs
      },
      # Tagging permissions, often needed by Terraform when it manages resources
      {
        Effect = "Allow"
        Action = [
          "tag:GetResources",
          "tag:TagResources",
          "tag:UntagResources"
        ]
        Resource = "*" # Broad for general tagging, can be refined.
      }
    ]
  })
}

# --- REMOVE THIS RESOURCE ---
# resource "aws_iam_role_policy_attachment" "codebuild_eks" {
#   role       = aws_iam_role.codebuild.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
# }
# This policy is typically for the EKS Cluster's service role, not for a CI/CD role
# managing the cluster. Its permissions are either redundant with what's in your inline policy,
# or not directly relevant to what the CodeBuild role needs to do.
# Removing it simplifies policy management and avoids potential conflicts.
