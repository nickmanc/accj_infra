# accj_infra

Terraform code for deploying the www.acatcalledjack.co.uk website to AWS.

Main Components are:

* S3 Bucket for hosting content
* CloudFront Distribution for serving up over https
* Certificate for the requested domain and DNS records in Route 53
* Lambda to invalidate the CloudFront distribution when new content uploaded
* Code Pipeline to automatically update the S3 bucket when new content committed to https://github.com/nickmanc/accj_content
* SNS email & sms notifications when pipeline has run





