# warp-mesh 配置参考

> 完整的环境变量、MDM 参数、warp-cli 命令和配置示例。

---

## 环境变量完整列表

### 核心（必需）

| 变量 | 说明 |
|---|---|
| `CONNECTOR_TOKEN` | Cloudflare Zero Trust Connector 注册 Token（从 Dashboard 获取） |
| `WARP_ROLE` | 角色：`node`（落地）/ `relay`（中转）/ `client`（本地） |

### WARP 连接

| 变量 | 默认 | 说明 |
|---|---|---|
| `WARP_AUTO_CONNECT` | `true` | 是否自动执行 `warp-cli connect` |
| `WARP_SLEEP` | `5` | warp-svc 启动后等待秒数 |
| `WARP_MODE` | — | 运行模式（见下表） |
| `WARP_ENDPOINT` | — | 强制指定 WireGuard 端点 `IP:PORT` |
| `WARP_PROTOCOL` | — | 隧道协议：`WireGuard` 或 `MASQUE` |

### WARP 运行模式（`WARP_MODE`）

| 值 | 说明 |
|---|---|
| `warp` | 建立 WARP 隧道 + UDP DNS 代理（默认） |
| `doh` | 不建立隧道，仅代理 DNS over HTTPS |
| `warp+doh` | 建立隧道 + DoH DNS |
| `dot` | 不建立隧道，仅代理 DNS over TLS |
| `warp+dot` | 建立隧道 + DoT DNS |
| `proxy` | 建立隧道用于 SOCKS5 代理 |
| `tunnel_only` | 建立隧道，不代理 DNS |

### GOST 代理

| 变量 | 默认 | 适用角色 | 说明 |
|---|---|---|---|
| `GOST_REMOTE` | — | relay, client | 转发目标，格式：`[protocol://]host:port`（默认 socks5） |
| `GOST_BIND` | `0.0.0.0` | node, relay | 监听地址 |
| `GOST_SOCKS_PORT` | `1080` | 全部 | SOCKS5 端口 |
| `GOST_HTTP_PORT` | `8080` | 全部 | HTTP 代理端口 |
| `GOST_USER` | — | node, relay | 认证用户名 |
| `GOST_PASS` | — | node, relay | 认证密码 |
| `GOST_LOCAL_BIND` | `0.0.0.0` | client | client 监听地址（局域网可达） |
| `GOST_LOCAL_PORT` | `1080` | client | client SOCKS5 端口 |
| `GOST_LOCAL_HTTP_PORT` | `8080` | client | client HTTP 端口 |
| `GOST_CONFIG` | `/etc/gost/gost.yaml` | 全部 | 配置文件路径 |

### 透明代理（client 默认启用）

| 变量 | 默认 | 说明 |
|---|---|---|
| `WARP_TRANSPARENT` | `true`(client) | 启用 iptables 透明代理 |
| `GOST_REDIRECT_PORT` | `12345` | redirect 目标端口 |

**iptables 排除列表（不会被透明代理劫持）：**

| CIDR | 说明 |
|---|---|
| `127.0.0.0/8` | 本地回环 |
| `10.0.0.0/8` | 内网 |
| `172.16.0.0/12` | Docker 内网 |
| `192.168.0.0/16` | 局域网 |
| `100.64.0.0/10` | WARP mesh 内网 |
| `162.159.0.0/16` | Cloudflare WARP 端点（兜底，覆盖 DoH + API + WireGuard） |
| 动态 WARP IP | 启动时自动获取的端点 IP |

> ⚠️ 如果自定义了 `WARP_ENDPOINT`，确保对应 IP 也在排除列表中（`162.159.0.0/16` 兜底已覆盖）。

---

## MDM 配置

MDM（Mobile Device Management）通过 XML 文件强制应用 Cloudflare Zero Trust 策略。本地设置优先级高于 Cloudflare Dashboard。

### 两种配置方式

**方式一：挂载 mdm.xml 文件（推荐）**

```yaml
volumes:
  - ./mdm.xml:/var/lib/cloudflare-warp/mdm.xml:ro
```

修改文件后 `docker compose restart` 即可生效。

**方式二：环境变量自动生成**

当没有挂载 mdm.xml 且设置了 `WARP_ORG` 或 `WARP_AUTH_CLIENT_ID` 时，自动生成。

### MDM 环境变量

