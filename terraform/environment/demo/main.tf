provider "aws" {
  region = "us-east-1"
}

# VPC
module "vpc" {
  source                = "../../modules/vpc"
  vpc_cidr              = "10.0.0.0/16"
  public_subnet_1_cidr  = "10.0.1.0/24"
  public_subnet_2_cidr  = "10.0.2.0/24"
  az_1                  = "us-east-1a"
  az_2                  = "us-east-1b"
}

# Security
module "security" {
  source   = "../../modules/security"
  vpc_id   = module.vpc.vpc_id
  my_ip    = "YOUR_PUBLIC_IP/32"  # replace with your IP for SSH
}

# EC2
module "ec2" {
  source            = "../../modules/ec2"
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.security.ec2_sg_id
}

# ALB
module "alb" {
  source            = "../../modules/alb"
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.security.alb_sg_id
  instance_ids      = module.ec2.instance_ids
}
