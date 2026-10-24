# Guía de montaje

Del cero a la VPN funcionando en el iPhone y la laptop. Unos 40 minutos.

**Resumen:** 1) preparar la laptop y AWS → 2) crear el servidor con Terraform → 3) comprobarlo → 4) crear clientes → 5) iPhone → 6) Windows → 7) otros usuarios.

## Qué va por la VPN

| Dispositivo | App | Config | Qué va por Brasil |
|---|---|---|---|
| **Laptop Windows** (recomendado) | **WireSock Secure Connect** (gratis uso personal) | `atalho-vpn-app.conf` | Solo los procesos `claude.exe` (Claude de escritorio y Claude Code). Por app, de verdad. |
| Laptop Windows (alternativa) | WireGuard oficial | `atalho-vpn-claude.conf` | Todo lo que vaya a Anthropic (también claude.ai en el navegador). |
| **iPhone** | WireGuard oficial | `atalho-vpn-claude.conf` (QR) | Todo lo que vaya a Anthropic → en la práctica solo la app de Claude. |

**Por qué el iPhone va por destino y no por app:** iOS solo permite VPN por app en iPhones de empresa (MDM). Claude usa solo los rangos de Anthropic `160.79.104.0/23` y `2607:6bc0::/48` (claude.ai, claude.com, api.anthropic.com y claudeusercontent.com), así que la VPN solo lleva ese tráfico.

Cada cliente tiene 3 configs con la misma llave: activa **solo una** a la vez.

---

## 0. (Opcional) Probar en tu PC

Con Docker Desktop abierto, en la carpeta del repo:

```powershell
.\test\probar-local.ps1
```

Debe terminar en `TODO OK`. Si PowerShell lo bloquea: `powershell -ExecutionPolicy Bypass -File .\test\probar-local.ps1`.

## 1. Preparar la laptop (una sola vez)

**1.1 Cuenta de AWS.** Si no tienes, créala en https://aws.amazon.com y elige **"Free plan"**. Pide tarjeta, pero el Free plan no cobra. Activa MFA en el usuario raíz (consola → arriba a la derecha → Credenciales de seguridad).

**1.2 Instalar Terraform y AWS CLI** (PowerShell; luego cierra y abre la terminal):

```powershell
winget install Hashicorp.Terraform Amazon.AWSCLI
```

Verifica con `terraform -version` y `aws --version`.

**1.3 Llave SSH** (si no tienes `~\.ssh\id_ed25519.pub`):

```powershell
ssh-keygen -t ed25519 -C "atalho-vpn"
```

**1.4 Usuario de AWS para Terraform.** Consola → IAM → Usuarios → Crear usuario `atalho-vpn-terraform` (sin acceso a la consola) → Permisos → Crear política en línea → JSON:

```json
{ "Version": "2012-10-17", "Statement": [{ "Effect": "Allow", "Action": ["ec2:*", "budgets:*"], "Resource": "*" }] }
```

En el usuario → Credenciales de seguridad → Crear clave de acceso → "Interfaz de línea de comandos (CLI)". Configúrala tú (no la pegues en ningún chat ni archivo del repo):

```powershell
aws configure
```

Región: `sa-east-1`. Formato: `json`. Comprueba con `aws sts get-caller-identity`.

**1.5 Ver qué instancia es gratis en tu cuenta:**

```powershell
aws ec2 describe-instance-types --region sa-east-1 --filters Name=free-tier-eligible,Values=true --query "InstanceTypes[].InstanceType" --output text
```

Usa `t3.micro` si aparece; si no, la que salga.

## 2. Crear el servidor

En la carpeta del repo:

```powershell
cd infra
copy terraform.tfvars.example terraform.tfvars
curl.exe https://checkip.amazonaws.com
```

Edita `terraform.tfvars`:

- `ssh_cidr = "TU.IP/32"` (la IP que salió arriba)
- `instance_type` (paso 1.5)
- `email_alertas` (tu correo, para la alerta de gasto)

