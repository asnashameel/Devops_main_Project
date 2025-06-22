# modules/iam/outputs.tf

output "codebuild_role_arn" {
  description = "The ARN of the CodeBuild IAM role created by this module."
  value       = aws_iam_role.codebuild.arn
}

output "codebuild_role_name" {
  description = "The name of the CodeBuild IAM role created by this module."
  value       = aws_iam_role.codebuild.name
}
