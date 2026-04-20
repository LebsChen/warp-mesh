# warp-mesh

Cloudflare WARP Mesh 网络 + GOST 代理链。统一镜像，三种角色，一个 `entrypoint.sh` 搞定。

## 角色

| 角色 | 说明 | GOST 监听 | 转发 | 透明代理 |
|---|---|---|---|---|
| **node** (落地) | 公网出口，接受 mesh 连入 | `0.0.0.0:1080/8080` | 可选 | ❌ |
| **relay** (中转) | 接受连入，转发到下一跳 | `0.0.0.0:1080/8080` | ✅ | ❌ |
| **client** (本地) | 本地/局域网代理客户端 | `0.0.0.0:1080/8080` | ✅ | ✅ 默认启用 |

## 典型拓扑

```
client (本地/局域网)          relay (国内中转)          node (US VPS 落地)
0.0.0.0:1080/8080            0.0.0.0:1080/8080         0.0.0.0:1080/8080
透明代理 ✅                   GOST_REMOTE →             出口 → 外网
GOST_REMOTE →                100.96.0.12:1080
100.96.0.16:1080
```

## 特性

- **统一镜像**：三种角色通过 `WARP_ROLE` 环境变量区分
- **MDM 支持**：挂载 `mdm.xml` 或通过环境变量自动生成
- **透明代理**：client 默认 iptables 劫持所有 TCP → GOST，自动排除 WARP 端点 IP
- **优雅退出**：`docker stop` 自动断开 WARP → 停止 GOST → 清理 iptables → 停止 warp-svc
- **认证**：node/relay 可配置 SOCKS5/HTTP 代理认证

## 快速开始

### Docker Pull

```bash
docker pull chenlebs/warp-mesh:latest
```

### Docker Run

**Node（落地节点，公网出口）：**

```bash
docker run -d --name warp-mesh --restart unless-stopped \
  --cap-add NET_ADMIN --cap-add SYS_MODULE \
  --device /dev/net/tun:/dev/net/tun \
  -e CONNECTOR_TOKEN=your_token_here \
  -e WARP_ROLE=node \
  -p 1080:1080 -p 8080:8080 \
  chenlebs/warp-mesh:latest
```

**Relay（中转节点，转发到下一跳）：**

```bash
docker run -d --name warp-mesh --restart unless-stopped \
  --cap-add NET_ADMIN --cap-add SYS_MODULE \
  --device /dev/net/tun:/dev/net/tun \
  -e CONNECTOR_TOKEN=your_token_here \
  -e WARP_ROLE=relay \
  -e GOST_REMOTE=socks5://100.96.0.41:1080 \
  -p 1080:1080 -p 8080:8080 \
  chenlebs/warp-mesh:latest
```

**Client（本地透明代理，host 网络）：**

```bash
docker run -d --name warp-mesh --restart unless-stopped \
  --cap-add NET_ADMIN --cap-add SYS_MODULE \
  --device /dev/net/tun:/dev/net/tun \
  --network host \
  -e CONNECTOR_TOKEN=your_token_here \
  -e WARP_ROLE=client \
  -e GOST_REMOTE=socks5://100.96.0.42:1080 \
  chenlebs/warp-mesh:latest
```

> 首次启动后查看 mesh IP：`docker logs warp-mesh 2>&1 | grep "v4"`
> 然后填入下游节点的 `GOST_REMOTE`，重启即可。

### Docker Compose

使用 `init.sh` 生成配置，再用 compose 部署（推荐，支持配置持久化）：

```bash
# 生成 gost.yaml 配置
bash init.sh node                  # 或 relay/client + GOST_REMOTE

# 启动
docker compose up -d
```

各角色示例 compose 文件见 `examples/` 目录。

### 停止

```bash
docker stop warp-mesh && docker rm warp-mesh
# 自动：断开 WARP → 停止 GOST → 清理 iptables → 停止 warp-svc
```



### 必需

| 变量 | 说明 |
|---|---|
| `CONNECTOR_TOKEN` | Cloudflare Zero Trust Connector Token（从 Dashboard 获取） |
| `WARP_ROLE` | 角色：`node` / `relay` / `client` |

### GOST 代理

| 变量 | 默认 | 适用角色 | 说明 |
|---|---|---|---|
| `GOST_REMOTE` | — | relay, client | 转发目标，如 `socks5://100.96.0.12:1080` |
| `GOST_BIND` | `0.0.0.0` | node, relay | 监听地址 |
| `GOST_SOCKS_PORT` | `1080` | 全部 | SOCKS5 端口 |
| `GOST_HTTP_PORT` | `8080` | 全部 | HTTP 代理端口 |
| `GOST_USER` | — | node, relay | 认证用户名 |
| `GOST_PASS` | — | node, relay | 认证密码 |
| `GOST_LOCAL_BIND` | `0.0.0.0` | client | client 监听地址 |
| `GOST_LOCAL_PORT` | `1080` | client | client SOCKS5 端口 |
| `GOST_LOCAL_HTTP_PORT` | `8080` | client | client HTTP 端口 |

### WARP 连接

| 变量 | 默认 | 说明 |
|---|---|---|
| `WARP_AUTO_CONNECT` | `true` | 是否自动连接 |
| `WARP_SLEEP` | `5` | warp-svc 启动等待秒数 |
| `WARP_MODE` | — | 运行模式：`warp`/`doh`/`warp+doh`/`dot`/`warp+dot`/`proxy`/`tunnel_only` |
| `WARP_ENDPOINT` | — | 强制端点 IP:PORT |
| `WARP_PROTOCOL` | — | 隧道协议：`WireGuard`/`MASQUE` |

