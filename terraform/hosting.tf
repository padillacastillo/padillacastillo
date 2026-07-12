# Static hosting: Route 53 -> CloudFront -> private S3.
# The domain is registered at Squarespace, not Route 53, so this creates the
# hosted zone from scratch - after apply, the zone's name servers need to be
# copied into Squarespace's DNS settings so Route 53 becomes authoritative.

resource "aws_route53_zone" "primary" {
  name = "padillacastillo.com"
}

# ACM requires the cert for a CloudFront distribution to live in us-east-1,
# regardless of where everything else runs - the provider in versions.tf is
# already pinned to us-east-1, so no separate provider alias is needed here.
resource "aws_acm_certificate" "site" {
  domain_name       = "padillacastillo.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.site.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.primary.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "site" {
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_s3_bucket" "site" {
  bucket = "padillacastillo-site"
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lets CloudFront read from the private bucket without the bucket itself
# ever being public - see README for why this is preferred over S3 static
# website hosting.
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "padillacastillo-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "url_rewrite" {
  name    = "padillacastillo-url-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrites directory-style requests (e.g. /resume) to their index.html before hitting the S3 origin."
  publish = true
  code    = file("${path.module}/functions/url_rewrite.js")
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["padillacastillo.com"]
  price_class         = "PriceClass_100" # cheapest tier (North America + Europe) - plenty for a personal resume site

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods          = ["GET", "HEAD"]
    target_origin_id       = "s3-site"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.url_rewrite.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

data "aws_iam_policy_document" "site" {
  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site.json
}

resource "aws_route53_record" "apex_a" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "padillacastillo.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex_aaaa" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "padillacastillo.com"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

output "route53_nameservers" {
  description = "Copy these into Squarespace's custom-nameserver settings for padillacastillo.com so Route 53 becomes authoritative for DNS."
  value       = aws_route53_zone.primary.name_servers
}

output "cloudfront_domain_name" {
  description = "CloudFront's own domain (*.cloudfront.net) - useful for testing over HTTPS before the Squarespace nameserver cutover finishes propagating."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_bucket_name" {
  description = "Bucket to sync site/ into, e.g.: aws s3 sync site/ s3://<this>/"
  value       = aws_s3_bucket.site.bucket
}
