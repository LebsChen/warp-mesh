#!/bin/bash
set -e

ROLE="${WARP_ROLE:-node}"
VALID_ROLES="node relay client"
if ! echo "$VALID_ROLES" | grep -qw "$ROLE"; then
  echo "[ERROR] Invalid WARP_ROLE: ${ROLE}. Must be one of: ${VALID_ROLES}"
  exit 1
fi

echo "[INFO] warp-mesh starting (role: ${ROLE})..."

# ============================================================
# 函数定义
# ============================================================

generate_gost_config() {
  local bind="$1" socks_port="$2" http_port="$3" auth="$4" remote="$5"
  local config="${GOST_CONFIG:-/etc/gost/gost.yaml}"

  local remote_addr=""
  local remote_proto="socks5"
  if [ -n "${remote}" ]; then
    case "$remote" in
      *://*)
        remote_proto="${remote%%://*}"
        remote_addr="${remote#*://}"
        ;;
      *)
        remote_addr="${remote}"
        ;;
    esac
  fi

  mkdir -p "$(dirname "${config}")"

  # --- services ---
  cat > "${config}" << EOF
services:
  - name: socks5-service
    addr: "${bind}:${socks_port}"
    handler:
      type: socks5
EOF

  if [ -n "${auth}" ]; then
    local user="${auth%%:*}"
    local pass="${auth#*:}"
    cat >> "${config}" << EOF
      auth:
        username: ${user}
        password: ${pass}
EOF
  fi

  if [ -n "${remote_addr}" ]; then
    echo "      chain: gost-chain" >> "${config}"
  fi

  cat >> "${config}" << EOF
    listener:
      type: tcp

  - name: http-service
    addr: "${bind}:${http_port}"
    handler:
      type: http
EOF

  if [ -n "${auth}" ]; then
    cat >> "${config}" << EOF
      auth:
        username: ${user}
        password: ${pass}
EOF
  fi

  if [ -n "${remote_addr}" ]; then
    echo "      chain: gost-chain" >> "${config}"
  fi

  cat >> "${config}" << EOF
    listener:
      type: tcp
EOF

  # --- chains ---
  if [ -n "${remote_addr}" ]; then
    cat >> "${config}" << EOF

chains:
  - name: gost-chain
    hops:
      - name: hop-remote
        nodes:
          - name: remote-node
            addr: ${remote_addr}
            connector:
              type: ${remote_proto}
            dialer:
              type: tcp
EOF
  fi

  # --- log ---
  cat >> "${config}" << EOF

log:
  level: info
  format: text
  output: stdout
EOF

  echo "[INFO] GOST config generated: ${config}"
}

# ============================================================
# 1. 基础服务
# ============================================================

echo "[INFO] Starting dbus..."
mkdir -p /run/dbus
dbus-daemon --system --fork || true

echo "[INFO] Starting warp-svc..."
warp-svc &

sleep ${WARP_SLEEP:-5}

# ============================================================
# 2. MDM 配置（可选）
# ============================================================

if [ -n "${MDM_TOKEN}" ]; then
  mkdir -p /var/lib/cloudflare-warp
  cat > /var/lib/cloudflare-warp/mdm.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<config>
  <organization>${MDM_ORG:-}</organization>
  <token>${MDM_TOKEN}</token>
</config>
EOF
  echo "[INFO] MDM config written"
fi

# ============================================================
# 3. WARP Connector 注册
# ============================================================

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

# ============================================================
# 4. WARP 可选配置
# ============================================================

[ -n "${WARP_MODE}" ] && warp-cli --accept-tos mode set "${WARP_MODE}" 2>/dev/null || true
[ -n "${WARP_ENDPOINT}" ] && warp-cli --accept-tos tunnel endpoint set "${WARP_ENDPOINT}" 2>/dev/null || true
[ -n "${WARP_PROTOCOL}" ] && warp-cli --accept-tos tunnel protocol set "${WARP_PROTOCOL}" 2>/dev/null || true
[ -n "${WARP_VNET}" ] && warp-cli --accept-tos vnet set "${WARP_VNET}" 2>/dev/null || true
[ -n "${WARP_PROXY_PORT}" ] && warp-cli --accept-tos proxy port "${WARP_PROXY_PORT}" 2>/dev/null || true

