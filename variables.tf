variable "name" {
   type = string
   description = "name of app"
   default     = "tk-tf-s3"
}

variable "domain_name" {
  type        = string
  default     = "sctp-sandbox.com"
  description = "Hosted zone domain name"
}