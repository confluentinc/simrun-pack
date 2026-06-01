provider "aws" {
  skip_region_validation      = true
  skip_credentials_validation = true
}

variable "resource_prefix" {
  type = string
}

resource "random_string" "random" {
  length    = 6
  min_lower = 6
}

resource "aws_s3_bucket" "this" {
  bucket = "${var.resource_prefix}-s3-list-objects-${random_string.random.result}"
}

output "bucket_name" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_region" {
  description = "The AWS region the S3 bucket resides in"
  value       = aws_s3_bucket.this.region
}

output "display" {
  value = format("S3 bucket %s is ready for list objects simulation", aws_s3_bucket.this.id)
}
