output "alb_dns_name" {
  value = aws_lb.internal_alb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.db.endpoint
}

output "secret_arn" {
  value = aws_secretsmanager_secret.db_secret.arn
}