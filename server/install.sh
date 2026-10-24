#!/usr/bin/env bash
# Atalho VPN — instala el servidor WireGuard en Ubuntu 24.04 (AWS EC2, São Paulo).
# Terraform clona el repo y lo corre al primer arranque. A mano: sudo ENDPOINT=<ip-publica> bash server/install.sh
# Es idempotente: si se vuelve a correr no regenera las llaves ni borra clientes.
set -euo pipefail
exec > >(tee -a /var/log/atalho-vpn-install.log) 2>&1
echo "== atalho-vpn: instalación $(date -u '+%F %T') UTC =="

WG=/etc/wireguard
# Si ya estaba instalado, se conservan el puerto y la IP de la primera instalación
if [[ -f "$WG/atalho-vpn.env" ]]; then source "$WG/atalho-vpn.env"; fi
WG_PORT="${WG_PORT:-51820}"
ENDPOINT="${ENDPOINT:-}"

# Reintenta: al asociar la IP fija la red se corta unos segundos
retry() { local i; for i in $(seq 1 10); do "$@" && return 0; echo "reintento $i: $*"; sleep 10; done; return 1; }

export DEBIAN_FRONTEND=noninteractive
retry apt-get update -y
retry apt-get install -y wireguard wireguard-tools qrencode iptables iproute2 curl unattended-upgrades

# Interfaz de salida a internet (en EC2 suele ser ens5)
NIC="$(ip -4 route show default | awk '{print $5; exit}')"

# Reenvío de paquetes (accept_ra=2 para no perder la ruta IPv6 al activar forwarding)
cat > /etc/sysctl.d/99-atalho-vpn.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.${NIC}.accept_ra = 2
EOF
sysctl --system >/dev/null

mkdir -p "$WG/clients" "$WG/peers"
chmod 700 "$WG" "$WG/clients" "$WG/peers"

if [[ ! -f "$WG/server.key" ]]; then
  (umask 077; wg genkey > "$WG/server.key")
  wg pubkey < "$WG/server.key" > "$WG/server.pub"
fi

if [[ ! -f "$WG/atalho-vpn.env" ]]; then
  cat > "$WG/atalho-vpn.env" <<EOF
# Configuración de Atalho VPN (la leen vpnctl y atalho-vpn-fw)
WG_PORT=$WG_PORT
NIC=$NIC
NET4=10.66.66
NET6=fd66:66:66::
# IP pública fija del servidor; vacío = se detecta sola al crear cada cliente
ENDPOINT=$ENDPOINT
EOF
  chmod 600 "$WG/atalho-vpn.env"
fi

# --- Firewall/NAT del túnel (lo llaman PostUp/PostDown de wg-quick) ---
cat > /usr/local/sbin/atalho-vpn-fw <<'FW'
#!/usr/bin/env bash
# Uso: atalho-vpn-fw up|down — NAT y reglas de reenvío para wg0
set -uo pipefail
source /etc/wireguard/atalho-vpn.env
# Al subir, cualquier regla que falle detiene wg0 (error visible); al bajar se ignoran
op=-A; if [[ "${1:-up}" == down ]]; then op=-D; else set -e; fi

# Cadenas propias insertadas al inicio de INPUT/FORWARD: así funcionan aunque la imagen
# traiga reglas REJECT al final (Oracle Cloud las trae)
for ipt in iptables ip6tables; do
  for c in INPUT FORWARD; do
    $ipt -D "$c" -j "ATALHO-$c" 2>/dev/null || true
    $ipt -F "ATALHO-$c" 2>/dev/null || true
    $ipt -X "ATALHO-$c" 2>/dev/null || true
  done
done

if [[ $op == -A ]]; then
  for ipt in iptables ip6tables; do
    for c in INPUT FORWARD; do $ipt -N "ATALHO-$c"; $ipt -I "$c" 1 -j "ATALHO-$c"; done
    $ipt -A ATALHO-INPUT -p udp --dport "$WG_PORT" -j ACCEPT
    $ipt -A ATALHO-FORWARD -i wg0 -o wg0 -j DROP                         # los clientes no se ven entre sí
  done
  iptables -A ATALHO-FORWARD -i wg0 -d 169.254.0.0/16 -j DROP           # sin acceso a la metadata de la nube
  iptables -A ATALHO-FORWARD -i wg0 -o "$NIC" -j ACCEPT
  iptables -A ATALHO-FORWARD -i "$NIC" -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  if ip -6 addr show dev "$NIC" scope global | grep -q inet6; then
    ip6tables -A ATALHO-FORWARD -i wg0 -o "$NIC" -j ACCEPT
    ip6tables -A ATALHO-FORWARD -i "$NIC" -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  else
    # El servidor no tiene IPv6: se rechaza al instante para que las apps usen IPv4 sin esperar
    ip6tables -A ATALHO-FORWARD -i wg0 -p tcp -j REJECT --reject-with tcp-reset
    ip6tables -A ATALHO-FORWARD -i wg0 -j REJECT
  fi
fi

