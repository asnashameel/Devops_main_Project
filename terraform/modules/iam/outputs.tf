output "arn" {
  description = "CodeBuild role ARN"
  value       = aws_iam_role.codebuild.arn
}

output "name" {
  description = "CodeBuild role name"
  value       = aws_iam_role.codebuild.name
} 
