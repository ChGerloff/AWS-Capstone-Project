output "vpc_id" {
  value = aws_vpc.dev_vpc.id
}

output "public_subnet_a_id" {
  value = aws_subnet.public_a.id
}

output "public_subnet_b_id" {
  value = aws_subnet.public_b.id
}

output "private_subnet_a_id" {
  value = aws_subnet.private_a.id
}

output "private_subnet_b_id" {
  value = aws_subnet.private_b.id
}

output "web_server_public_ip" {
  value = aws_instance.web_server.public_ip
}

output "web_server_public_dns" {
  value = aws_instance.web_server.public_dns
}
