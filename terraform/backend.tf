# State currently lives only on whoever's laptop runs `terraform apply` -
# GitHub Actions needs to read/write the same state, so it has to move
# somewhere both sides can reach. This bucket is that destination.
#
# Bootstrap (one-time, from your machine, since CI has no credentials yet):
#   1. terraform apply                     # creates this bucket via local state
#   2. uncomment the `backend "s3"` block in versions.tf
#   3. terraform init -migrate-state       # copies local state into the bucket
#
# After that, both you and CI read/write state through this bucket instead
# of a local file.

resource "aws_s3_bucket" "tfstate" {
  bucket = "padillacastillo-tfstate"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
