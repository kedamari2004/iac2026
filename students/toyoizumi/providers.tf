provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      Createdby = var.executor_name
      Training  = "iac2026"
    }
  }
}