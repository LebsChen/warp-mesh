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
client (本地) ──mesh──→ relay (中转) ──mesh──→ node (落地) → 外网
                       ↘ node2 ──mesh──→ node2 (落地) → 外网2
```

```
VM102 (client)  ──mesh──→  VM101 (relay)  ──mesh──→  US VPS (node)
127.0.0.1:1080            0.0.0.0:1080             0.0.0.0:1080
         GOST_REMOTE→              GOST_REMOTE→
         100.96.0.16:1080          100.96.0.12:1080
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
echo "NEXT_HOP=100.96.0.12:1080" > .env  # node 的 mesh IP
docker compose up -d
```

### 4. 部署 client (本地)

```bash
cd examples/warp-client
export CONNECTOR_TOKEN="your-token"
echo "NEXT_HOP=100.96.0.16:1080" > .env  # relay 的 mesh IP
docker compose up -d
```

### 5. 测试

```bash
curl -4 -s --proxy socks5://127.0.0.1:1080 ifconfig.me
# 应返回 node 的出口 IP
```

## 工作原理

entrypoint.sh 根据角色和 `GOST_REMOTE` 环境变量动态生成 GOST v3 配置文件 (`/etc/gost/gost.yaml`)，然后启动 GOST。

**GOST 配置文件格式**（自动生成）：

```yaml
services:
  - name: socks5-service
    addr: ":1080"
    handler:
      type: socks5
      chain: gost-chain
    listener:
      type: tcp

chains:
  - name: gost-chain
    hops:
      - name: hop-remote
        nodes:
          - name: remote-node
            addr: 100.96.0.12:1080
            connector:
              type: socks5
            dialer:
              type: tcp
```

> ⚠️ **注意**：GOST v3 的 chain 配置中，hop 下必须用 `nodes` 数组，且用 `connector`/`dialer`（不是 `handler`/`listener`）。直接在 hop 下写 `addr`/`handler` 不会生效。

## 已知问题

1. **mesh IP 动态变化** — WARP 重新注册会分配新 IP，`GOST_REMOTE` 需更新
2. **WARP 连接不稳定** — 部分环境 WARP DNS (DoH) 超时
3. **旧 GOST 进程残留** — `network_mode: host` 下容器删除后进程可能残留，需 `kill $(pidof gost)`

## 项目结构

```
warp-mesh/
├── Dockerfile
├── entrypoint.sh               # 统一入口（动态生成 GOST 配置）
├── docker-compose.yaml         # 默认 node 角色
└── examples/
    ├── warp-node/compose.yaml  # 落地节点
    ├── warp-relay/compose.yaml # 中转节点
    └── warp-client/compose.yaml # 本地客户端
```

## License

Based on [warp-node](https://github.com/LebsChen/warp-node/) (MIT)
