/*output "website_url" {
  value       = "http://${aws_route53_record.www.name}.${data.aws_route53_zone.sctp_zone.name}"
  description = "Public URL for the hosted static website"
}
*/

output "website_url" {
  value       = "https://${aws_route53_record.www.name}.${data.aws_route53_zone.sctp_zone.name}"
  description = "Public HTTPS URL for the CloudFront hosted website"
}