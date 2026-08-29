output "instance_id" {
  description = "Use this with: aws ssm start-session --target <instance_id>"
  value       = aws_instance.bastion.id
}

output "public_ip" {
  description = "SSH: ssh -i <your-key>.pem ec2-user@<this-ip>"
  value       = aws_instance.bastion.public_ip
}

output "bastion_role_arn" {
  value = aws_iam_role.bastion.arn
}

output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}