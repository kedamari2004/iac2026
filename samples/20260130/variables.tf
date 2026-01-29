variable "aws_region" {
  type        = string
  default     = "ap-northeast-1"
  description = "AWS region"
}

variable "executor_name" {
  type        = string
  description = "実行者名（命名・タグに使用）"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR (例: 10.10.0.0/16)"
}

variable "name_prefix" {
  type    = string
  default = "iac2026"
}

variable "instance_type_ec2" {
  type    = string
  default = "t3.micro"
}

variable "instance_type_rds" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "trivia_db"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "ssh_key_name" {
  type        = string
  default     = null
  description = "SSH KeyPair名（SSM利用時はnull可）"
}

variable "allowed_http_cidr" {
  type        = string
  default     = null
  description = "内部ALBに到達可能なCIDR（未指定時はVPC CIDR）"
}
