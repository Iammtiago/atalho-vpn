#!/usr/bin/env bash
# Cliente de prueba: conecta con atalho-vpn-claude.conf y verifica que solo Claude va por el túnel
set -uo pipefail
fallas=0
ok()  { echo "  OK     $1"; }
mal() { echo "  FALLA  $1"; fallas=$((fallas + 1)); }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq wireguard-tools iproute2 curl >/dev/null
for _ in $(seq 1 120); do [[ -f /out/servidor.listo ]] && break; sleep 2; done

echo "Cliente:"
mkdir -p /etc/wireguard && cp /out/atalho-vpn-claude.conf /etc/wireguard/wg0.conf
if wg-quick up wg0 >/dev/null 2>&1; then ok "conecta el túnel"; else mal "conecta el túnel"; fi
[[ $(ip -4 route get 160.79.104.10) == *"dev wg0"* ]] && ok "Claude (160.79.104.10) va por el túnel" || mal "Claude va por el túnel"
[[ $(ip -4 route get 1.1.1.1) != *"dev wg0"* ]] && ok "el resto de internet NO va por el túnel" || mal "el resto NO va por el túnel"
code=$(curl -4 -s -o /dev/null -w '%{http_code}' --max-time 10 https://claude.ai/)
[[ $code != 000 ]] && ok "claude.ai responde por el túnel (HTTP $code)" || mal "claude.ai responde por el túnel"
hs=$(wg show wg0 latest-handshakes | awk '{print $2}')
(( hs > 0 )) && ok "handshake con el servidor" || mal "handshake con el servidor"

touch /out/cliente.listo
exit "$fallas"
