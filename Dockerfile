FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH

# 安装依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release dbus iproute2 iptables procps tini wget tar jq \
    && rm -rf /var/lib/apt/lists/*

# 安装 Cloudflare WARP CLI
RUN mkdir -p /usr/share/keyrings \
    && curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflare-client.list \
    && apt-get update && apt-get install -y cloudflare-warp \
    && rm -rf /var/lib/apt/lists/*

# 安装 Gost v3（动态获取最新版本）
RUN GOST_VERSION=$(curl -s https://api.github.com/repos/go-gost/gost/releases/latest | jq -r '.tag_name' | sed 's/^v//') \
    && arch="${TARGETARCH:-$(dpkg --print-architecture)}" \
    && case "$arch" in \
         amd64) gost_arch="amd64" ;; \
         arm64) gost_arch="arm64" ;; \
         *) echo "Unsupported: $arch" >&2; exit 1 ;; \
       esac \
    && wget -O /tmp/gost.tar.gz "https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_${gost_arch}.tar.gz" \
    && tar -xzf /tmp/gost.tar.gz -C /tmp \
    && install -m 0755 /tmp/gost /usr/local/bin/gost \
    && /usr/local/bin/gost -V \
    && rm -rf /tmp/gost.tar.gz /tmp/gost

# 复制文件
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 创建必要目录
RUN mkdir -p /var/lib/cloudflare-warp /run/dbus /etc/gost

EXPOSE 1080 8080

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]