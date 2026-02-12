variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "ami_owner" {
  type    = string
  default = "099720109477" # Canonical Ubuntu
}