iptables -t nat $op POSTROUTING -s "$NET4.0/24" -o "$NIC" -j MASQUERADE
if ip -6 addr show dev "$NIC" scope global | grep -q inet6; then
  ip6tables -t nat $op POSTROUTING -s "${NET6}/64" -o "$NIC" -j MASQUERADE
fi

for ipt in iptables ip6tables; do
  $ipt -t mangle $op FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
done
exit 0
FW
chmod 700 /usr/local/sbin/atalho-vpn-fw

# --- Cabecera del servidor; vpnctl arma wg0.conf = cabecera + peers/*.conf ---
cat > "$WG/wg0.header" <<EOF
# Generado por Atalho VPN. No editar wg0.conf a mano: usa vpnctl.
[Interface]
Address = 10.66.66.1/24, fd66:66:66::1/64
ListenPort = $WG_PORT
PrivateKey = $(cat "$WG/server.key")
PostUp = /usr/local/sbin/atalho-vpn-fw up
PostDown = /usr/local/sbin/atalho-vpn-fw down
EOF
chmod 600 "$WG/wg0.header"

# --- vpnctl: administración de clientes ---
cat > /usr/local/sbin/vpnctl <<'VPNCTL'
#!/usr/bin/env bash
# vpnctl — clientes de Atalho VPN. Ejecuta "sudo vpnctl" para ver la ayuda.
set -euo pipefail
shopt -s nullglob

WG=/etc/wireguard
source "$WG/atalho-vpn.env"
# Rangos de Anthropic: claude.ai, claude.com, api.anthropic.com, claudeusercontent.com
# (https://docs.claude.com/en/api/ip-addresses)
CLAUDE_IPS="160.79.104.0/23, 2607:6bc0::/48"
DNS="1.1.1.1, 2606:4700:4700::1111"
EXPORT_DIR=/home/ubuntu/vpn-clientes