### 透明代理（client 默认启用）

| 变量 | 默认 | 说明 |
|---|---|---|
| `WARP_TRANSPARENT` | `true`(client) | 启用 iptables 透明代理 |
| `GOST_REDIRECT_PORT` | `12345` | redirect 目标端口 |

**自动排除的流量（不会被劫持）：**

| CIDR | 说明 |
|---|---|
| `127.0.0.0/8` | 本地回环 |
| `10.0.0.0/8` | 内网 |
| `172.16.0.0/12` | Docker 内网 |
| `192.168.0.0/16` | 局域网 |
| `100.64.0.0/10` | WARP mesh 内网 |
| `162.159.0.0/16` | Cloudflare WARP 端点（兜底） |
| 动态 WARP IP | 启动时自动获取 |

> ⚠️ **警告**：透明代理会劫持所有 TCP 出口流量到 GOST。如果 GOST 链路不通，所有 TCP 连接都会失败！

### MDM 配置

两种方式（二选一）：

**方式一：挂载 mdm.xml（推荐）**

```yaml
volumes:
  - ./mdm.xml:/var/lib/cloudflare-warp/mdm.xml:ro
```

参考 `examples/mdm.xml` 模板，支持的配置项：`organization`、`auth_client_id/secret`、`service_mode`、`warp_tunnel_protocol`、`auto_connect`、`switch_locked`、`override_warp_endpoint`、`gateway_unique_id`、`enable_post_quantum` 等。

**方式二：环境变量自动生成**

| 变量 | 对应 mdm.xml 键 | 说明 |
|---|---|---|
| `WARP_ORG` | `organization` | Zero Trust 组织名 |
| `WARP_AUTH_CLIENT_ID` | `auth_client_id` | Service Token Client ID |
| `WARP_AUTH_CLIENT_SECRET` | `auth_client_secret` | Service Token Client Secret |
| `WARP_SERVICE_MODE` | `service_mode` | 运行模式 |
| `WARP_TUNNEL_PROTOCOL` | `warp_tunnel_protocol` | 隧道协议 |
| `WARP_OVERRIDE_ENDPOINT` | `override_warp_endpoint` | 端点覆盖 |
| `WARP_GATEWAY_ID` | `gateway_unique_id` | DNS Gateway ID |
| `WARP_ENVIRONMENT` | `environment` | `normal`/`fedramp_high` |
| `WARP_POST_QUANTUM` | `enable_post_quantum` | 后量子密码学 |
| `WARP_DISPLAY_NAME` | `display_name` | 设备显示名 |

## 启动流程

```
entrypoint.sh
  │
  ├─ 1. dbus + warp-svc 启动
  ├─ 2. MDM 配置（挂载文件 或 环境变量生成）
  ├─ 3. WARP Connector 注册
  ├─ 4. WARP 可选配置（mode/endpoint/protocol）
  ├─ 5. WARP 连接
  ├─ 6. Mesh 路由（100.96.0.0/16 → CloudflareWARP）
  ├─ 7. GOST 代理（动态生成配置）
  ├─ 8. iptables 透明代理（client 默认启用）
  └─ 9. 信号监听（SIGTERM → 优雅退出）
```

**优雅退出（`docker stop`）：**

```
SIGTERM 收到
  ├─ warp-cli disconnect    断开 WARP
  ├─ kill GOST              停止代理
  ├─ 清理 iptables          删除 GOST_TRANSPARENT 链
  └─ pkill warp-svc         停止后台服务
```

## 项目结构

```
warp-mesh/
├── Dockerfile                  # 统一镜像（debian + warp + gost）
├── entrypoint.sh               # 统一入口（三种角色 + 优雅退出）
├── docker-compose.yaml         # 默认 node 角色
├── docs/
│   └── CONFIGURATION.md        # 完整配置参考
├── examples/
│   ├── mdm.xml                 # MDM 配置模板
│   ├── warp-node/compose.yaml  # 落地节点
│   ├── warp-relay/compose.yaml # 中转节点
│   └── warp-client/compose.yaml # 本地客户端（host 网络）
└── README.md
```

## 注意事项

- **Mesh IP 稳定性**：WARP Connector mesh IP（100.96.x.x）由 Cloudflare 自动分配。docker compose restart 和 warp-cli disconnect/connect IP 不变。只有删除 volume 后重建（新注册）才会变。示例 compose 已配置 warp-data volume 持久化 /var/lib/cloudflare-warp
- **首次部署**：首次 docker compose up 后查看日志获取 mesh IP：docker logs warp-mesh 2>&1 | grep v4，然后填入下游节点的 GOST_REMOTE
- **GOST_REMOTE 格式**：支持 [protocol://][user:pass@]host:port，如 socks5://001:password@100.96.0.42:1080。纯数字用户名会被 YAML 误解析为八进制，已自动加引号处理
- **client 用 `network_mode: host`**：透明代理和局域网可达都需要 host 网络
- **GOST 配置格式**：chain 中 hop 下必须用 `nodes` 数组 + `connector`/`dialer`（不是 `handler`/`listener`）
- **旧进程残留**：`network_mode: host` 下容器异常退出可能残留 GOST 进程，需 `kill $(pidof gost)`

## License

Based on [warp-node](https://github.com/LebsChen/warp-node/) (MIT)
