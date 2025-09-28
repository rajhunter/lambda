# lambda
# terraform

# 🌍 Terraform Project

This repository contains Terraform configurations for provisioning infrastructure.

---

## 📦 Prerequisites

- **Terraform** (v1.x or later)
- **AWS CLI** installed and configured with valid credentials
- A GitHub account + SSH setup (if cloning/pushing code)

---

## 🚀 Install Terraform on macOS

### Option 1: Install via Homebrew (Recommended)
```bash
brew update
brew install terraform
terraform -version

### Option terraform init 

# Initialize Terraform working directory
terraform init

# Validate configuration
terraform validate

# Apply changes automatically (no confirmation)

 terraform apply \                                            
  -var "project_name=customer-management-dev" \        
  -var "lambda_zip_path=/Users/raj/Documents/dev-2025/challange/customer-management/target/customer-management-0.0.1-SNAPSHOT.zip" \
  -var "region=us-east-1" \
  -var "stage_name=dev" 
# Apply changes automatically (no confirmation)
Yes     # to aprrove  


#Apply complete! Resources: 18 added, 0 changed, 0 destroyed.
# Outputs: Exaple 

artifact_bucket = "customer-management-dev-lambda-artifacts-698031349227"
invoke_url = "https://5c7wc8ecw6.execute-api.us-east-1.amazonaws.com/dev"
lambda_alias_arn = "arn:aws:lambda:us-east-1:698031349227:function:customer-management-dev-api:live"
rest_api_id = "5c7wc8ecw6"
stage_name = "dev"
#postman request 
https://5c7wc8ecw6.execute-api.us-east-1.amazonaws.com/dev/api/v1/customers
#postman json

{
"customerName":"abh",
"emailId":"abc@abc.com",
"annualSpend":100.00
}

# Clean up state and lock files (if needed)
rm -rf .terraform/ .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup

# OR destroy the infrastructure
terraform destroy -auto-approve