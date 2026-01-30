output "alb_dns_name" {
  value = aws_lb.internal.dns_name
}

output "web_private_ips" {
  value = [
    aws_instance.web1.private_ip,
    aws_instance.web2.private_ip
  ]
}

output "rds_endpoint" {
  value = aws_db_instance.mysql.address
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "vpc_id" {
  value = aws_vpc.this.id
}