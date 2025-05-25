output "dbdnsssh" {
  value = aws_instance.mongodb_instance.public_dns
}

output "db_private_ip" {
  value = aws_instance.mongodb_instance.private_ip
}

#output "lb_dns_endpoint" {
#  value = kubernetes_service.tasky_svc.status[0].load_balancer[0].ingress[0].hostname
#}
