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