# ============================================================
# 5. WARP 连接
# ============================================================

if [ "${WARP_AUTO_CONNECT:-true}" = "true" ]; then
  echo "[INFO] Connecting WARP..."
  warp-cli --accept-tos connect 2>/dev/null || true
fi

warp-cli --accept-tos status

# ============================================================
# 6. Mesh 路由
# ============================================================

echo "[INFO] Mesh IP:"
ip addr show CloudflareWARP 2>/dev/null | grep "inet " || echo "  No mesh IP yet"

echo "[INFO] Adding mesh route (100.96.0.0/16 → CloudflareWARP)..."
ip route add 100.96.0.0/16 dev CloudflareWARP 2>/dev/null || true

# ============================================================
# 7. GOST 代理（配置文件）
# ============================================================

GOST_CONFIG="${GOST_CONFIG:-/etc/gost/gost.yaml}"
GOST_BIND="${GOST_BIND:-0.0.0.0}"
GOST_SOCKS_PORT="${GOST_SOCKS_PORT:-1080}"
GOST_HTTP_PORT="${GOST_HTTP_PORT:-8080}"

AUTH=""
if [ -n "${GOST_USER}" ] && [ -n "${GOST_PASS}" ]; then
  AUTH="${GOST_USER}:${GOST_PASS}@"
  echo "[INFO] GOST auth enabled"
fi

case "${ROLE}" in
  node)
    generate_gost_config "${GOST_BIND}" "${GOST_SOCKS_PORT}" "${GOST_HTTP_PORT}" "${AUTH}" "${GOST_REMOTE}"
    echo "[INFO] Role: node (落地) — listen ${GOST_BIND}:${GOST_SOCKS_PORT}/${GOST_HTTP_PORT}"
    ;;
  relay)
    generate_gost_config "${GOST_BIND}" "${GOST_SOCKS_PORT}" "${GOST_HTTP_PORT}" "${AUTH}" "${GOST_REMOTE}"
    echo "[INFO] Role: relay (中转) — listen ${GOST_BIND}:${GOST_SOCKS_PORT}/${GOST_HTTP_PORT} → ${GOST_REMOTE:-direct}"
    ;;
  client)
    LOCAL_BIND="${GOST_LOCAL_BIND:-127.0.0.1}"
    LOCAL_SOCKS="${GOST_LOCAL_PORT:-${GOST_SOCKS_PORT}}"
    LOCAL_HTTP="${GOST_LOCAL_HTTP_PORT:-${GOST_HTTP_PORT}}"
    generate_gost_config "${LOCAL_BIND}" "${LOCAL_SOCKS}" "${LOCAL_HTTP}" "" "${GOST_REMOTE}"
    echo "[INFO] Role: client (本地) — listen ${LOCAL_BIND}:${LOCAL_SOCKS}/${LOCAL_HTTP} → ${GOST_REMOTE:-direct}"
    ;;
esac

echo "[INFO] Starting GOST with config: ${GOST_CONFIG}"
gost -C "${GOST_CONFIG}" &

# ============================================================
# 8. 透明代理 iptables（仅 client，可选，⚠️ 谨慎）
# ============================================================

if [ "${WARP_TRANSPARENT:-false}" = "true" ]; then
  if [ "${ROLE}" != "client" ]; then
    echo "[WARN] WARP_TRANSPARENT only works with client role, ignoring"
  else
    REDIRECT_PORT="${GOST_REDIRECT_PORT:-12345}"
    echo "[INFO] Setting up transparent proxy (redirect → :${REDIRECT_PORT})..."
    echo "[WARN] ⚠️  This hijacks ALL TCP! If GOST chain fails, all TCP breaks."
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
fi

echo "[INFO] warp-mesh started (${ROLE} mode)"
tail -f /dev/null