```powershell
terraform init
terraform plan
terraform apply
```

Escribe `yes`. Al final verás `ip_publica`, `ssh` e `instancia`. Espera **3 minutos** a que el servidor clone el repo y se instale. AWS te enviará un correo para confirmar la alerta de gasto: confírmalo.

## 3. Comprobar el servidor

```powershell
ssh ubuntu@IP_PUBLICA
```

```bash
sudo vpnctl check
```

Todo debe salir `OK`. Si algo falla: `tail -n 30 /var/log/atalho-vpn-install.log` y [problemas.md](problemas.md).

## 4. Crear los clientes

Un dispositivo = un cliente:

```bash
sudo vpnctl add tiago-iphone
sudo vpnctl add tiago-laptop
```

Para que más apps de Windows vayan por la VPN: `sudo vpnctl add tiago-laptop "claude, chrome"`.

## 5. iPhone

1. App Store → **WireGuard** (de WireGuard Development Team), gratis.
2. En el servidor: `sudo vpnctl qr tiago-iphone` (agranda la terminal si el QR sale cortado).
3. iPhone: WireGuard → **+** → **Crear desde código QR** → nombre `Atalho` → **Permitir**.
4. Activa el túnel y abre Claude.

**Activar/desactivar:** interruptor en la app de WireGuard o en **Ajustes → VPN**. Como solo lleva el tráfico de Claude, puede quedar siempre prendida; para que se encienda sola: WireGuard → Atalho → Editar → "Activar bajo demanda" (Wi-Fi y datos móviles).

**Prueba:**

- Usa Claude y en el servidor corre `sudo vpnctl list`: `tiago-iphone` debe tener conexión reciente y el tráfico subiendo.
- En Safari abre `ifconfig.me`: debe mostrar **tu IP de siempre** (lo demás no pasa por Brasil).

## 6. Laptop Windows

**6.1 Bajar las configs.** En el servidor:

```bash
sudo vpnctl export tiago-laptop
exit
```

En la laptop (PowerShell):

```powershell
scp -r ubuntu@IP_PUBLICA:/home/ubuntu/vpn-clientes/tiago-laptop $env:USERPROFILE\vpn-clientes
ssh ubuntu@IP_PUBLICA "rm -r /home/ubuntu/vpn-clientes/tiago-laptop"
```

Quedan en `%USERPROFILE%\vpn-clientes\tiago-laptop\`, fuera de OneDrive y del repo a propósito: tienen la llave privada.

**6.2 Por app (recomendado): WireSock Secure Connect.** Descárgalo de https://wiresock.net → instala → importa `atalho-vpn-app.conf`. En el túnel verás *Tunneled applications: claude*; desde la interfaz puedes agregar o quitar apps. **Activar/desactivar:** botón Connect/Disconnect o el ícono en la bandeja (junto al reloj).

**6.3 Alternativa: WireGuard oficial** (https://www.wireguard.com/install/) → Importar túnel desde archivo → `atalho-vpn-claude.conf` → Activar/Desactivar. La config `-app` no funciona aquí (`AllowedApps` es solo de WireSock).

No tengas los dos clientes conectados a la vez.

**Prueba:** con la VPN activa, `curl.exe https://checkip.amazonaws.com` debe dar **tu IP normal**; usa Claude y `sudo vpnctl list` muestra el tráfico de `tiago-laptop` subiendo.

## 7. Otros usuarios

```bash
sudo vpnctl add maria-iphone        # crear
sudo vpnctl qr maria-iphone         # que escanee el QR (en persona o por un canal privado)
sudo vpnctl qr maria-iphone todo    # o: VPN completa para esa persona
sudo vpnctl list                    # quién está conectado
sudo vpnctl remove maria-iphone     # quitarle el acceso
```

## 8. Apagar todo

```powershell
cd infra
terraform destroy
```

Borra el servidor, la IP y el firewall: deja de consumir free tier y créditos.
