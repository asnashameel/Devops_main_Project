terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "CloudOps-Demo"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

locals {
  name   = var.cluster_name
  region = var.aws_region

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project     = "CloudOps-Demo"
    Environment = var.environment
  }
}

data "aws_availability_zones" "available" {}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_dns_hostnames = true
  enable_dns_support = true

  # Kubernetes tags
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.15"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["t3.medium"]

    attach_cluster_primary_security_group = true
  }

  eks_managed_node_groups = {
    blue = {
      name = "${local.name}-blue"
      
      min_size     = 1
      max_size     = 10
      desired_size = 3

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      labels = {
        Environment = var.environment
        NodeGroup   = "blue"
      }

      taints = []

      update_config = {
        max_unavailable_percentage = 33
      }

      tags = {
        NodeGroup = "blue"
      }
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = module.codebuild_role.arn
      username = "codebuild"
      groups   = ["system:masters"]
    },
  ]

  tags = local.tags
}

################################################################################
# RDS Module
################################################################################

module "rds" {
  source = "./modules/rds"

  cluster_name = local.name
  environment  = var.environment
  
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.intra_subnets
  eks_security_group_id = module.eks.cluster_security_group_id
  
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  tags = local.tags
}

################################################################################
# ECR Repositories
################################################################################

module "ecr" {
  source = "./modules/ecr"

  repository_names = ["cloudops-frontend", "cloudops-backend"]
  
  tags = local.tags
}

################################################################################
# CodeBuild & CI/CD
################################################################################

module "codebuild_role" {
  source = "./modules/iam"

  cluster_name = local.name
  
  tags = local.tags
}

################################################################################
# EKS Addons
################################################################################

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = module.eks.cluster_name
  addon_name = "aws-ebs-csi-driver"
  addon_version = "v1.21.0-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn = module.ebs_csi_role.arn

  tags = local.tags
}

module "ebs_csi_role" {
  source = "./modules/ebs-csi-role"

  cluster_name = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  
  tags = local.tags
}

################################################################################
# Load Balancer Controller
################################################################################

module "load_balancer_controller" {
  source = "./modules/load-balancer-controller"

  cluster_name = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  vpc_id = module.vpc.vpc_id

  depends_on = [module.eks]

  tags = local.tags
} 
