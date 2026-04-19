# warp-mesh

Cloudflare WARP mesh 网络 + GOST 代理链，统一镜像，三种角色。

## 角色

| 角色 | 说明 | GOST 监听 | GOST 转发 |
|---|---|---|---|
| **node** (落地) | 有公网出口，接受 mesh 连入 | ✅ 0.0.0.0:1080/8080 | 可选 → 下一跳 |
| **relay** (中转) | 接受连入并转发到下一跳 | ✅ 0.0.0.0:1080/8080 | ✅ → 下一跳 |
| **client** (本地) | 本地代理客户端 | ✅ 127.0.0.1:1080/8080 | ✅ → 下一跳 |

## 典型拓扑

```
client → relay → node → 外网
                ↘ node2 → 外网2
```

```
VM102 (client)  ──mesh──→  VM101 (relay)  ──mesh──→  US VPS (node)
127.0.0.1:1080            0.0.0.0:1080             0.0.0.0:1080
                          转发→US VPS              直连出口
```

## 环境变量

### 必需

| 变量 | 说明 |
|---|---|
| `CONNECTOR_TOKEN` | Cloudflare Zero Trust Connector Token |

### 角色

| 变量 | 默认 | 说明 |
|---|---|---|
| `WARP_ROLE` | `node` | `node` / `relay` / `client` |

### GOST 代理

| 变量 | 默认 | 说明 |
|---|---|---|
| `GOST_REMOTE` | — | 转发目标，如 `socks5://100.96.0.12:1080` 或 `100.96.0.12:1080` |
| `GOST_BIND` | `0.0.0.0` | node/relay 监听地址 |
| `GOST_SOCKS_PORT` | `1080` | SOCKS5 端口 |
| `GOST_HTTP_PORT` | `8080` | HTTP 代理端口 |
| `GOST_USER` | — | 认证用户名 |
| `GOST_PASS` | — | 认证密码 |
| `GOST_LOCAL_BIND` | `127.0.0.1` | client 监听地址 |
| `GOST_LOCAL_PORT` | `1080` | client SOCKS5 端口 |
| `GOST_LOCAL_HTTP_PORT` | `8080` | client HTTP 端口 |

### 透明代理（仅 client，⚠️ 谨慎启用）

| 变量 | 默认 | 说明 |
|---|---|---|
| `WARP_TRANSPARENT` | `false` | 启用 iptables 透明代理 |
| `GOST_REDIRECT_PORT` | `12345` | 透明代理 redirect 端口 |

> ⚠️ **警告**：透明代理会劫持所有 TCP 出口流量到 GOST。如果 GOST 链路不通，所有 TCP 连接都会失败！

### WARP

| 变量 | 默认 | 说明 |
|---|---|---|
| `WARP_AUTO_CONNECT` | `true` | 自动 connect |
| `WARP_SLEEP` | `5` | warp-svc 启动等待秒数 |

## 快速开始

### 1. 构建

```bash
docker build -t warp-mesh:latest .
```

### 2. 部署 node (US VPS)

```bash
cd examples/warp-node
export CONNECTOR_TOKEN="your-token"
# 直接用，不转发
docker compose up -d
```

### 3. 部署 relay (国内中转)

```bash
cd examples/warp-relay
export CONNECTOR_TOKEN="your-token"
# .env 文件设置 NEXT_HOP 为 node 的 mesh IP
echo "NEXT_HOP=100.96.0.12:1080" > .env
docker compose up -d
```

### 4. 部署 client (本地)

```bash
cd examples/warp-client
export CONNECTOR_TOKEN="your-token"
# .env 文件设置 NEXT_HOP 为 relay 的 mesh IP
echo "NEXT_HOP=100.96.0.16:1080" > .env
docker compose up -d
```

### 5. 测试

```bash
# 在 client 机器上
curl -4 -s --proxy socks5://127.0.0.1:1080 ifconfig.me
# 应返回 node 的出口 IP
```

## 已知问题

1. **mesh IP 动态变化** — 每次 WARP 重新注册会分配新的 mesh IP，`GOST_REMOTE` 中的 IP 需要更新
2. **WARP 连接不稳定** — 部分 VM 上 WARP DNS (DoH) 可能超时，导致 WARP 卡在 Connecting
3. **GOST 配置文件 chain 不生效** — GOST v3.x 配置文件的 chain/forward 功能有 bug，已改用命令行 `-F` 参数
4. **旧 GOST 进程残留** — `network_mode: host` 下，容器删除后 GOST 进程可能仍在宿主机运行，需手动 `kill`

## 项目结构

```
warp-mesh/
├── Dockerfile
├── entrypoint.sh
├── docker-compose.yaml         # 默认 node 角色
└── examples/
    ├── warp-node/compose.yaml  # 落地节点
    ├── warp-relay/compose.yaml # 中转节点
    └── warp-client/compose.yaml # 本地客户端
```

## License

Based on [warp-node](https://github.com/LebsChen/warp-node/) (MIT)
