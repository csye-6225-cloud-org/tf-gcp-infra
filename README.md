# tf-gcp-infra
Infrastructure as Code using terraform to set up cloud resources on GCP

## APIs enabled on GCP
1. Compute Engine API
2. OS Login API
3. Service Networking API
4. Cloud Logging API
5. Stackdriver Monitoring API

## Instructions for setting up infra using terraform
1. Install terraform 
2. Install gcloud
3. Run "gcloud auth application-default login" to generate credentials
4. Copy contents of the json file to a new gcp-creds.json file
5. Run terraform init
6. Run terraform validate
7. Run terraform apply
