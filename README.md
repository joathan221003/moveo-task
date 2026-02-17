# Yehonatan Ohana
# Moveo DevOps Home Assignment

---

## Deployed URL
http://task-alb-465263923.us-east-1.elb.amazonaws.com

### Expected Response
yo this is nginx

---

## Overview
This project provisions an AWS infrastructure using Terraform.
It deploys an internet-facing Application Load Balancer (ALB) that routes HTTP traffic to an EC2 instance located in a private subnet.
The EC2 instance runs Docker with an NGINX container serving a custom index page.

---

## Architecture
- Internet → ALB (public subnets)
- ALB → Target Group
- Target Group → EC2 (private subnet) running Docker + NGINX
- Private subnet outbound traffic via NAT Gateway
- Public subnets connected to Internet Gateway

---

## Prerequisites
- AWS Account
- Terraform installed
- AWS CLI configured (aws configure)
- Region: us-east-1

---

## Deployment Instructions

Format Terraform files:
terraform fmt -recursive

Initialize Terraform:
terraform init

Review execution plan:
terraform plan

Apply infrastructure:
terraform apply

Get ALB URL:
terraform output alb_dns_name

---

## How to Test

curl http://task-alb-465263923.us-east-1.elb.amazonaws.com

Expected output:
yo this is nginx

---

## Cleanup

terraform destroy

---

## Security Notes
- EC2 instance is deployed in a private subnet (not publicly accessible).
- Only the Application Load Balancer is internet-facing.
- Security Groups restrict traffic to necessary ports only.
- Outbound internet access for the EC2 instance is provided via NAT Gateway.

