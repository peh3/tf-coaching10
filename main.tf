resource "aws_s3_bucket" "static_bucket" {
 bucket = "${var.name}.{var.domain_name}"
 force_destroy = true
}


resource "aws_s3_bucket_public_access_block" "enable_public_access" {

  bucket = aws_s3_bucket.static_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
  
}

/*
data "aws_iam_policy_document" "allow_public_access" {
  statement {
    sid    = "PublicReadGetObject"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    effect = "Allow"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.static_bucket.arn}/*"
    ]
  }
}
*/

data "aws_iam_policy_document" "s3_policy_doc" {
  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static_bucket.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}

/*resource "aws_s3_bucket_policy" "allow_public_access" {
    bucket = aws_s3_bucket.static_bucket.id
    policy = data.aws_iam_policy_document.allow_public_access.json

    # Explicit dependency to ensure public access block is disabled first
    depends_on = [aws_s3_bucket_public_access_block.enable_public_access]
}*/

resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.static_bucket.id
  policy = data.aws_iam_policy_document.s3_policy_doc.json
}

resource "aws_s3_bucket_website_configuration" "website" {
    bucket = aws_s3_bucket.static_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
/*
  routing_rule {
    condition {
      key_prefix_equals = "docs/"
    }
    redirect {
      replace_key_prefix_with = "documents/"
    }
  }
  */
}


data "aws_route53_zone" "sctp_zone" {
 name = "${var.domain_name}"
}


/*resource "aws_route53_record" "www" {
 zone_id = data.aws_route53_zone.sctp_zone.zone_id
 name = "${var.name}" # Bucket prefix before sctp-sandbox.com
 type = "A"


 alias {
   name = aws_s3_bucket_website_configuration.website.website_domain
   zone_id = aws_s3_bucket.static_bucket.hosted_zone_id
   evaluate_target_health = true
 }
}*/

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.sctp_zone.zone_id
  name    = var.name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.name}-oac"
  description                       = "OAC for S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  providers = {
    aws = aws.us_east_1
  }

  domain_name = local.domain_name
  zone_id     = data.aws_route53_zone.sctp_zone.zone_id

  validation_method   = "DNS"
  wait_for_validation = true
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  web_acl_id          = aws_wafv2_web_acl.waf.arn

  origin {
    domain_name              = aws_s3_bucket.static_bucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.static_bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.static_bucket.id}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/error.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = module.acm.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_wafv2_web_acl" "waf" {
  provider    = aws.us_east_1
  name        = "${var.name}-cf-waf"
  description = "WAF for CloudFront"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }
}