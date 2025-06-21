output "repository_urls" {
  description = "Map of repository names to URLs"
  value = {
    for k, repo in aws_ecr_repository.this : k => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository names to ARNs"
  value = {
    for k, repo in aws_ecr_repository.this : k => repo.arn
  }
} 