# Atalho VPN

**VPN propia con WireGuard en AWS São Paulo, con split tunneling por app.** Eliges qué va por la VPN (por ejemplo, solo la app de Claude) y todo lo demás sigue saliendo por tu internet normal. Funciona en Windows y iPhone, cada dispositivo tiene su propia llave y le das o quitas acceso a quien quieras con un comando.

> *Atalho* significa "atajo" en portugués.

```
  Laptop (WireSock)                                     ┌──────────────────────────────┐
  claude.exe ───────────────┐                           │  AWS EC2 · São Paulo         │
  resto de apps → internet  │   túnel WireGuard (UDP)   │  Ubuntu 24.04 + WireGuard    │      Claude /
                            ├──────────────────────────►│  NAT + firewall              ├────► Anthropic
  iPhone (WireGuard)        │                           │  vpnctl (clientes)           │
  tráfico a Anthropic ──────┘                           └──────────────────────────────┘
  resto de apps → internet
```

## Características

- **Split tunneling** de tres formas por cliente:
  - `atalho-vpn-app.conf`: **por app** en Windows (con [WireSock Secure Connect](https://wiresock.net)). Por defecto solo `claude.exe`.
  - `atalho-vpn-claude.conf`: **por destino**, solo lo que va a Anthropic (`160.79.104.0/23`, `2607:6bc0::/48`). Sirve en iPhone y en cualquier PC con la app oficial de WireGuard.
  - `atalho-vpn-todo.conf`: VPN completa.
- **Multiusuario**: `vpnctl add / list / qr / export / remove`. Los clientes no se ven entre sí.
- **iPhone sin configuración manual**: se escanea un QR.
- **Free tier de AWS**: EC2 micro, CPU en modo `standard` (sin cobros extra) y alerta por correo si aparece un cobro real.
- **Infraestructura como código** (Terraform) y **prueba local con Docker**, sin AWS.
- **Seguro por defecto**: llaves por dispositivo + preshared key, SSH solo desde tu IP, sin acceso a la metadata de AWS, parches automáticos.

## Inicio rápido

Requisitos: cuenta de AWS, [Terraform](https://developer.hashicorp.com/terraform/install), [AWS CLI](https://aws.amazon.com/cli/) configurada (`aws configure`) y una llave SSH.

```powershell
git clone https://github.com/Iammtiago/atalho-vpn.git
cd atalho-vpn\infra
copy terraform.tfvars.example terraform.tfvars   # pon tu IP en ssh_cidr
terraform init
terraform apply
```

Al primer arranque el servidor clona este repo en `/opt/atalho-vpn` y corre `server/install.sh`. Luego:

```bash
ssh ubuntu@IP_PUBLICA
sudo vpnctl check              # todo OK
sudo vpnctl add mi-iphone      # crear un cliente
sudo vpnctl qr mi-iphone       # escanear con la app WireGuard del iPhone
```

La guía completa, paso a paso y con pruebas, está en **[docs/guia-montaje.md](docs/guia-montaje.md)**.

### Sin Terraform (Oracle Cloud u otro VPS)

En cualquier Ubuntu 24.04 con el puerto UDP 51820 abierto (en Oracle Cloud Always Free, ver [docs/guia-oracle.md](docs/guia-oracle.md)):

```bash
git clone https://github.com/Iammtiago/atalho-vpn.git /opt/atalho-vpn
sudo ENDPOINT=<ip-publica> bash /opt/atalho-vpn/server/install.sh
```

## Documentación

| Documento | Contenido |
|---|---|
| [docs/guia-oracle.md](docs/guia-oracle.md) | Montaje en **Oracle Cloud Always Free** (São Paulo, gratis permanente) |
| [docs/guia-montaje.md](docs/guia-montaje.md) | Montaje completo: AWS, servidor, iPhone, Windows, otros usuarios |
| [docs/vpnctl.md](docs/vpnctl.md) | Referencia del comando `vpnctl` |
| [docs/problemas.md](docs/problemas.md) | Solución de problemas y actualizaciones |

## Estructura

```
server/install.sh     instala WireGuard, NAT/firewall (atalho-vpn-fw) y vpnctl; idempotente
infra/                Terraform: EC2, IP fija, security group, alerta de gasto
test/                 prueba local en Docker (servidor + cliente)
docs/                 guías
```

## Prueba local

Con Docker Desktop abierto (PowerShell):

```powershell
.\test\probar-local.ps1
```

Levanta un servidor y un cliente en contenedores Ubuntu 24.04, crea clientes, conecta el túnel y comprueba que solo el tráfico de Claude pasa por él. Debe terminar en `TODO OK`.

## Costos

Diseñado para el free tier de AWS:

- **Cuentas nuevas (desde el 15-jul-2025, "Free plan")**: el servidor consume unos US$15/mes de los créditos de bienvenida (US$100 + hasta US$100), por unos 6 meses. El Free plan no cobra: al acabarse, la cuenta se pausa.
- **Cuentas anteriores**: 12 meses de t2.micro/t3.micro + IPv4 pública gratis.
- Después: unos US$15/mes en São Paulo, o `terraform destroy`.

## Seguridad

- Nunca subas archivos `.conf` de clientes, `terraform.tfvars` ni el estado de Terraform (ya están en `.gitignore`).
- Cada `.conf`/QR es la llave de un dispositivo: si se filtra, `sudo vpnctl remove NOMBRE`.
- El tráfico de quien uses la VPN sale con la IP del servidor: da acceso solo a gente de confianza.

## Licencia

[MIT](LICENSE)
