# modules/iam/variables.tf

variable "cluster_name" {
  description = "The name of the EKS cluster (used for naming the CodeBuild role and policy)."
  type        = string
}

variable "terraform_state_bucket_name" {
  description = "The name of the S3 bucket used for Terraform state."
  type        = string
}

variable "terraform_lock_table_name" {
  description = "The name of the DynamoDB table used for Terraform state locking."
  type        = string
}

variable "ssm_db_password_path" {
  description = "The path in SSM Parameter Store for the database password (used in CodeBuild policy)."
  type        = string
  # Example default, but you should align with your actual parameter path:
  # default = "/cloudops-demo/db-password"
}

variable "tags" {
  description = "A map of tags to apply to the CodeBuild IAM role."
  type        = map(string)
  default     = {}
}
