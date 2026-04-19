# warp-node - Cloudflare WARP Connector + GOST Proxy Server

SOCKS5/HTTP proxy server with Cloudflare WARP tunnel integration.

## Features

- Cloudflare WARP tunnel connection
- SOCKS5 proxy (port 1080)
- HTTP proxy (port 8080)
- GOST config file support (extensible)
- Mesh network integration (100.96.0.x)

## Quick Start

```bash
docker run -d --name warp-node --restart always --privileged --network host \
  -e CONNECTOR_TOKEN=your-token \
  -v warp-data:/var/lib/cloudflare-warp \
  chenlebs/warp-node:latest
```

## Environment Variables

### WARP Configuration

| Variable | Description | Required |
|---|---|---|
| `CONNECTOR_TOKEN` | Cloudflare Zero Trust Connector Token | **Yes** |
| `WARP_SLEEP` | Startup wait time (seconds) | No (default: 5) |
| `WARP_AUTO_CONNECT` | Auto connect WARP | No (default: true) |
| `WARP_MODE` | WARP mode (Warp/WarpWithDnsOverHttps) | No |
| `WARP_ENDPOINT` | Custom WARP endpoint | No |
| `WARP_PROTOCOL` | Tunnel protocol (WireGuard/MASQUE) | No |

### GOST Configuration

| Variable | Description | Default |
|---|---|---|
| `GOST_CONFIG` | Config file path | /etc/gost/gost.yaml |
| `GOST_BIND` | Bind address | 0.0.0.0 |
| `GOST_SOCKS_PORT` | SOCKS5 port | 1080 |
| `GOST_HTTP_PORT` | HTTP proxy port | 8080 |
| `GOST_USER` | Auth username | - |
| `GOST_PASS` | Auth password | - |

## Ports

- **SOCKS5**: 1080
- **HTTP**: 8080

## GOST Config File (Optional)

Mount custom config to /etc/gost/gost.yaml:

```yaml
services:
  - name: socks5-service
    addr: ":1080"
    handler:
      type: socks5
  - name: http-service
    addr: ":8080"
    handler:
      type: http

log:
  level: info
```

## Mesh Network

warp-node joins Cloudflare Zero Trust Mesh automatically. Mesh IP: 100.96.0.x

## docker-compose Example

```yaml
services:
  warp-node:
    image: chenlebs/warp-node:latest
    container_name: warp-node
    restart: unless-stopped
    privileged: true
    network_mode: host
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - warp-data:/var/lib/cloudflare-warp
      - ./gost.yaml:/etc/gost/gost.yaml
    environment:
      - CONNECTOR_TOKEN=your-token
      - WARP_AUTO_CONNECT=true
      - GOST_CONFIG=/etc/gost/gost.yaml

volumes:
  warp-data:
```

## Related Image

- **warp-client**: tungo transparent proxy client (chenlebs/warp-client)
