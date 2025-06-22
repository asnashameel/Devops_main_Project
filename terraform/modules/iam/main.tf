resource "aws_iam_role" "codebuild" {
  name = "${var.cluster_name}-codebuild-role"

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

# This is the main policy for your CodeBuild role.
# All necessary permissions for Terraform backend, EKS interaction, etc.,
# should be defined here.
resource "aws_iam_role_policy" "codebuild" {
  name = "${var.cluster_name}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs permissions
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      # ECR Pull (read) permissions
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      # ECR Push (write) permissions (if CodeBuild is building and pushing images)
      {
        Effect = "Allow"
        Action = [
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
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
          "s3:GetBucketAcl"
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
      # EKS Cluster description and kubectl access
      {
        Sid    = "AllowEKSClusterDescriptionAndKubectlAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup",
          "ssm:GetParameters" # Needed by aws cli for EKS, especially update-kubeconfig
        ]
        Resource = [
          "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}",
          "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:nodegroup/${var.cluster_name}/*/*",
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/*" # Broad for SSM if used by EKS utilities
        ]
      },
      # SSM Parameter Store Access (for DB_PASSWORD)
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
      # EC2 Describe Availability Zones
      {
        Sid    = "AllowEC2AvailabilityZones"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*" # DescribeAvailabilityZones is a read-only API that typically operates across all resources, hence "*"
      },
      # IAM GetRole for current session (THIS IS THE ONE THAT WAS TROUBLING YOU)
      {
        Sid    = "AllowIAMGetRoleForCurrentSession"
        Effect = "Allow"
        Action = [
          "iam:GetRole"
        ]
        # Granting on '*' for iam:GetRole is often necessary for data sources like aws_iam_session_context
        # to query their own role name when the call might not be a direct ARN lookup.
        Resource = "*" 
        # Alternatively, if you want to be super strict, use the specific role ARN:
        # Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.cluster_name}-codebuild-role"
        # BUT THE '*' IS LIKELY THE SOLUTION FOR THE PERSISTENT ERROR.
      },
      # Potentially needed for EKS modules to pass roles to services or manage cluster roles
      {
        Sid    = "AllowIAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        # IMPORTANT: This should be restricted to *only* the roles your CodeBuild role is allowed to pass
        # to EKS, such as the EKS cluster role, node group roles, or service account roles (IRSA).
        # For now, if you are actively creating these roles via Terraform, a '*' might be needed initially
        # but refine this later.
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eks-cluster-role-*", # Example placeholder
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eks-node-group-role-*", # Example placeholder
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/some-irsa-role-*" # Example IRSA role
        ]
      }
    ]
  })
}

# --- REMOVE OR COMMENT OUT THIS BLOCK ---
# resource "aws_iam_role_policy_attachment" "codebuild_eks" {
#   role       = aws_iam_role.codebuild.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
# }
# This policy is typically for the EKS Cluster's role, not the CodeBuild role.
# Its permissions are either redundant with what's in your inline policy,
# or not directly relevant to what the CodeBuild role needs to do.
# Relying on the single, comprehensive inline policy is better for clarity and debugging.
