output "ip_publica" {
  description = "IP fija del servidor VPN"
  value       = aws_eip.vpn.public_ip
}

output "ssh" {
  description = "Comando para entrar al servidor"
  value       = "ssh ubuntu@${aws_eip.vpn.public_ip}"
}

output "instancia" {
  description = "Tipo, zona e imagen usados"
  value       = "${aws_instance.vpn.instance_type} en ${aws_instance.vpn.availability_zone} (${data.aws_ami.ubuntu.name})"
}
