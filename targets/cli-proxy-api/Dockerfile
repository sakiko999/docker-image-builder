ARG BASE_IMAGE
FROM $BASE_IMAGE

ARG UPSTREAM_TAG
ARG UPSTREAM_SHA
ARG OVERLAY_SHA

LABEL org.opencontainers.image.source="https://github.com/sakiko999/CLIProxyAPI"
LABEL org.opencontainers.image.version="$UPSTREAM_TAG"
LABEL org.opencontainers.image.revision="$UPSTREAM_SHA"
LABEL org.opencontainers.image.vendor="sakiko999"
LABEL io.github.sakiko999.cli-proxy-api.overlay-revision="$OVERLAY_SHA"

# 容器默认以 root 运行，不降权。
# 入口点会自动管理配置与认证目录的创建。
USER root

# 确定性 HOME：认证目录默认为 /root/.cli-proxy-api
ENV HOME=/root

# CLIProxyAPI 是 Go 编译的静态服务，运行时仅需 curl 做健康检查。
# 不预装 node/gh/tmux 等——上游 base（debian:bookworm）已含 tzdata/ca-certificates。
# 体积增量 <1MB，与上游官方镜像保持接近。
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 targets/cli-proxy-api/entrypoint.sh /usr/local/bin/cli-proxy-api-overlay-entrypoint
COPY --chmod=0755 targets/cli-proxy-api/healthcheck.sh /usr/local/bin/cli-proxy-api-healthcheck
COPY targets/cli-proxy-api/config/ /opt/cli-proxy-api-overlay/config/

EXPOSE 8317
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD ["/usr/local/bin/cli-proxy-api-healthcheck"]

ENTRYPOINT ["/usr/local/bin/cli-proxy-api-overlay-entrypoint"]
CMD []
