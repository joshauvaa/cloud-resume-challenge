provider "aws" {
  region = "us-east-1"
}

###### S3 CONFIGURATION ######

## Bucket Creation ##
resource "aws_s3_bucket" "resume_files" {
  # Naming the bucket with same domain name"
  bucket = "joshauvaa-cloudresume.com"

  tags = {
    Project = "cloud-resume"
  }
}

## Website Configuration ##
resource "aws_s3_bucket_website_configuration" "resume_site" {
  bucket = aws_s3_bucket.resume_files.id

  index_document {
    suffix = "index.html"
  }

  # Not including an error document. Need to check if this goes against best practice.

}

## Enabling Public Access ##
resource "aws_s3_bucket_public_access_block" "resume_site_public_access_block" {
  bucket = aws_s3_bucket.resume_files.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

## Bucket Policy to allow public read access to the objects in the bucket ##
resource "aws_s3_bucket_policy" "resume_site_bucket_policy" {
  bucket = aws_s3_bucket.resume_files.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.resume_files.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.resume_site_public_access_block]
}

output "website_url" {
  value = aws_s3_bucket_website_configuration.resume_site.website_endpoint
}

###### CLOUDFRONT CONFIGURATION ######

resource "aws_cloudfront_distribution" "resume_cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases = [
    "joshauvaa-cloudresume.com",
    "www.joshauvaa-cloudresume.com"
  ]

  origin {
    domain_name = aws_s3_bucket_website_configuration.resume_site.website_endpoint
    origin_id   = "resume-site-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "resume-site-origin"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.resume_cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  tags = {
    Project = "cloud-resume"
  }
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.resume_cdn.domain_name
}


### DYNAMODB CONFIGURATION ###

resource "aws_dynamodb_table" "visitor_counter" {
  name         = "visitor-counter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Project = "cloud-resume"
  }
}

### LAMBDA CONFIGURATION ##

data "archive_file" "visitor_counter_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/lambda_increment_visitor_count.py"
  output_path = "${path.module}/lambda_increment_visitor_count.zip"
}

resource "aws_iam_role" "visitor_counter_lambda_role" {
  name = "visitor-counter-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = "cloud-resume"
  }
}

resource "aws_iam_role_policy_attachment" "visitor_counter_lambda_basic_execution" {
  role       = aws_iam_role.visitor_counter_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "visitor_counter_dynamodb_policy" {
  name = "visitor-counter-dynamodb-policy"
  role = aws_iam_role.visitor_counter_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowUpdateVisitorCounter"
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.visitor_counter.arn
      }
    ]
  })
}

resource "aws_lambda_function" "visitor_counter" {
  function_name = "visitor-counter"
  role          = aws_iam_role.visitor_counter_lambda_role.arn
  runtime       = "python3.12"
  handler       = "lambda_increment_visitor_count.lambda_handler"

  filename         = data.archive_file.visitor_counter_zip.output_path
  source_code_hash = data.archive_file.visitor_counter_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_counter.name
    }
  }

  tags = {
    Project = "cloud-resume"
  }
}

### API GATEWAY CONFIGURATION ###

resource "aws_apigatewayv2_api" "visitor_counter_api" {
  name          = "visitor-counter-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [
      "https://${aws_cloudfront_distribution.resume_cdn.domain_name}",
      "http://${aws_s3_bucket_website_configuration.resume_site.website_endpoint}",
      "https://joshauvaa-cloudresume.com",
      "https://www.joshauvaa-cloudresume.com"
    ]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }

  tags = {
    Project = "cloud-resume"
  }
}

resource "aws_apigatewayv2_integration" "visitor_counter_lambda" {
  api_id                 = aws_apigatewayv2_api.visitor_counter_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.visitor_counter.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_visits" {
  api_id    = aws_apigatewayv2_api.visitor_counter_api.id
  route_key = "GET /visits"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_counter_lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.visitor_counter_api.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Project = "cloud-resume"
  }
}

resource "aws_lambda_permission" "allow_api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitor_counter_api.execution_arn}/*/*"
}

output "api_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "visits_endpoint" {
  value = "${aws_apigatewayv2_stage.default.invoke_url}/visits"
}

### ROUTE 53 CONFIGURATION ###

data "aws_route53_zone" "primary" {
  name         = "joshauvaa-cloudresume.com"
  private_zone = false
}

resource "aws_route53_record" "apex_a" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "joshauvaa-cloudresume.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.resume_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.resume_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex_aaaa" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "joshauvaa-cloudresume.com"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.resume_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.resume_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_a" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "www.joshauvaa-cloudresume.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.resume_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.resume_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_aaaa" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "www.joshauvaa-cloudresume.com"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.resume_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.resume_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

### ACM CONFIGURATION ###

resource "aws_acm_certificate" "resume_cert" {
  domain_name               = "joshauvaa-cloudresume.com"
  subject_alternative_names = ["www.joshauvaa-cloudresume.com"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Project = "cloud-resume"
  }
}

resource "aws_route53_record" "resume_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.resume_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.primary.zone_id
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
}

resource "aws_acm_certificate_validation" "resume_cert" {
  certificate_arn         = aws_acm_certificate.resume_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.resume_cert_validation : record.fqdn]

  timeouts {
    create = "15m"
  }
}
