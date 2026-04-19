#!/bin/bash
set -e

echo "[INFO] warp-node starting..."

echo "[INFO] Starting dbus..."
mkdir -p /run/dbus
dbus-daemon --system --fork || true

echo "[INFO] Starting warp-svc..."
warp-svc &

sleep 5

if ! warp-cli --accept-tos status 2>/dev/null | grep -qE "Connected|Disconnected"; then
  if [ -n "${CONNECTOR_TOKEN}" ]; then
    echo "[INFO] Registering WARP Connector..."
    warp-cli --accept-tos connector new "${CONNECTOR_TOKEN}" || true
  fi
fi

[ -n "${WARP_MODE}" ] && warp-cli --accept-tos mode set "${WARP_MODE}" 2>/dev/null || true
[ -n "${WARP_ENDPOINT}" ] && warp-cli --accept-tos tunnel endpoint set "${WARP_ENDPOINT}" 2>/dev/null || true
[ -n "${WARP_PROTOCOL}" ] && warp-cli --accept-tos tunnel protocol set "${WARP_PROTOCOL}" 2>/dev/null || true
[ -n "${WARP_VNET}" ] && warp-cli --accept-tos vnet set "${WARP_VNET}" 2>/dev/null || true
[ -n "${WARP_PROXY_PORT}" ] && warp-cli --accept-tos proxy port "${WARP_PROXY_PORT}" 2>/dev/null || true

if [ "${WARP_AUTO_CONNECT:-true}" = "true" ]; then
  echo "[INFO] Connecting WARP..."
  warp-cli --accept-tos connect 2>/dev/null || true
fi

warp-cli --accept-tos status

echo "[INFO] Mesh IP:"
ip addr show CloudflareWARP 2>/dev/null | grep inet || echo "No IP"

CONFIG_FILE="${GOST_CONFIG:-/etc/gost/gost.yaml}"
GOST_BIND="${GOST_BIND:-0.0.0.0}"
GOST_SOCKS_PORT="${GOST_SOCKS_PORT:-1080}"
GOST_HTTP_PORT="${GOST_HTTP_PORT:-8080}"

if [ -f "$CONFIG_FILE" ]; then
  echo "[INFO] Using config file: $CONFIG_FILE"
  gost -C "$CONFIG_FILE" &
else
  echo "[WARN] Config not found, using default..."
  if [ -n "${GOST_USER}" ] && [ -n "${GOST_PASS}" ]; then
    gost -L "socks5://${GOST_USER}:${GOST_PASS}@${GOST_BIND}:${GOST_SOCKS_PORT}" -L "http://${GOST_USER}:${GOST_PASS}@${GOST_BIND}:${GOST_HTTP_PORT}" &
  else
    gost -L "socks5://${GOST_BIND}:${GOST_SOCKS_PORT}" -L "http://${GOST_BIND}:${GOST_HTTP_PORT}" &
  fi
fi

echo "[INFO] warp-node started"
tail -f /dev/null
