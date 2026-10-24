# vpnctl

Comando del servidor para administrar los clientes. Siempre con `sudo`.

| Comando | Qué hace |
|---|---|
| `vpnctl add NOMBRE [APPS]` | Crea un cliente (un dispositivo = un cliente). `APPS` son las apps del modo por app en Windows, separadas por coma (por defecto `claude`). |
| `vpnctl list` | Clientes, IP en el túnel, última conexión (UTC) y tráfico. |
| `vpnctl check` | Revisa el servidor: túnel activo, puerto, reenvío, NAT, salida a internet, acceso a Claude y la IP pública. |
| `vpnctl qr NOMBRE [claude\|todo]` | Muestra un QR en la terminal para la app WireGuard del iPhone (por defecto `claude`). |
| `vpnctl export NOMBRE` | Copia las configs a `/home/ubuntu/vpn-clientes/NOMBRE` para bajarlas con `scp`. |
| `vpnctl remove NOMBRE` | Revoca el acceso y borra las llaves del cliente. |

`NOMBRE`: minúsculas, números, `-` y `_`, máximo 32 caracteres. Ejemplo: `tiago-iphone`.

## Configs de cada cliente

Se generan tres archivos con la misma llave (usa solo uno a la vez por dispositivo):

| Archivo | `AllowedIPs` | Para qué |
|---|---|---|
| `atalho-vpn-claude.conf` | `160.79.104.0/23, 2607:6bc0::/48` | Solo el tráfico hacia Anthropic. App oficial de WireGuard (iPhone, Windows, Mac, Android). |
| `atalho-vpn-app.conf` | `0.0.0.0/0, ::/0` + `AllowedApps` | Solo las apps elegidas. WireSock Secure Connect (Windows). |
| `atalho-vpn-todo.conf` | `0.0.0.0/0, ::/0` + DNS `1.1.1.1` | Todo el tráfico por la VPN. |

## Dónde vive cada cosa en el servidor

| Ruta | Contenido |
|---|---|
| `/etc/wireguard/atalho-vpn.env` | Puerto, interfaz, redes del túnel e IP pública (`ENDPOINT`) |
| `/etc/wireguard/wg0.header` | Cabecera del servidor (llave privada); `wg0.conf` = cabecera + `peers/*.conf` |
| `/etc/wireguard/peers/NOMBRE.conf` | El peer de cada cliente en el servidor |
| `/etc/wireguard/clients/NOMBRE/` | Las 3 configs del cliente, su IP y su llave pública |
| `/usr/local/sbin/atalho-vpn-fw` | Reglas de NAT y firewall (lo llama `wg-quick`) |
| `/var/log/atalho-vpn-install.log` | Log de la instalación |
| `/opt/atalho-vpn` | Este repositorio, clonado por Terraform |

Red del túnel: `10.66.66.0/24` y `fd66:66:66::/64`. El servidor es `.1`; los clientes, de `.2` en adelante.

## Respaldo

Todo el estado está en `/etc/wireguard`. Para guardarlo:

```bash
sudo tar czf /home/ubuntu/atalho-vpn-respaldo.tgz -C /etc wireguard
```

Tiene llaves privadas: guárdalo en un lugar privado.
