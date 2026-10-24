# Guía de montaje en Oracle Cloud (gratis permanente)

Oracle Cloud tiene un plan **Always Free** que no vence y una región en **São Paulo**. Aquí el servidor se crea a mano en la consola (sin Terraform) y se instala clonando este repo. Unos 30 minutos.

**Resumen:** 1) cuenta → 2) llave SSH → 3) crear el servidor → 4) abrir el puerto → 5) instalar → 6) clientes (igual que en la [guía general](guia-montaje.md#4-crear-los-clientes)).

## 1. Crear la cuenta

1. Entra a https://www.oracle.com/cloud/free/ → **Start for free**.
2. **Home Region: `Brazil East (Sao Paulo)`**. **No se puede cambiar después**, y los recursos gratis solo se crean en la región de origen.
3. Pide tarjeta para verificar identidad: hace un cargo temporal que luego devuelve. Las tarjetas prepagadas o virtuales suelen rechazarse.
4. Quédate en la cuenta **Free Tier** (no hace falta pasar a "Pay As You Go").

## 2. Llave SSH (en la laptop)

Si no tienes `~\.ssh\id_ed25519.pub`:

```powershell
ssh-keygen -t ed25519 -C "atalho-vpn"
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub
```

Copia la línea que empieza con `ssh-ed25519`: es la llave **pública** (la privada nunca sale de tu laptop).

## 3. Crear el servidor

Consola → menú ☰ → **Compute → Instances → Create instance**:

| Campo | Valor |
|---|---|
| Name | `atalho-vpn` |
| Image | **Canonical Ubuntu 24.04** (botón *Change image*) |
| Shape | **Ampere → `VM.Standard.A1.Flex`**, 1 OCPU y 6 GB (sale *Always Free-eligible*). Si no hay capacidad: **AMD → `VM.Standard.E2.1.Micro`**. |
| Networking | *Create new virtual cloud network* + *Create new public subnet* · **Assign a public IPv4 address: Sí** |
| Add SSH keys | *Paste public keys* → pega la línea del paso 2 |
| Boot volume | Por defecto (gratis hasta 200 GB en total) |

**Create**. En 1–2 minutos queda en *Running*; copia la **Public IP address**.

> **"Out of capacity"** con Ampere: prueba otro *Availability domain* / *Fault domain*, inténtalo más tarde o usa `VM.Standard.E2.1.Micro` (alcanza para unos pocos usuarios).

## 4. Abrir el puerto de WireGuard

En la instancia → **Primary VNIC → Subnet** → **Security Lists** → *Default Security List* → **Add Ingress Rules**:

| Campo | Valor |
|---|---|
| Source CIDR | `0.0.0.0/0` |
| IP Protocol | **UDP** |
| Destination Port Range | `51820` |
| Description | `WireGuard` |

El SSH (TCP 22) ya viene abierto. El firewall interno de Ubuntu lo abre `install.sh` solo.

## 5. Instalar Atalho VPN

```powershell
ssh ubuntu@IP_PUBLICA
```

```bash
sudo git clone https://github.com/Iammtiago/atalho-vpn.git /opt/atalho-vpn
sudo ENDPOINT=IP_PUBLICA bash /opt/atalho-vpn/server/install.sh
sudo vpnctl check
```

Todo debe salir `OK`.

## 6. Clientes, iPhone y Windows

Sigue la guía general desde el **[paso 4](guia-montaje.md#4-crear-los-clientes)**: es igual (`vpnctl add`, QR para el iPhone, `export` + WireSock para la laptop).

## Tener en cuenta en Oracle

- **La IP pública** se mantiene mientras no borres la instancia (aunque la detengas). Si la pierdes, cambia `ENDPOINT=` en `/etc/wireguard/atalho-vpn.env` y vuelve a crear los clientes.
- **Instancias inactivas**: Oracle puede reclamar servidores Always Free que pasan 7 días casi sin uso de CPU, red y memoria (sobre todo Ampere). Te avisa por correo antes. Si pasa, recréalo con esta guía; pasar la cuenta a *Pay As You Go* evita esa regla, pero ahí sí podrías pagar si creas algo que no sea gratis.
- **Respaldo de clientes**: `sudo tar czf ~/atalho-respaldo.tgz -C /etc wireguard` y bájalo con `scp`. Así no tienes que repartir QR nuevos si recreas el servidor.
- **Actualizar**: `cd /opt/atalho-vpn && sudo git pull && sudo bash server/install.sh`.
