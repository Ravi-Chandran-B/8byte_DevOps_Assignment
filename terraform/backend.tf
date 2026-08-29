terraform {
  backend "s3" {
    bucket         = "devops-assignment-terraform-state-jksdfak"
    key            = "devops-assignment/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}