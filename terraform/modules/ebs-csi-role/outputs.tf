output "arn" {
  description = "EBS CSI driver role ARN"
  value       = aws_iam_role.ebs_csi.arn
}

output "name" {
  description = "EBS CSI driver role name"
  value       = aws_iam_role.ebs_csi.name
} 