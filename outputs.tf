

output "db_private_ip" {
  value = aws_instance.mongodb_instance.private_ip
}

output "dbdnsssh" {
  value = aws_instance.mongodb_instance.public_dns
}

output "db_public_ip" {
  value = aws_instance.mongodb_instance.public_ip
}

output "attacker_private_ip" {
  value = aws_instance.attacker.private_ip
}

output "attacker_dns" {
  value = aws_instance.attacker.public_dns
}

output "attacker_public_ip" {
  value = aws_instance.attacker.public_ip
}

output "lb_dns_endpoint" {
  value = kubernetes_service.tasky_svc.status[0].load_balancer[0].ingress[0].hostname
}
