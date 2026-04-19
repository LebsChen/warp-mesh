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

# 获取 WARP 端点 IP（WireGuard + DoH + connectivity check）
get_warp_endpoint_ips() {
  local ips=""

  # 从 WARP debug 获取当前 WireGuard endpoint
  local wg_endpoint
  wg_endpoint=$(warp-cli --accept-tos tunnel endpoint 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "${wg_endpoint}" ] && ips="${ips} ${wg_endpoint}"

  # 从 warp-cli settings 获取 DoH resolver IP
  local doh_ips
  doh_ips=$(warp-cli --accept-tos settings 2>/dev/null | grep -oE '162\.159\.[0-9]+\.[0-9]+')
  for ip in ${doh_ips}; do
    ips="${ips} ${ip}"
  done

  # 解析 connectivity check 域名
  local conn_ips
  conn_ips=$(nslookup connectivity.cloudflareclient.com 2>/dev/null | grep -oE '162\.159\.[0-9]+\.[0-9]+')
  for ip in ${conn_ips}; do
    ips="${ips} ${ip}"
  done

  # 去重
  echo "${ips}" | tr ' ' '\n' | sort -u | grep -v '^$'
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
# 2. MDM 配置
# ============================================================

MDM_FILE="/var/lib/cloudflare-warp/mdm.xml"

# 如果 mdm.xml 已通过 volume 挂载，直接使用
if [ -f "${MDM_FILE}" ]; then
  echo "[INFO] Using mounted mdm.xml from ${MDM_FILE}"
  warp-cli --accept-tos mdm set-config 2>/dev/null || true

# 否则，从环境变量生成 mdm.xml
elif [ -n "${WARP_ORG}" ] || [ -n "${WARP_AUTH_CLIENT_ID}" ]; then
  echo "[INFO] Generating mdm.xml from environment variables..."
  mkdir -p /var/lib/cloudflare-warp

  cat > "${MDM_FILE}" << XMEOF
<dict>
XMEOF

  # --- 必需：组织名 ---
  [ -n "${WARP_ORG}" ] && echo "  <key>organization</key><string>${WARP_ORG}</string>" >> "${MDM_FILE}"

  # --- Service Token 认证 ---
  if [ -n "${WARP_AUTH_CLIENT_ID}" ] && [ -n "${WARP_AUTH_CLIENT_SECRET}" ]; then
    echo "  <key>auth_client_id</key><string>${WARP_AUTH_CLIENT_ID}</string>" >> "${MDM_FILE}"
    echo "  <key>auth_client_secret</key><string>${WARP_AUTH_CLIENT_SECRET}</string>" >> "${MDM_FILE}"
  fi

  # --- 连接行为 ---
  [ -n "${WARP_AUTO_CONNECT}" ] && echo "  <key>auto_connect</key><integer>${WARP_AUTO_CONNECT}</integer>" >> "${MDM_FILE}"
  [ "${WARP_SWITCH_LOCKED:-}" = "true" ] && echo "  <key>switch_locked</key><true/>" >> "${MDM_FILE}"
  [ "${WARP_ONBOARDING:-}" = "false" ] && echo "  <key>onboarding</key><false/>" >> "${MDM_FILE}"

  # --- 运行模式 ---
  [ -n "${WARP_SERVICE_MODE}" ] && echo "  <key>service_mode</key><string>${WARP_SERVICE_MODE}</string>" >> "${MDM_FILE}"
  [ -n "${WARP_PROXY_PORT}" ] && echo "  <key>proxy_port</key><integer>${WARP_PROXY_PORT}</integer>" >> "${MDM_FILE}"

  # --- 隧道协议 ---
  [ -n "${WARP_TUNNEL_PROTOCOL}" ] && echo "  <key>warp_tunnel_protocol</key><string>${WARP_TUNNEL_PROTOCOL}</string>" >> "${MDM_FILE}"

  # --- 端点覆盖 ---
  [ -n "${WARP_OVERRIDE_ENDPOINT}" ] && echo "  <key>override_warp_endpoint</key><string>${WARP_OVERRIDE_ENDPOINT}</string>" >> "${MDM_FILE}"
  [ -n "${WARP_OVERRIDE_DOH}" ] && echo "  <key>override_doh_endpoint</key><string>${WARP_OVERRIDE_DOH}</string>" >> "${MDM_FILE}"
  [ -n "${WARP_OVERRIDE_API}" ] && echo "  <key>override_api_endpoint</key><string>${WARP_OVERRIDE_API}</string>" >> "${MDM_FILE}"

  # --- 高级 ---
  [ -n "${WARP_GATEWAY_ID}" ] && echo "  <key>gateway_unique_id</key><string>${WARP_GATEWAY_ID}</string>" >> "${MDM_FILE}"
  [ -n "${WARP_ENVIRONMENT}" ] && echo "  <key>environment</key><string>${WARP_ENVIRONMENT}</string>" >> "${MDM_FILE}"
  [ "${WARP_POST_QUANTUM:-}" = "true" ] && echo "  <key>enable_post_quantum</key><true/>" >> "${MDM_FILE}"
  [ -n "${WARP_DISPLAY_NAME}" ] && echo "  <key>display_name</key><string>${WARP_DISPLAY_NAME}</string>" >> "${MDM_FILE}"
  [ -n "${WARP_SUPPORT_URL}" ] && echo "  <key>support_url</key><string>${WARP_SUPPORT_URL}</string>" >> "${MDM_FILE}"

  echo "</dict>" >> "${MDM_FILE}"

  echo "[INFO] mdm.xml generated from env vars: ${MDM_FILE}"
  warp-cli --accept-tos mdm set-config 2>/dev/null || true

else
  echo "[INFO] No mdm.xml found and no WARP_ORG/WARP_AUTH_CLIENT_ID set"
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
# 6b. Mesh 主机名映射（/etc/hosts）
# ============================================================

# MESH_HOSTS 格式："name1:ip1 name2:ip2 ..."
# 示例：MESH_HOSTS="us-vps:100.96.0.12 relay-1:100.96.0.16"
# 这样 GOST_REMOTE 可以用 socks5://us-vps:1080 而不是硬编码 IP
if [ -n "${MESH_HOSTS}" ]; then
  echo "[INFO] Adding mesh host mappings..."
  for entry in ${MESH_HOSTS}; do
    name="${entry%%:*}"
    ip="${entry#*:}"
    if [ -n "${name}" ] && [ -n "${ip}" ]; then
      # 移除旧条目（避免重复）
      sed -i "/# warp-mesh:${name}$/d" /etc/hosts
      echo "${ip} ${name} # warp-mesh:${name}" >> /etc/hosts
      echo "[INFO]   ${name} → ${ip}"
    fi
  done
fi

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
    LOCAL_BIND="${GOST_LOCAL_BIND:-0.0.0.0}"
    LOCAL_SOCKS="${GOST_LOCAL_PORT:-${GOST_SOCKS_PORT}}"
    LOCAL_HTTP="${GOST_LOCAL_HTTP_PORT:-${GOST_HTTP_PORT}}"
    generate_gost_config "${LOCAL_BIND}" "${LOCAL_SOCKS}" "${LOCAL_HTTP}" "" "${GOST_REMOTE}"
    echo "[INFO] Role: client (本地) — listen ${LOCAL_BIND}:${LOCAL_SOCKS}/${LOCAL_HTTP} → ${GOST_REMOTE:-direct}"
    ;;
esac

echo "[INFO] Starting GOST with config: ${GOST_CONFIG}"
gost -C "${GOST_CONFIG}" &

# ============================================================
# 8. 透明代理 iptables（client 默认启用）
# ============================================================

# client 角色默认启用透明代理，其他角色不启用
if [ "${ROLE}" = "client" ] || [ "${WARP_TRANSPARENT:-false}" = "true" ]; then
  REDIRECT_PORT="${GOST_REDIRECT_PORT:-12345}"
  echo "[INFO] Setting up transparent proxy (redirect → :${REDIRECT_PORT})..."

  iptables -t nat -N GOST_TRANSPARENT 2>/dev/null || true
  iptables -t nat -F GOST_TRANSPARENT

  # 排除本地回环
  iptables -t nat -A GOST_TRANSPARENT -d 127.0.0.0/8 -j RETURN

  # 排除内网地址
  iptables -t nat -A GOST_TRANSPARENT -d 10.0.0.0/8 -j RETURN
  iptables -t nat -A GOST_TRANSPARENT -d 172.16.0.0/12 -j RETURN
  iptables -t nat -A GOST_TRANSPARENT -d 192.168.0.0/16 -j RETURN

  # 排除 WARP mesh 内网（100.96.0.0/16 走 WARP tunnel，不经 GOST）
  iptables -t nat -A GOST_TRANSPARENT -d 100.64.0.0/10 -j RETURN

  # 排除 Cloudflare WARP 端点 IP（防止 WARP 断连）
  # 1. 动态获取当前 WARP 端点 IP
  WARP_ENDPOINT_IPS=$(get_warp_endpoint_ips)
  for ip in ${WARP_ENDPOINT_IPS}; do
    echo "[INFO] Excluding WARP endpoint: ${ip}"
    iptables -t nat -A GOST_TRANSPARENT -d "${ip}" -j RETURN
  done

  # 2. 兜底：排除 Cloudflare 162.159.0.0/16（覆盖 DoH、API、connectivity check）
  iptables -t nat -A GOST_TRANSPARENT -d 162.159.0.0/16 -j RETURN

  # 劫持所有其他 TCP 流量
  iptables -t nat -A GOST_TRANSPARENT -p tcp -j REDIRECT --to-ports "${REDIRECT_PORT}"
  iptables -t nat -C OUTPUT -p tcp -j GOST_TRANSPARENT 2>/dev/null || \
    iptables -t nat -A OUTPUT -p tcp -j GOST_TRANSPARENT

  echo "[INFO] iptables transparent proxy rules applied"
fi

echo "[INFO] warp-mesh started (${ROLE} mode)"
tail -f /dev/null
