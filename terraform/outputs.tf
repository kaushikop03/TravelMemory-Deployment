output "web_public_ip" {
  value = aws_instance.web.public_ip
}

output "database_private_ip" {
  value = aws_instance.database.private_ip
}