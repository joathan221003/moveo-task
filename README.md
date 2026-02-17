# Yehonatan Ohana
# Moveo DevOps Home Assignment

## Deployed URL
http://task-alb-465263923.us-east-1.elb.amazonaws.com

Expected response:
yo this is nginx




---

## Overview
This project provisions an AWS environment with an internet-facing Application Load Balancer (ALB) that forwards traffic to an EC2 instance running Dockerized NGINX in a private subnet.

---

## Architecture
- Internet → **ALB (public subnets)**
- ALB → **Target Group**
- Target Group → **EC2 (private subnet)** running **Docker + NGINX**
- Private subnet egress via **NAT Gateway**
- Public subnets connected via **Internet Gateway**

### Diagram (Mermaid)
```mermaid
flowchart LR
  U[User / Browser] --> ALB[ALB - Public Subnets]
  ALB --> TG[Target Group]
  TG --> EC2[EC2 - Private Subnet]
  EC2 --> D[Docker Container: NGINX]
  EC2 --> NAT[NAT Gateway]
  NAT --> IGW[Internet Gateway]



terraform fmt -recursive
terraform init
terraform plan
terraform apply

#HOW TO TEST
curl http://task-alb-465263923.us-east-1.elb.amazonaws.com

#EXPECTED OUTPUT
yo thus is nginx

#CLEANUP
terraform destroy

Security Notes

-EC2 instance is placed in a private subnet (not directly exposed to the internet).

-Only the ALB is public-facing.

-Security Groups allow inbound HTTP to the ALB and allow ALB-to-EC2 traffic.

-Outbound internet access for the private subnet is done via NAT Gateway (for updates/pulling images if needed).




