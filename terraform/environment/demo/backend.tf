terraform {
  backend "s3" {
    bucket         = "timi-infra-terraform-state"   # my S3 bucket
    key            = "terraform.tfstate"       # path inside the bucket
    region         = "us-east-1"              # same as your bucket
    dynamodb_table = "terraform-state-lock"   # table for state locking
    encrypt        = true                      # enable server-side encryption
  }
}
