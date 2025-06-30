# terraform code of create s3 bucket, clone github repo and upload code to s3

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "project_bucket" {
  bucket = "selmi-bucket-123456" 
  force_destroy = true

  tags = {
    Name        = "ProjectCodeBucket"
    Environment = "Dev"
  }
}

# Clone GitHub repo locally and upload to S3 using AWS CLI
resource "null_resource" "fetch_and_upload_code" {
  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/my-project
      git clone https://github.com/asnashameel/Three-tier-Application-Deployment-.git /tmp/my-project
      aws s3 cp /tmp/my-project s3://${aws_s3_bucket.project_bucket.bucket}/ --recursive
    EOT
  }

  depends_on = [aws_s3_bucket.project_bucket]
}
