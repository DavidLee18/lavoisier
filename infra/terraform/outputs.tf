output "alb_dns_name" {
  description = "Public DNS of the gateway ALB — curl http://<this>/health"
  value       = aws_lb.main.dns_name
}

output "ecr_repository_url" {
  description = "Build + push the image here (infra/scripts/build-and-push.zsh)."
  value       = aws_ecr_repository.app.repository_url
}

output "log_group" {
  description = "CloudWatch log group for the gateway tasks."
  value       = aws_cloudwatch_log_group.app.name
}
