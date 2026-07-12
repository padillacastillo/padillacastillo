# Google Workspace mail records, replicated from Squarespace's current DNS.
# Once Squarespace's nameservers point at the zone in hosting.tf, Route 53
# becomes authoritative for *all* DNS on the domain, not just the web
# records - without these, the nameserver cutover would take email down
# along with it.

resource "aws_route53_record" "mx" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "padillacastillo.com"
  type    = "MX"
  ttl     = 14400

  records = [
    "1 aspmx.l.google.com.",
    "5 alt1.aspmx.l.google.com.",
    "5 alt2.aspmx.l.google.com.",
    "10 alt3.aspmx.l.google.com.",
    "10 alt4.aspmx.l.google.com.",
  ]
}

# Google's domain-ownership verification, plus SPF - both lived as separate
# TXT records at the apex in Squarespace, but DNS allows (and Route 53
# requires, via the same resource) multiple TXT values under one name.
resource "aws_route53_record" "txt_root" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "padillacastillo.com"
  type    = "TXT"
  ttl     = 3600

  records = [
    "google-site-verification=IEqakYzuDNOFnOXWjF8MF5nAJ6F8nE60P4ZF_Iv-KWA",
    "v=spf1 include:_spf.google.com ~all",
  ]
}

resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "_dmarc.padillacastillo.com"
  type    = "TXT"
  ttl     = 14400
  records = ["v=DMARC1; p=none;"]
}

locals {
  # DNS TXT records are limited to 255 bytes per quoted segment, and this
  # 1024-bit RSA key's base64 well exceeds that - so it has to be split into
  # multiple quoted chunks that DNS clients concatenate back together. Doing
  # the split with substr()/range() here instead of by hand avoids
  # hand-transcribing a cryptographic key, where one mistyped character
  # would silently break DKIM signing.
  google_dkim_value  = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsrKp149W0Ra+yHsRfxzJhc/sxfJT9kUivW4flQqfrHHZ1/B3T2XfwXgqQfiscPZZm1zQ31nAbky8brnemD7rR7lZ/92DRJlqNVV85hUm1UzowWG84Uw0TloC8qzXcdLxbgoOJs6PKyOcYuqBNWjeai06lUhDsYQ+EyRvrLht11RCY1rcx/hhNptUeIgLEkk6xCjfq+cD2cAv3Phx43V0T+dYhp40Tj4+UORvyzDYjn2YmvAcPjFw6dog7QuaMFjdUWHAYNldCXYSs7y0ANnLwrMHmVd0aGRR7UhJD16JGapLYIfOLocVbfOlzu0wqyvMCwgIHNj6+ORRpMwDjr5OtwIDAQAB"
  google_dkim_chunks = [for i in range(0, ceil(length(local.google_dkim_value) / 255)) : substr(local.google_dkim_value, i * 255, 255)]
}

resource "aws_route53_record" "google_dkim" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "google._domainkey.padillacastillo.com"
  type    = "TXT"
  ttl     = 14400
  # Terraform already wraps the whole list element in the outer quotes a TXT
  # record needs - inserting `" "` only between chunks (not around each one)
  # is what actually produces "chunk1" "chunk2" once Terraform adds its own.
  records = [join("\" \"", local.google_dkim_chunks)]
}
