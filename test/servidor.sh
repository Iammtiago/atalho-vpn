#!/usr/bin/env bash
# Prueba de install.sh + vpnctl en un contenedor Ubuntu 24.04 (lo lanza probar-local.ps1)
set -uo pipefail
fallas=0
ok()  { echo "  OK     $1"; }
mal() { echo "  FALLA  $1"; fallas=$((fallas + 1)); }
probar() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else mal "$d"; fi; }

# El contenedor no tiene systemd: systemctl "restart" levanta wg0 con wg-quick
cat > /usr/local/bin/systemctl <<'EOF'
#!/bin/bash
[[ "$1" == restart ]] && { wg-quick down wg0 2>/dev/null; wg-quick up wg0; exit $?; }
exit 0
EOF
chmod +x /usr/local/bin/systemctl

# El kernel de Docker Desktop no trae nf_tables: se usa iptables-legacy (en EC2 no hace falta)
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq iptables >/dev/null
update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null

export ENDPOINT=$(hostname -i | awk '{print $1}') WG_PORT=51820
tr -d '\r' < /src/server/install.sh > /tmp/install.sh

echo "Servidor:"
probar "install.sh termina sin errores" bash /tmp/install.sh
probar "install.sh se puede correr dos veces" bash /tmp/install.sh
probar "wg0 activo" wg show wg0
probar "crear cliente tiago-iphone" vpnctl add tiago-iphone
probar "crear cliente tiago-laptop con apps" vpnctl add tiago-laptop "claude, chrome"
if vpnctl add "Nombre Malo" >/dev/null 2>&1; then mal "rechaza nombre inválido"; else ok "rechaza nombre inválido"; fi
if vpnctl add tiago-iphone >/dev/null 2>&1; then mal "rechaza duplicado"; else ok "rechaza duplicado"; fi
probar "config por app tiene AllowedApps" grep -q "AllowedApps = claude, chrome" /etc/wireguard/clients/tiago-laptop/atalho-vpn-app.conf
probar "config claude solo lleva rangos de Anthropic" grep -q "AllowedIPs = 160.79.104.0/23, 2607:6bc0::/48" /etc/wireguard/clients/tiago-iphone/atalho-vpn-claude.conf
probar "QR se genera" vpnctl qr tiago-iphone
probar "export deja los archivos para scp" bash -c "vpnctl export tiago-laptop && ls /home/ubuntu/vpn-clientes/tiago-laptop/atalho-vpn-todo.conf"
probar "NAT configurado" iptables -t nat -C POSTROUTING -s 10.66.66.0/24 -o eth0 -j MASQUERADE
probar "clientes aislados entre sí" iptables -C FORWARD -i wg0 -o wg0 -j DROP
vpnctl add borrar-me >/dev/null 2>&1
probar "revocar cliente" vpnctl remove borrar-me
probar "quedan 2 clientes en wg0" bash -c "[[ \$(wg show wg0 peers | wc -l) == 2 ]]"

# En Docker la IP del contenedor no es la pública: se omite esa revisión de vpnctl check
sed -i 's/^ENDPOINT=.*/ENDPOINT=/' /etc/wireguard/atalho-vpn.env
probar "vpnctl check sin fallas" vpnctl check

cp /etc/wireguard/clients/tiago-iphone/atalho-vpn-claude.conf /out/
echo "$fallas" > /out/servidor.fallas
touch /out/servidor.listo
echo "Esperando al cliente..."
for _ in $(seq 1 120); do [[ -f /out/cliente.listo ]] && break; sleep 2; done
echo "Tráfico visto por el servidor:"
vpnctl list
exit "$fallas"
