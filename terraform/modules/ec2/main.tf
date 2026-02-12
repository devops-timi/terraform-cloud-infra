# Latest Ubuntu 20.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 instances
resource "aws_instance" "web" {
  count                   = length(var.subnet_ids)
  ami                     = data.aws_ami.ubuntu.id
  key_name                = "us-connect"
  instance_type           = var.instance_type
  subnet_id               = var.subnet_ids[count.index]
  vpc_security_group_ids  = [var.security_group_id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              sudo systemctl enable docker
              sudo systemctl start docker
              sudo usermod -aG docker ubuntu
              docker pull devopstimi/focusflow-cicd:14
              docker run -d -p 5000:5000 --restart unless-stopped devopstimi/focusflow-cicd:14
              EOF

  tags = {
    Name = "web-${count.index + 1}"
  }
}


