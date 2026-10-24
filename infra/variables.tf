variable "name" {
  description = "Nombre del servidor y prefijo de los recursos"
  type        = string
  default     = "atalho-vpn"
}

variable "region" {
  description = "Región de AWS (sa-east-1 = São Paulo)"
  type        = string
  default     = "sa-east-1"
}

variable "repo_url" {
  description = "Repositorio que el servidor clona para instalarse"
  type        = string
  default     = "https://github.com/Iammtiago/atalho-vpn.git"
}

variable "repo_branch" {
  description = "Rama del repositorio"
  type        = string
  default     = "main"
}

variable "instance_type" {
  description = "Tipo de instancia: el que tu cuenta marque como free tier (paso 1.4 de la guía)"
  type        = string
  default     = "t3.micro"
}

variable "wg_port" {
  description = "Puerto UDP de WireGuard"
  type        = number
  default     = 51820
}

variable "ssh_public_key_path" {
  description = "Llave pública SSH de la laptop"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_cidr" {
  description = "IP pública desde la que entras por SSH, en formato x.x.x.x/32"
  type        = string
}

variable "ssh_desde_consola" {
  description = "Permitir SSH desde el navegador (EC2 Instance Connect)"
  type        = bool
  default     = true
}

variable "email_alertas" {
  description = "Correo para la alerta de gasto (vacío = sin alerta)"
  type        = string
  default     = ""
}