| 变量 | 对应 mdm.xml 键 | 说明 |
|---|---|---|
| `WARP_ORG` | `organization` | Zero Trust 组织名（`<team>.cloudflareaccess.com` 中的 team） |
| `WARP_AUTH_CLIENT_ID` | `auth_client_id` | Service Token Client ID（需 device enrollment 权限） |
| `WARP_AUTH_CLIENT_SECRET` | `auth_client_secret` | Service Token Client Secret |
| `WARP_SERVICE_MODE` | `service_mode` | `warp`/`1dot1`/`proxy`/`postureonly`/`tunnelonly` |
| `WARP_TUNNEL_PROTOCOL` | `warp_tunnel_protocol` | `wireguard`/`masque` |
| `WARP_AUTO_CONNECT` | `auto_connect` | 自动重连间隔（分钟）：0=允许用户关闭，1-1440 |
| `WARP_SWITCH_LOCKED` | `switch_locked` | `true`=用户不能关闭客户端 |
| `WARP_OVERRIDE_ENDPOINT` | `override_warp_endpoint` | 强制 WireGuard 端点 `IP:PORT` |
| `WARP_OVERRIDE_DOH` | `override_doh_endpoint` | 强制 DoH 端点 IP |
| `WARP_OVERRIDE_API` | `override_api_endpoint` | 强制 API 端点 IP |
| `WARP_GATEWAY_ID` | `gateway_unique_id` | DNS Gateway 唯一 ID |
| `WARP_ENVIRONMENT` | `environment` | `normal`/`fedramp_high` |
| `WARP_POST_QUANTUM` | `enable_post_quantum` | `true`=启用后量子密码学 |
| `WARP_DISPLAY_NAME` | `display_name` | 设备显示名（多组织时需要） |
| `WARP_SUPPORT_URL` | `support_url` | 反馈 URL |

### mdm.xml 完整模板

参考 `examples/mdm.xml`，包含所有可用参数及注释。

---

## warp-cli 常用命令速查

### 连接管理

```bash
warp-cli --accept-tos status              # 查看连接状态
warp-cli --accept-tos connect             # 连接
warp-cli --accept-tos disconnect          # 断开
```

### 注册管理

```bash
warp-cli --accept-tos registration show          # 查看注册信息
warp-cli --accept-tos registration delete        # 删除注册
warp-cli --accept-tos connector new <token>      # 注册 Connector
```

### 隧道配置

```bash
warp-cli --accept-tos mode set warp              # 设置模式
warp-cli --accept-tos tunnel endpoint set IP:PORT  # 设置端点
warp-cli --accept-tos tunnel protocol set WireGuard  # 设置协议
warp-cli --accept-tos tunnel dump                # 查看路由表
```

### DNS 配置

```bash
warp-cli --accept-tos dns fallback add <domain>  # 添加 fallback 域名
warp-cli --accept-tos dns fallback list           # 列出 fallback 域名
warp-cli --accept-tos dns gateway-id <id>         # 指定 Gateway ID
```

### 调试

```bash
warp-cli --accept-tos debug network              # 网络信息（含 mesh IP）
warp-cli --accept-tos settings list              # 查看所有设置
warp-cli --accept-tos mdm get-configs            # 查看 MDM 配置
```

---

## 配置示例

### 最简 node（US VPS 落地）

```yaml
services:
  warp-mesh:
    image: warp-mesh:latest
    cap_add: [NET_ADMIN, SYS_MODULE]
    environment:
      - CONNECTOR_TOKEN=eyJ...
      - WARP_ROLE=node
    ports:
      - "1080:1080"
      - "8080:8080"
```

### 带认证 + 转发的 relay

```yaml
services:
  warp-mesh:
    image: warp-mesh:latest
    cap_add: [NET_ADMIN, SYS_MODULE]
    environment:
      - CONNECTOR_TOKEN=eyJ...
      - WARP_ROLE=relay
      - GOST_REMOTE=socks5://100.96.0.12:1080
      - GOST_USER=admin
      - GOST_PASS=secret123
    ports:
      - "1080:1080"
      - "8080:8080"
```

### 带透明代理的 client + MDM

```yaml
services:
  warp-mesh:
    image: warp-mesh:latest
    cap_add: [NET_ADMIN, SYS_MODULE]
    sysctls:
      - net.ipv4.ip_forward=1
    environment:
      - CONNECTOR_TOKEN=eyJ...
      - WARP_ROLE=client
      - GOST_REMOTE=socks5://100.96.0.12:1080
    volumes:
      - ./mdm.xml:/var/lib/cloudflare-warp/mdm.xml:ro
    network_mode: host
```

### 自定义端点 + WireGuard + 后量子

```yaml
services:
  warp-mesh:
    image: warp-mesh:latest
    cap_add: [NET_ADMIN, SYS_MODULE]
    environment:
      - CONNECTOR_TOKEN=eyJ...
      - WARP_ROLE=node
      - WARP_ENDPOINT=162.159.197.3:2408
      - WARP_PROTOCOL=WireGuard
      - WARP_ORG=my-team
      - WARP_POST_QUANTUM=true
    ports:
      - "1080:1080"
```
