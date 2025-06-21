output "role_arn" {
  description = "AWS Load Balancer Controller role ARN"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "role_name" {
  description = "AWS Load Balancer Controller role name"
  value       = aws_iam_role.aws_load_balancer_controller.name
} 