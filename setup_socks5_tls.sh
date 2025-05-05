#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <proxy-username> <proxy-password>"
  exit 1
fi

PROXY_USER="$1"
PROXY_PASS="$2"
DANTE_CONF="/etc/danted.conf"
STUNNEL_CONF="/etc/stunnel/stunnel.conf"
CERT_FILE="/etc/stunnel/stunnel.pem"

echo "🔧 Installing packages…"
apt update
DEBIAN_FRONTEND=noninteractive apt install -y stunnel4 dante-server openssl

echo "👤 Creating proxy user…"
if ! id "$PROXY_USER" &>/dev/null; then
  useradd --no-create-home --shell /usr/sbin/nologin "$PROXY_USER"
fi
echo "${PROXY_USER}:${PROXY_PASS}" | chpasswd

echo "📝 Writing Dante config to ${DANTE_CONF}…"
cat > "$DANTE_CONF" <<EOF
logoutput: syslog
internal: 127.0.0.1 port = 1080
external: eth0
method: username
user.notprivileged: nobody

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: connect disconnect error
}

pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  protocol: tcp udp
  method: username
}
EOF

echo "🔐 Generating self-signed certificate…"
openssl req -new -x509 -days 3650 -nodes \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=Proxy/CN=$(hostname)" \
  -out "$CERT_FILE" \
  -keyout "$CERT_FILE"
chmod 600 "$CERT_FILE"

echo "📝 Writing stunnel config to ${STUNNEL_CONF}…"
cat > "$STUNNEL_CONF" <<EOF
pid = /var/run/stunnel.pid
output = /var/log/stunnel4.log

[socks5]
accept  = 443
connect = 127.0.0.1:1080
cert    = $CERT_FILE
EOF

echo "🚀 Restarting services…"
systemctl restart danted
systemctl enable danted
systemctl restart stunnel4
systemctl enable stunnel4

echo
echo "✅ TLS-wrapped SOCKS5 proxy is up!"
echo "   • Server:  your.server.ip" 
echo "   • Port:    443"
echo "   • Username:${PROXY_USER}"
echo "   • Password:${PROXY_PASS}"
