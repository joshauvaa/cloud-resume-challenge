provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "resume-files" {
  bucket = "joshauvaa-cloudresume.com"

  tags = {
    Project   = "cloud-resume"
  }
}

resource "aws_s3_bucket_website_configuration" "resume-site" {
  bucket = aws_s3_bucket.resume-files.id

  index_document {
    suffix = "index.html"
  }

  # Not including an error document. Need to check if this goes against best practice.

}

resource "aws_s3_bucket_public_access_block" "resume-site-public-access-block" {
  bucket = aws_s3_bucket.resume-files

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "resume-site-bucket-policy" {
  bucket = aws_s3_bucket.resume-files.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.resume-files.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.resume_site]
}

output "website_url" {
  value = aws_s3_bucket_website_configuration.resume_site.website_endpoint
}