die() { echo "error: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "ejecuta con sudo"

usage() {
  cat <<'EOF'
vpnctl — clientes de Atalho VPN

  sudo vpnctl add NOMBRE [APPS]        crea un cliente (un dispositivo = un cliente)
                                       APPS = apps del modo por app en Windows (por defecto: claude)
  sudo vpnctl list                     clientes, última conexión y tráfico
  sudo vpnctl check                    revisa que el servidor esté funcionando
  sudo vpnctl qr NOMBRE [claude|todo]  QR para el iPhone (por defecto: claude)
  sudo vpnctl export NOMBRE            copia las configs a /home/ubuntu/vpn-clientes/NOMBRE para bajarlas con scp
  sudo vpnctl remove NOMBRE            revoca el acceso y borra sus llaves

Cada cliente recibe 3 configs (misma llave; activa solo una a la vez):
  atalho-vpn-claude.conf  solo el tráfico hacia Claude/Anthropic (iPhone y PC, app oficial de WireGuard)
  atalho-vpn-app.conf     solo las apps de APPS (Windows con WireSock Secure Connect)
  atalho-vpn-todo.conf    todo el tráfico por la VPN
EOF
}

check_name() { [[ "${1:-}" =~ ^[a-z0-9_-]{1,32}$ ]] || die "nombre inválido: usa a-z, 0-9, - y _ (máx. 32)"; }
need_client() { check_name "${1:-}"; [[ -d "$WG/clients/$1" ]] || die "no existe el cliente $1"; }

rebuild() {
  cat "$WG/wg0.header" "$WG"/peers/*.conf > "$WG/wg0.conf"
  chmod 600 "$WG/wg0.conf"
  wg syncconf wg0 <(wg-quick strip wg0)
}

free_octet() {
  local used=" " f n
  for f in "$WG"/clients/*/ip; do used+="$(<"$f") "; done
  for n in $(seq 2 254); do [[ $used == *" $n "* ]] || { echo "$n"; return; }; done
  die "no quedan IPs libres"
}

cmd_add() {
  check_name "${1:-}"
  local name=$1 apps=${2:-claude} d="$WG/clients/$1" n ep priv pub psk iface peer
  [[ ! -e $d ]] || die "ya existe el cliente $name"
  n=$(free_octet)
  ep=${ENDPOINT:-$(curl -fsS --max-time 5 https://checkip.amazonaws.com || true)}
  [[ -n $ep ]] || die "no pude detectar la IP pública; ponla en ENDPOINT= de $WG/atalho-vpn.env"
  priv=$(wg genkey); pub=$(wg pubkey <<<"$priv"); psk=$(wg genpsk)

  umask 077
  mkdir -p "$d"
  echo "$n" > "$d/ip"
  echo "$pub" > "$d/publickey"
  cat > "$WG/peers/$name.conf" <<EOF

# cliente: $name
[Peer]
PublicKey = $pub
PresharedKey = $psk
AllowedIPs = $NET4.$n/32, $NET6$n/128
EOF

  iface="[Interface]
PrivateKey = $priv
Address = $NET4.$n/32, $NET6$n/128"
  peer="[Peer]
PublicKey = $(<"$WG/server.pub")
PresharedKey = $psk
Endpoint = $ep:$WG_PORT
PersistentKeepalive = 25"
  printf '%s\n\n%s\nAllowedIPs = %s\n' "$iface" "$peer" "$CLAUDE_IPS" > "$d/atalho-vpn-claude.conf"
  printf '%s\n\n%s\nAllowedIPs = 0.0.0.0/0, ::/0\nAllowedApps = %s\n' "$iface" "$peer" "$apps" > "$d/atalho-vpn-app.conf"
  printf '%s\nDNS = %s\n\n%s\nAllowedIPs = 0.0.0.0/0, ::/0\n' "$iface" "$DNS" "$peer" > "$d/atalho-vpn-todo.conf"

  rebuild
  echo "Cliente $name creado ($NET4.$n). Siguiente paso:"
  echo "  iPhone:  sudo vpnctl qr $name"
  echo "  Laptop:  sudo vpnctl export $name   (y luego scp desde la laptop)"
}

cmd_list() {
  local d name pub n hs rx tx when
  declare -A HS RX TX
  while read -r pub hs; do HS[$pub]=$hs; done < <(wg show wg0 latest-handshakes)
  while read -r pub rx tx; do RX[$pub]=$rx; TX[$pub]=$tx; done < <(wg show wg0 transfer)
  printf '%-24s %-13s %-22s %10s %10s\n' CLIENTE IP "ULTIMA CONEXION (UTC)" RECIBIDO ENVIADO
  for d in "$WG"/clients/*/; do
    name=$(basename "$d"); pub=$(<"$d/publickey"); n=$(<"$d/ip")
    hs=${HS[$pub]:-0}
    if (( hs > 0 )); then when=$(date -u -d "@$hs" '+%F %H:%M'); else when=nunca; fi
    printf '%-24s %-13s %-22s %10s %10s\n' "$name" "$NET4.$n" "$when" \
      "$(numfmt --to=iec "${RX[$pub]:-0}")" "$(numfmt --to=iec "${TX[$pub]:-0}")"
  done
}

cmd_qr() {
  need_client "${1:-}"
  local mode=${2:-claude}
  [[ $mode == claude || $mode == todo ]] || die "modo para QR: claude o todo"
  qrencode -t ansiutf8 < "$WG/clients/$1/atalho-vpn-$mode.conf"
  echo "(atalho-vpn-$mode de $1) En el iPhone: WireGuard → + → Crear desde código QR"
}

cmd_export() {
  need_client "${1:-}"
  local out="$EXPORT_DIR/$1"
  install -d -o ubuntu -g ubuntu -m 700 "$EXPORT_DIR" "$out"
  install -o ubuntu -g ubuntu -m 600 "$WG/clients/$1"/*.conf "$out/"
  echo "Copiado en $out. Desde la laptop (PowerShell):"
  echo "  scp -r ubuntu@${ENDPOINT:-<IP>}:$out \$env:USERPROFILE\\vpn-clientes"
  echo "Después bórralo del servidor: rm -r $out"
}

cmd_check() {
  local fallas=0 pub
  chk() { if eval "$2" >/dev/null 2>&1; then echo "  OK     $1"; else echo "  FALLA  $1"; fallas=$((fallas + 1)); fi; }
  echo "Revisión del servidor:"
  chk "túnel wg0 activo" "wg show wg0"
  chk "escuchando en UDP $WG_PORT" "ss -lun | grep -q ':$WG_PORT '"
  chk "reenvío IPv4 activo" "[[ \$(sysctl -n net.ipv4.ip_forward) == 1 ]]"
  chk "NAT de los clientes" "iptables -t nat -C POSTROUTING -s $NET4.0/24 -o $NIC -j MASQUERADE"
  chk "salida a internet" "curl -fsS --max-time 5 https://checkip.amazonaws.com"
  chk "llega a Claude" "curl -s -o /dev/null --max-time 5 https://claude.ai"
  pub=$(curl -fsS --max-time 5 https://checkip.amazonaws.com || true)
  chk "IP de los clientes = IP pública ($pub)" "[[ -z '$ENDPOINT' || '$pub' == '$ENDPOINT' ]]"
  (( fallas == 0 )) && echo "Todo bien." || echo "$fallas revisión(es) fallaron."
  return "$fallas"
}

cmd_remove() {
  need_client "${1:-}"
  rm -f "$WG/peers/$1.conf"
  rm -rf "$WG/clients/$1" "$EXPORT_DIR/$1"
  rebuild
  echo "Cliente $1 revocado."
}

case "${1:-}" in
  add)    shift; cmd_add "$@" ;;
  list)   cmd_list ;;
  check)  cmd_check ;;
  qr)     shift; cmd_qr "$@" ;;
  export) shift; cmd_export "$@" ;;
  remove) shift; cmd_remove "$@" ;;
  *)      usage ;;
esac
VPNCTL
chmod 700 /usr/local/sbin/vpnctl

# Primer arranque: wg0.conf con la cabecera + clientes que ya existan
shopt -s nullglob
cat "$WG/wg0.header" "$WG"/peers/*.conf > "$WG/wg0.conf"
chmod 600 "$WG/wg0.conf"
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo "== atalho-vpn listo: puerto UDP $WG_PORT, interfaz $NIC, endpoint ${ENDPOINT:-auto} =="
wg show wg0
