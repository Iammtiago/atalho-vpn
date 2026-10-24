# Solución de problemas

## Terraform

| Error | Solución |
|---|---|
| `no matching EC2 VPC found` / sin VPC por defecto | `aws ec2 create-default-vpc --region sa-east-1` y vuelve a `terraform apply`. |
| Error con `ec2-instance-connect` | En `terraform.tfvars`: `ssh_desde_consola = false`. |
| `InvalidKeyPair` o no encuentra la llave | Revisa `ssh_public_key_path` o crea la llave: `ssh-keygen -t ed25519`. |
| `UnauthorizedOperation` | Al usuario de IAM le falta la política del paso 1.4 de la guía. |
| `The instance type is not eligible for Free Tier` | Usa el tipo que salga en el paso 1.5 de la guía. |

## El servidor

- **No entra por SSH**: tu IP cambió. Actualiza `ssh_cidr` y `terraform apply`, o entra desde la consola de AWS → EC2 → la instancia → **Conectar** → EC2 Instance Connect.
- **`vpnctl: command not found`**: la instalación no terminó. Mira `tail -n 50 /var/log/atalho-vpn-install.log`. Para correrla de nuevo (no borra nada):

  ```bash
  sudo git clone https://github.com/Iammtiago/atalho-vpn.git /opt/atalho-vpn   # si no existe
  sudo bash /opt/atalho-vpn/server/install.sh
  ```

- **`vpnctl check` marca "IP de los clientes = IP pública"**: corrige `ENDPOINT=` en `/etc/wireguard/atalho-vpn.env` y vuelve a crear los clientes.

## Los clientes

- **Conecta pero no pasa tráfico** (en la app de WireGuard "último handshake" nunca aparece):
  - El puerto UDP del security group no coincide con `wg_port`, o la red donde estás bloquea UDP. Prueba desde datos móviles.
  - El reloj del dispositivo está muy desfasado.
- **Claude no pasa por la VPN**: comprueba que Claude siga en los rangos de Anthropic:

  ```powershell
  Resolve-DnsName claude.ai
  ```

  Debe dar `160.79.104.x` / `2607:6bc0::…`. Si cambió, actualiza `CLAUDE_IPS` en `server/install.sh`, actualiza el servidor (abajo) y vuelve a crear los clientes.
- **WireSock no tunela Claude**: el proceso debe llamarse `claude.exe`. Revisa el nombre en el Administrador de tareas y ajusta *Tunneled applications*.
- **Dos VPN a la vez**: iOS y Windows no combinan bien dos túneles; deja activo solo uno.

## Actualizar el servidor

Después de subir cambios al repo:

```bash
cd /opt/atalho-vpn && sudo git pull
sudo bash server/install.sh
```

`install.sh` es idempotente: conserva las llaves, el puerto, la IP y los clientes. `terraform apply` tampoco recrea el servidor por cambios en el repo ni por nuevas versiones de Ubuntu.
