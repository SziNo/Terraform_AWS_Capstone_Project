output "load_balancer_dns" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.this.dns_name
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "instance_ids" {
  description = "IDs of the application instances"
  value       = aws_instance.app[*].id
}

output "db_private_ip" {
  description = "Private IP of the database instance"
  value       = aws_instance.db.private_ip
}

output "db_password" {
  description = "Generated password for the database"
  value       = random_password.db.result
  sensitive   = true
}