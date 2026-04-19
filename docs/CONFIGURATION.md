# warp-mesh 配置参考

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

### WARP 运行模式 (`WARP_MODE`)

通过 `warp-cli mode set` 设置：

| 值 | 说明 |
|---|---|
| `warp` | 建立 WARP 隧道 + UDP DNS 代理（默认） |
| `doh` | 不建立隧道，仅代理 DNS over HTTPS |
| `warp+doh` | 建立隧道 + DoH DNS |
| `dot` | 不建立隧道，仅代理 DNS over TLS |
| `warp+dot` | 建立隧道 + DoT DNS |
| `proxy` | 建立隧道用于 SOCKS5 代理 |
| `tunnel_only` | 建立隧道，不代理 DNS |

### WARP 隧道配置

| 变量 | 对应命令 | 说明 |
|---|---|---|
| `WARP_ENDPOINT` | `tunnel endpoint set` | 强制指定 WireGuard 端点 IP:PORT |
| `WARP_PROTOCOL` | `tunnel protocol set` | 隧道协议：`WireGuard` 或 `MASQUE` |
| `WARP_VNET` | `vnet set` | 指定虚拟网络 |

### Split Tunnel（分流隧道）

> ⚠️ Zero Trust 环境下由 Dashboard 策略控制，CLI 无法直接修改。
> 以下仅对 Consumer 模式有效。

- `warp-cli tunnel ip add <ip>` — 添加 IP 到 split tunnel
- `warp-cli tunnel ip add-range <start> <end>` — 添加 IP 范围
- `warp-cli tunnel host add <domain>` — 添加域名

**当前策略**（从 Dashboard 下发）：
- Include 模式：只代理 `100.96.0.0/16`（mesh 内网）
- 所有其他流量不走 WARP 隧道

### DNS 配置

| 命令 | 说明 |
|---|---|
| `warp-cli dns fallback add <domain>` | 添加 fallback 域名 |
| `warp-cli dns fallback list` | 列出 fallback 域名 |
| `warp-cli dns gateway-id <id>` | 指定 Gateway ID |
| `warp-cli dns log enable/disable` | 启用/禁用 DNS 日志 |

**当前 fallback 域名**（自动配置）：home.arpa, intranet, internal, private, localdomain, domain, lan, home, host, corp, local, localhost, invalid, test

### Proxy 模式

| 变量 | 对应命令 | 说明 |
|---|---|---|
| `WARP_PROXY_PORT` | `proxy port` | WARP 内置 SOCKS5 代理端口（仅 proxy 模式） |

### GOST 代理

| 变量 | 默认 | 适用角色 | 说明 |
|---|---|---|---|
| `GOST_REMOTE` | — | 全部 | 转发目标，格式：`socks5://host:port` 或 `host:port` |
| `GOST_BIND` | `0.0.0.0` | node/relay | 监听地址 |
| `GOST_SOCKS_PORT` | `1080` | 全部 | SOCKS5 端口 |
| `GOST_HTTP_PORT` | `8080` | 全部 | HTTP 代理端口 |
| `GOST_USER` | — | node/relay | 认证用户名 |
| `GOST_PASS` | — | node/relay | 认证密码 |
| `GOST_LOCAL_BIND` | `127.0.0.1` | client | 本地监听地址 |
| `GOST_LOCAL_PORT` | `1080` | client | 本地 SOCKS5 端口 |
| `GOST_LOCAL_HTTP_PORT` | `8080` | client | 本地 HTTP 端口 |
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
| `162.159.0.0/16` | Cloudflare WARP 端点（DoH + API + WireGuard） |
| 动态 WARP IP | 自动获取的端点 IP |

> ⚠️ 如果自定义了 WARP_ENDPOINT，确保对应 IP 也在排除列表中。

---

## MDM 配置（高级）

MDM（Mobile Device Management）通过 XML 文件强制应用 Cloudflare Zero Trust 策略，不需要用户交互。

### mdm.xml 格式

```xml
<?xml version="1.0" encoding="UTF-8"?>
<config>
  <organization>your-org-name</organization>
  <token>your-mdm-token</token>
</config>
```

### MDM 支持的配置项

| 配置 | 说明 |
|---|---|
| `organization` | Zero Trust 组织名 |
| `token` | MDM 注册 Token（不同于 Connector Token） |
| `mode` | 强制运行模式 |
| `gateway-id` | DNS Gateway ID |
| `support-url` | 支持页面 URL |
| `allow-mode-switch` | 是否允许用户切换模式 |
| `allow-updates` | 是否允许自动更新 |
| `allow-leave-org` | 是否允许离开组织 |

### 环境变量

| 变量 | 说明 |
|---|---|
| `MDM_TOKEN` | MDM Token |
| `MDM_ORG` | 组织名 |

### 查看当前 MDM 配置

```bash
warp-cli --accept-tos mdm get-configs
warp-cli --accept-tos mdm refresh   # 刷新 MDM 配置
```

---

## warp-cli 常用命令速查

### 连接管理

```bash
warp-cli --accept-tos status          # 查看连接状态
warp-cli --accept-tos connect         # 连接
warp-cli --accept-tos disconnect      # 断开
```

### 注册管理

```bash
warp-cli --accept-tos registration show    # 查看注册信息
warp-cli --accept-tos registration delete  # 删除注册
warp-cli --accept-tos connector new <token>  # 注册 Connector
```

### 隧道配置

```bash
warp-cli --accept-tos tunnel endpoint set <ip:port>  # 设置端点
warp-cli --accept-tos tunnel protocol set WireGuard   # 设置协议
warp-cli --accept-tos tunnel dump                     # 查看路由表
warp-cli --accept-tos tunnel ip list                  # 查看分流 IP
warp-cli --accept-tos tunnel host list                # 查看分流域名
```

### 调试

```bash
warp-cli --accept-tos debug network           # 网络信息（含 mesh IP）
warp-cli --accept-tos debug connectivity-check enable   # 启用连通性检查
warp-cli --accept-tos settings list            # 查看所有设置
```

---

## 配置示例

### 最简 node（US VPS）

```yaml
services:
  warp-mesh:
    image: warp-mesh:latest
    environment:
      - CONNECTOR_TOKEN=eyJ...
      - WARP_ROLE=node
```

### 带认证 + 转发的 relay

```yaml
services:
  warp-mesh:
    image: warp-mesh:latest
    environment:
      - CONNECTOR_TOKEN=eyJ...
      - WARP_ROLE=relay
      - GOST_REMOTE=socks5://100.96.0.12:1080
      - GOST_USER=admin
      - GOST_PASS=secret123
```

### 自定义端点的 client

```yaml
services:
  warp-mesh:
    image: warp-mesh:latest
    environment:
      - CONNECTOR_TOKEN=eyJ...
      - WARP_ROLE=client
      - GOST_REMOTE=100.96.0.16:1080
      - WARP_ENDPOINT=162.159.197.3:2408
      - WARP_PROTOCOL=WireGuard
```

### 自定义 GOST 端口

```yaml
services:
  warp-mesh:
    image: warp-mesh:latest
    environment:
      - CONNECTOR_TOKEN=eyJ...
      - WARP_ROLE=node
      - GOST_SOCKS_PORT=1081
      - GOST_HTTP_PORT=8081
```
