#!/bin/bash
set -e

echo "[INFO] warp-connector starting (role: ${WARP_ROLE:-node})..."

# === 1. 基础服务 ===
echo "[INFO] Starting dbus..."
mkdir -p /run/dbus
dbus-daemon --system --fork || true

echo "[INFO] Starting warp-svc..."
warp-svc &

sleep ${WARP_SLEEP:-5}

# === 2. MDM 配置（可选） ===
if [ -n "${MDM_TOKEN}" ]; then
  mkdir -p /var/lib/cloudflare-warp
  cat > /var/lib/cloudflare-warp/mdm.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<config>
  <organization>${MDM_ORG:-}</organization>
  <token>${MDM_TOKEN}</token>
</config>
EOF
  echo '[INFO] MDM config written'
fi

# === 3. WARP Connector 注册 ===
if ! warp-cli --accept-tos status 2>/dev/null | grep -qE "Connected|Disconnected"; then
  if [ -n "${CONNECTOR_TOKEN}" ]; then
    echo "[INFO] Registering WARP Connector..."
    warp-cli --accept-tos connector new "${CONNECTOR_TOKEN}" || true
  else
    echo "[WARN] No CONNECTOR_TOKEN provided"
  fi
else
  echo "[INFO] Already registered"
fi

# === 4. WARP 可选配置 ===
[ -n "${WARP_MODE}" ] && warp-cli --accept-tos mode set "${WARP_MODE}" 2>/dev/null || true
[ -n "${WARP_ENDPOINT}" ] && warp-cli --accept-tos tunnel endpoint set "${WARP_ENDPOINT}" 2>/dev/null || true
[ -n "${WARP_PROTOCOL}" ] && warp-cli --accept-tos tunnel protocol set "${WARP_PROTOCOL}" 2>/dev/null || true
[ -n "${WARP_VNET}" ] && warp-cli --accept-tos vnet set "${WARP_VNET}" 2>/dev/null || true
[ -n "${WARP_PROXY_PORT}" ] && warp-cli --accept-tos proxy port "${WARP_PROXY_PORT}" 2>/dev/null || true

# === 5. WARP 连接 ===
if [ "${WARP_AUTO_CONNECT:-true}" = "true" ]; then
  echo "[INFO] Connecting WARP..."
  warp-cli --accept-tos connect 2>/dev/null || true
fi

warp-cli --accept-tos status

# === 6. Mesh 路由 ===
echo "[INFO] Mesh IP:"
warp-cli --accept-tos debug network 2>/dev/null | grep -E 'Interface Addresses|100\.' || ip addr show CloudflareWARP 2>/dev/null | grep inet || echo "No mesh IP yet"

echo "[INFO] Adding mesh route (100.96.0.0/16 → CloudflareWARP)..."
ip route add 100.96.0.0/16 dev CloudflareWARP 2>/dev/null || true

# === 7. GOST 代理 ===
CONFIG_FILE="${GOST_CONFIG:-/etc/gost/gost.yaml}"
GOST_BIND="${GOST_BIND:-0.0.0.0}"
GOST_SOCKS_PORT="${GOST_SOCKS_PORT:-1080}"
GOST_HTTP_PORT="${GOST_HTTP_PORT:-8080}"

if [ -f "$CONFIG_FILE" ]; then
  echo "[INFO] Starting GOST with config: $CONFIG_FILE"
  gost -C "$CONFIG_FILE" &
else
  echo "[WARN] No config file, using env vars (role: ${WARP_ROLE:-node})..."
  case "${WARP_ROLE:-node}" in
    client)
      if [ -n "${GOST_REMOTE_HOST}" ]; then
        echo "[INFO] GOST forward -> ${GOST_REMOTE_HOST}:${GOST_REMOTE_PORT:-1080}"
        gost -L "socks5://${GOST_LOCAL_BIND:-127.0.0.1}:${GOST_LOCAL_PORT:-1080}" \
             -F "socks5://${GOST_REMOTE_HOST}:${GOST_REMOTE_PORT:-1080}" &
      else
        gost -L "socks5://${GOST_LOCAL_BIND:-127.0.0.1}:${GOST_LOCAL_PORT:-1080}" &
      fi
      ;;
    node|*)
      if [ -n "${GOST_USER}" ] && [ -n "${GOST_PASS}" ]; then
        gost -L "socks5://${GOST_USER}:${GOST_PASS}@${GOST_BIND}:${GOST_SOCKS_PORT}" \
             -L "http://${GOST_USER}:${GOST_PASS}@${GOST_BIND}:${GOST_HTTP_PORT}" &
      else
        gost -L "socks5://${GOST_BIND}:${GOST_SOCKS_PORT}" \
             -L "http://${GOST_BIND}:${GOST_HTTP_PORT}" &
      fi
      ;;
  esac
fi

# === 8. 透明代理 iptables（仅 client 角色，可选） ===
if [ "${WARP_TRANSPARENT:-false}" = "true" ]; then
  REDIRECT_PORT="${GOST_REDIRECT_PORT:-12345}"
  echo "[INFO] Setting up transparent proxy (redirect → ${REDIRECT_PORT})..."
  iptables -t nat -N GOST_TRANSPARENT 2>/dev/null || true
  iptables -t nat -F GOST_TRANSPARENT
  iptables -t nat -A GOST_TRANSPARENT -d 127.0.0.0/8 -j RETURN
  iptables -t nat -A GOST_TRANSPARENT -d 10.0.0.0/8 -j RETURN
  iptables -t nat -A GOST_TRANSPARENT -d 172.16.0.0/12 -j RETURN
  iptables -t nat -A GOST_TRANSPARENT -d 192.168.0.0/16 -j RETURN
  iptables -t nat -A GOST_TRANSPARENT -d 100.64.0.0/10 -j RETURN
  iptables -t nat -A GOST_TRANSPARENT -p tcp -j REDIRECT --to-ports "${REDIRECT_PORT}"
  iptables -t nat -C OUTPUT -p tcp -j GOST_TRANSPARENT 2>/dev/null || \
    iptables -t nat -A OUTPUT -p tcp -j GOST_TRANSPARENT
  echo "[INFO] iptables transparent proxy rules applied"
fi

echo "[INFO] warp-connector started (${WARP_ROLE:-node} mode)"
tail -f /dev/null