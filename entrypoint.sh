#!/bin/bash
set -e

ROLE="${WARP_ROLE:-node}"
VALID_ROLES="node relay client"
if ! echo "$VALID_ROLES" | grep -qw "$ROLE"; then
  echo "[ERROR] Invalid WARP_ROLE: ${ROLE}. Must be one of: ${VALID_ROLES}"
  exit 1
fi

echo "[INFO] warp-mesh starting (role: ${ROLE})..."

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
  echo "[INFO] MDM config written"
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
ip addr show CloudflareWARP 2>/dev/null | grep "inet " || echo "  No mesh IP yet"

echo "[INFO] Adding mesh route (100.96.0.0/16 → CloudflareWARP)..."
ip route add 100.96.0.0/16 dev CloudflareWARP 2>/dev/null || true

# === 7. GOST 代理 ===
# GOST 配置优先级：GOST_CONFIG 文件 > 环境变量命令行
# 注意：GOST v3 配置文件的 chain/forward 功能有 bug，推荐用命令行 -F 参数

GOST_BIND="${GOST_BIND:-0.0.0.0}"
GOST_SOCKS_PORT="${GOST_SOCKS_PORT:-1080}"
GOST_HTTP_PORT="${GOST_HTTP_PORT:-8080}"

# 构建 GOST -F 转发参数
GOST_FWD=""
if [ -n "${GOST_REMOTE}" ]; then
  # GOST_REMOTE 格式: socks5://host:port 或 host:port
  case "$GOST_REMOTE" in
    *://*) GOST_FWD="-F ${GOST_REMOTE}" ;;
    *)     GOST_FWD="-F socks5://${GOST_REMOTE}" ;;
  esac
  echo "[INFO] GOST forward -> ${GOST_REMOTE}"
fi

# 构建 GOST 认证参数
GOST_AUTH=""
if [ -n "${GOST_USER}" ] && [ -n "${GOST_PASS}" ]; then
  GOST_AUTH="${GOST_USER}:${GOST_PASS}@"
  echo "[INFO] GOST auth enabled"
fi

# 构建 GOST 监听参数
GOST_LISTEN=""
case "${ROLE}" in
  node)
    # 落地节点：监听 SOCKS5 + HTTP，接受 mesh 连入，可转发到下一跳
    GOST_LISTEN="-L socks5://${GOST_AUTH}${GOST_BIND}:${GOST_SOCKS_PORT} -L http://${GOST_AUTH}${GOST_BIND}:${GOST_HTTP_PORT}"
    echo "[INFO] GOST listen: socks5://${GOST_BIND}:${GOST_SOCKS_PORT}, http://${GOST_BIND}:${GOST_HTTP_PORT}"
    ;;
  relay)
    # 中转节点：监听 SOCKS5 + HTTP，接受 mesh 连入，必须转发到下一跳
    GOST_LISTEN="-L socks5://${GOST_AUTH}${GOST_BIND}:${GOST_SOCKS_PORT} -L http://${GOST_AUTH}${GOST_BIND}:${GOST_HTTP_PORT}"
    echo "[INFO] GOST listen: socks5://${GOST_BIND}:${GOST_SOCKS_PORT}, http://${GOST_BIND}:${GOST_HTTP_PORT}"
    if [ -z "${GOST_REMOTE}" ]; then
      echo "[WARN] relay role without GOST_REMOTE — traffic will go direct"
    fi
    ;;
  client)
    # 本地客户端：只监听本地 SOCKS5（+可选 HTTP），转发到 mesh 下一跳
    LOCAL_BIND="${GOST_LOCAL_BIND:-127.0.0.1}"
    LOCAL_SOCKS="${GOST_LOCAL_PORT:-${GOST_SOCKS_PORT}}"
    LOCAL_HTTP="${GOST_LOCAL_HTTP_PORT:-${GOST_HTTP_PORT}}"
    GOST_LISTEN="-L socks5://${LOCAL_BIND}:${LOCAL_SOCKS} -L http://${LOCAL_BIND}:${LOCAL_HTTP}"
    echo "[INFO] GOST listen: socks5://${LOCAL_BIND}:${LOCAL_SOCKS}, http://${LOCAL_BIND}:${LOCAL_HTTP}"
    if [ -z "${GOST_REMOTE}" ]; then
      echo "[WARN] client role without GOST_REMOTE — no forwarding configured"
    fi
    ;;
esac

echo "[INFO] Starting GOST: gost ${GOST_LISTEN} ${GOST_FWD}"
gost ${GOST_LISTEN} ${GOST_FWD} &

# === 8. 透明代理 iptables（仅 client 角色，可选） ===
# ⚠️ 警告：透明代理会将所有 TCP 流量劫持到 GOST redirect
# 如果 GOST 转发链路不通，会导致所有 TCP 出口失败！
# 仅在明确需要且 mesh 链路稳定时启用
if [ "${WARP_TRANSPARENT:-false}" = "true" ]; then
  if [ "${ROLE}" != "client" ]; then
    echo "[WARN] WARP_TRANSPARENT only works with client role, ignoring"
  else
    REDIRECT_PORT="${GOST_REDIRECT_PORT:-12345}"
    echo "[INFO] Setting up transparent proxy (redirect → :${REDIRECT_PORT})..."
    echo "[WARN] ⚠️  This will hijack ALL TCP traffic! If GOST chain fails, all TCP breaks."

    iptables -t nat -N GOST_TRANSPARENT 2>/dev/null || true
    iptables -t nat -F GOST_TRANSPARENT
    # 排除本地和内网地址
    iptables -t nat -A GOST_TRANSPARENT -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A GOST_TRANSPARENT -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A GOST_TRANSPARENT -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A GOST_TRANSPARENT -d 192.168.0.0/16 -j RETURN
    # 100.64.0.0/10 (CGNAT) — mesh 内网流量走 WARP tunnel，不走透明代理
    # ⚠️ 如果启用 RETURN，mesh IP 的流量不会被透明代理劫持（正常行为）
    # 如果不 RETURN，GOST 到 mesh 下一跳的连接也会被劫持，形成循环！
    # 所以必须 RETURN 100.64.0.0/10
    iptables -t nat -A GOST_TRANSPARENT -d 100.64.0.0/10 -j RETURN
    iptables -t nat -A GOST_TRANSPARENT -p tcp -j REDIRECT --to-ports "${REDIRECT_PORT}"
    iptables -t nat -C OUTPUT -p tcp -j GOST_TRANSPARENT 2>/dev/null || \
      iptables -t nat -A OUTPUT -p tcp -j GOST_TRANSPARENT
    echo "[INFO] iptables transparent proxy rules applied"
  fi
fi

echo "[INFO] warp-mesh started (${ROLE} mode)"
tail -f /dev/null
