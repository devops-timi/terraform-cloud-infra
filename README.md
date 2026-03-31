# Terraform Cloud Infrastructure on AWS

Infrastructure-as-Code project that provisions a production-style AWS environment using **Terraform** and **GitHub Actions**. The stack includes a custom VPC, public subnets across two availability zones, EC2 instances bootstrapped with Docker and the FocusFlow app, an Application Load Balancer for traffic distribution, and security groups with least-privilege rules. Remote state is stored in S3 with DynamoDB locking.

All infrastructure operations — bootstrap, apply, and destroy — are triggered manually via GitHub Actions `workflow_dispatch`.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Infrastructure Components](#infrastructure-components)
- [Remote State Backend](#remote-state-backend)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
  - [Step 1 — Bootstrap the Backend](#step-1--bootstrap-the-backend)
  - [Step 2 — Provision Infrastructure](#step-2--provision-infrastructure)
  - [Step 3 — Destroy Infrastructure](#step-3--destroy-infrastructure)
- [GitHub Actions Workflows](#github-actions-workflows)
- [Terraform Modules](#terraform-modules)
  - [vpc](#vpc-module)
  - [sec_grp](#sec_grp-module)
  - [ec2](#ec2-module)
  - [alb](#alb-module)
- [Module Dependency Graph](#module-dependency-graph)
- [Network Layout](#network-layout)
- [Secrets Reference](#secrets-reference)
- [Customisation](#customisation)

---

## Architecture Overview

```
                          Internet
                             │
                        (Port 80)
                             │
                    ┌────────▼────────┐
                    │  App Load       │
                    │  Balancer (ALB) │  ← alb-sg: allows 0.0.0.0/0 on port 80
                    └────────┬────────┘
                             │ (Port 5000)
               ┌─────────────┴─────────────┐
               │                           │
      ┌────────▼────────┐       ┌──────────▼──────────┐
      │  EC2: web-1     │       │  EC2: web-2          │
      │  us-east-1a     │       │  us-east-1b          │
      │  public_subnet_1│       │  public_subnet_2     │
      │  Docker →       │       │  Docker →            │
      │  focusflow:14   │       │  focusflow:14        │
      └────────┬────────┘       └──────────┬───────────┘
               └──────────┬────────────────┘
                           │
              ┌────────────▼────────────┐
              │   VPC: 10.0.0.0/16      │
              │   demo-vpc              │
              │   DNS support enabled   │
              └─────────────────────────┘

Remote State:
  S3 bucket (versioned, AES-256 encrypted, public access blocked)
  + DynamoDB table (state locking, PAY_PER_REQUEST billing)
```

---

## Project Structure

```
terraform-cloud-infra/
├── .github/
│   └── workflows/
│       ├── s3-dynamo.yml           # Workflow 1: Bootstrap S3 + DynamoDB backend
│       ├── terraform.yml           # Workflow 2: terraform init → plan → apply
│       └── terraform-destroy.yml  # Workflow 3: terraform init → destroy
└── terraform/
    ├── bootstrap/
    │   └── aws-s3-dynamodb-backend.sh   # Shell script: creates S3 bucket + DynamoDB table
    ├── environments/
    │   └── demo/
    │       ├── backend.tf          # S3 remote state configuration
    │       └── main.tf             # Root module: wires all four modules together
    └── modules/
        ├── vpc/
        │   ├── main.tf             # VPC, IGW, subnets, route table, associations
        │   ├── variables.tf        # CIDR blocks, AZs
        │   └── outputs.tf          # vpc_id, public_subnet_ids
        ├── sec_grp/
        │   ├── main.tf             # ALB SG (port 80) and EC2 SG (port 5000 from ALB, 22 open)
        │   ├── variables.tf        # vpc_id
        │   └── outputs.tf          # alb_sg_id, ec2_sg_id
        ├── ec2/
        │   ├── main.tf             # AMI data source, EC2 instances, user_data bootstrap
        │   ├── variables.tf        # subnet_ids, security_group_id, instance_type, ami_owner
        │   └── outputs.tf          # instance_ids
        └── alb/
            ├── main.tf             # ALB, target group, attachments, listener
            ├── variables.tf        # vpc_id, subnet_ids, security_group_id, instance_ids
            └── outputs.tf          # alb_dns_name
```

---

## Infrastructure Components

| Component | Details |
|-----------|---------|
| **VPC** | CIDR `10.0.0.0/16`, DNS support and hostnames enabled |
| **Subnets** | 2 public subnets: `10.0.1.0/24` (us-east-1a), `10.0.2.0/24` (us-east-1b) |
| **Internet Gateway** | Attached to the VPC; routes `0.0.0.0/0` via the public route table |
| **Route Table** | Single public route table associated with both subnets |
| **Security Group — ALB** | Inbound: port 80 from `0.0.0.0/0`; Outbound: all |
| **Security Group — EC2** | Inbound: port 5000 from ALB SG only, port 22 from `0.0.0.0/0`; Outbound: all |
| **EC2 Instances** | 2 × `t2.micro`, Ubuntu 24.04 (Noble), one per subnet; auto-assigned public IPs |
| **EC2 User Data** | Installs Docker, starts the FocusFlow container on port 5000 at launch |
| **ALB** | Application Load Balancer spanning both public subnets; listener on port 80 |
| **Target Group** | Forwards traffic to EC2 instances on port 5000 |
| **Remote State** | S3 bucket with versioning, AES-256 encryption, public access blocked |
| **State Locking** | DynamoDB table `terraform-state-lock` (PAY_PER_REQUEST) |

---

## Remote State Backend

Before running any Terraform commands, the S3 bucket and DynamoDB table must exist. The bootstrap script handles this.

`terraform/bootstrap/aws-s3-dynamodb-backend.sh` creates:

- **S3 bucket** (`timi-infra-terraform-state`) with:
  - Versioning enabled (allows state file recovery)
  - AES-256 server-side encryption
  - All public access blocked
- **DynamoDB table** (`terraform-state-lock`) with:
  - `LockID` as the hash key (string)
  - PAY_PER_REQUEST billing (no capacity planning needed)

`terraform/environments/demo/backend.tf` then references these resources:

```hcl
terraform {
  backend "s3" {
    bucket         = "timi-infra-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

---

## Prerequisites

- An **AWS account** with an IAM user that has permissions for:
  - EC2, VPC, ALB (Elastic Load Balancing)
  - S3 (create bucket, put versioning/encryption/policy)
  - DynamoDB (create table)
- A **GitHub repository** with Actions enabled
- An **EC2 key pair** named `us-connect` already created in `us-east-1` (referenced in the EC2 module — update if using a different key name)

---

## Usage

All three operations are triggered manually from **GitHub Actions → Actions tab → select workflow → Run workflow**.

### Step 1 — Bootstrap the Backend

Run the **Bootstrap Terraform Backend** workflow (`s3-dynamo.yml`) first — this only needs to be done once.

It executes `aws-s3-dynamodb-backend.sh`, which creates the S3 bucket and DynamoDB table used by the Terraform backend.

> If you want to use a different bucket name, update `BUCKET_NAME` in `terraform/bootstrap/aws-s3-dynamodb-backend.sh` and `bucket` in `terraform/environments/demo/backend.tf` to match.

### Step 2 — Provision Infrastructure

Run the **Terraform Infrastructure** workflow (`terraform.yml`).

Steps executed:
1. `terraform init` — initialises the backend and downloads providers
2. `terraform plan` — shows what will be created
3. `terraform apply -auto-approve` — provisions all resources

Once complete, the ALB DNS name is available as a Terraform output. Access the FocusFlow app at:

```
http://<alb_dns_name>
```

### Step 3 — Destroy Infrastructure

Run the **Terraform Destroy** workflow (`terraform-destroy.yml`) to tear down all provisioned resources and avoid ongoing AWS charges.

Uses `terraform init -reconfigure` followed by `terraform destroy -auto-approve`.

> The S3 bucket and DynamoDB table created in Step 1 are **not** destroyed by this workflow — they must be removed manually if no longer needed.

---

## GitHub Actions Workflows

All three workflows use `workflow_dispatch` (manual trigger only — no automatic runs on push).

| Workflow File | Name | Trigger | Working Directory | What It Does |
|---------------|------|---------|-------------------|--------------|
| `s3-dynamo.yml` | Bootstrap Terraform Backend | Manual | `terraform/bootstrap` | Runs the shell script to create S3 + DynamoDB |
| `terraform.yml` | Terraform Infrastructure | Manual | `terraform/environments/demo` | init → plan → apply |
| `terraform-destroy.yml` | Terraform Destroy | Manual | `terraform/environments/demo` | init (reconfigure) → destroy |

All workflows authenticate with AWS using the same three secrets.

---

## Terraform Modules

### `vpc` Module

**Path:** `terraform/modules/vpc`

Creates the core network layer.

| Resource | Description |
|----------|-------------|
| `aws_vpc.main` | VPC with DNS support and hostnames enabled |
| `aws_internet_gateway.igw` | Attached to the VPC for internet access |
| `aws_subnet.public_1` | Public subnet in `az_1`, auto-assigns public IPs |
| `aws_subnet.public_2` | Public subnet in `az_2`, auto-assigns public IPs |
| `aws_route_table.public_rt` | Routes `0.0.0.0/0` through the IGW |
| `aws_route_table_association.assoc_1/2` | Associates both subnets with the route table |

**Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `public_subnet_1_cidr` | `10.0.1.0/24` | First public subnet CIDR |
| `public_subnet_2_cidr` | `10.0.2.0/24` | Second public subnet CIDR |
| `az_1` | `us-east-1a` | Availability zone for subnet 1 |
| `az_2` | `us-east-1b` | Availability zone for subnet 2 |

**Outputs:** `vpc_id`, `public_subnet_ids`

---

### `sec_grp` Module

**Path:** `terraform/modules/sec_grp`

Creates two security groups with the principle of least privilege.

**ALB Security Group (`alb-sg`):**
- Inbound: TCP port 80 from `0.0.0.0/0` (public HTTP traffic)
- Outbound: all traffic allowed

**EC2 Security Group (`ec2-sg`):**
- Inbound: TCP port 5000 **from the ALB security group only** (no direct public access to the app)
- Inbound: TCP port 22 from `0.0.0.0/0` (SSH — restrict this to your IP in production)
- Outbound: all traffic allowed

**Variables:** `vpc_id`

**Outputs:** `alb_sg_id`, `ec2_sg_id`

---

### `ec2` Module

**Path:** `terraform/modules/ec2`

Provisions EC2 instances with a dynamic count matching the number of subnets provided.

**AMI:** Dynamically fetches the latest Ubuntu 24.04 (Noble) HVM AMI from Canonical (`ami_owner = "099720109477"`).

**User Data (runs at first boot):**
```bash
apt-get update -y
apt-get install -y docker.io
systemctl enable docker && systemctl start docker
usermod -aG docker ubuntu
docker pull devopstimi/focusflow-cicd:14
docker run -d -p 5000:5000 --restart unless-stopped devopstimi/focusflow-cicd:14
```

Each instance installs Docker, pulls the FocusFlow image (tag `14`), and starts the container on port 5000 with `--restart unless-stopped`.

**Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `subnet_ids` | — | List of subnet IDs (one instance created per subnet) |
| `security_group_id` | — | EC2 security group ID |
| `instance_type` | `t2.micro` | EC2 instance type |
| `ami_owner` | `099720109477` | Canonical's AWS account ID |

**Outputs:** `instance_ids`

---

### `alb` Module

**Path:** `terraform/modules/alb`

Provisions an Application Load Balancer that distributes HTTP traffic across the EC2 instances.

| Resource | Description |
|----------|-------------|
| `aws_lb.this` | Internet-facing ALB named `app-alb` spanning both public subnets |
| `aws_lb_target_group.this` | Target group `app-tg`, forwards to port 5000 over HTTP |
| `aws_lb_target_group_attachment.this` | Attaches each EC2 instance to the target group |
| `aws_lb_listener.this` | Listens on port 80, forwards to the target group |

**Variables:** `vpc_id`, `subnet_ids`, `security_group_id`, `instance_ids`

**Outputs:** `alb_dns_name`

---

## Module Dependency Graph

```
environments/demo/main.tf
        │
        ├── module.vpc
        │       └── outputs: vpc_id, public_subnet_ids
        │
        ├── module.security (depends on: vpc_id from vpc)
        │       └── outputs: alb_sg_id, ec2_sg_id
        │
        ├── module.ec2 (depends on: subnet_ids from vpc, ec2_sg_id from security)
        │       └── outputs: instance_ids
        │
        └── module.alb (depends on: vpc_id from vpc, subnet_ids from vpc,
                        alb_sg_id from security, instance_ids from ec2)
                └── outputs: alb_dns_name
```

Terraform resolves these dependencies automatically and provisions resources in the correct order.

---

## Network Layout

```
VPC: 10.0.0.0/16
│
├── public_subnet_1: 10.0.1.0/24  (us-east-1a)
│       └── EC2: web-1
│
├── public_subnet_2: 10.0.2.0/24  (us-east-1b)
│       └── EC2: web-2
│
└── Route Table → 0.0.0.0/0 → Internet Gateway
```

---

## Secrets Reference

Configure these in **GitHub → Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key ID |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret access key |
| `AWS_REGION` | Target AWS region (e.g., `us-east-1`) |

---

## Customisation

| What to change | Where |
|----------------|-------|
| AWS region | `aws-s3-dynamodb-backend.sh`, `backend.tf`, `main.tf` provider block |
| S3 bucket name | `aws-s3-dynamodb-backend.sh` (`BUCKET_NAME`) and `backend.tf` (`bucket`) |
| VPC / subnet CIDRs | `environments/demo/main.tf` module inputs |
| Availability zones | `environments/demo/main.tf` (`az_1`, `az_2`) |
| EC2 instance type | `modules/ec2/variables.tf` (`instance_type` default) or via `main.tf` |
| SSH key pair name | `modules/ec2/main.tf` (`key_name = "us-connect"`) |
| Docker image / tag | `modules/ec2/main.tf` user data script |
| App port | `modules/ec2/main.tf` (Docker `-p`), `modules/sec_grp/main.tf`, `modules/alb/main.tf` |