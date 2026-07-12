variable "contact_email" {
  description = "Address that receives contact-form submissions. Must be verified in SES while the account is in the sandbox."
  type        = string
  default     = "cristian@padillacastillo.com"
}

variable "allowed_origin" {
  description = "Origin allowed to call the contact-form API (CORS). Include the localhost dev server too while testing."
  type        = list(string)
  default     = ["https://padillacastillo.com", "http://localhost:8000"]
}
