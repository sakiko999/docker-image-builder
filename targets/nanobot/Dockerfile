ARG BASE_IMAGE
FROM $BASE_IMAGE

ARG UPSTREAM_TAG
ARG UPSTREAM_SHA
ARG OVERLAY_SHA

LABEL org.opencontainers.image.source="https://github.com/HKUDS/nanobot"
LABEL org.opencontainers.image.version="$UPSTREAM_TAG"
LABEL org.opencontainers.image.revision="$UPSTREAM_SHA"
LABEL org.opencontainers.image.vendor="sakiko999"
LABEL io.github.sakiko999.nanobot.overlay-revision="$OVERLAY_SHA"

# 容器默认以 root 运行，不降权到 nanobot 用户。
# 入口点会自动管理数据目录的创建和权限。
USER root

# 设置 root 的 HOME，使得默认数据目录为 /root/.nanobot
ENV HOME=/root

# 保留上游的 Python 运行时环境配置
ENV PYTHONUNBUFFERED=1 PYTHONFAULTHANDLER=1

# 预装常用工具和运行时
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gpg \
      unzip \
      zip \
      jq \
      tmux && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
      gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get update && \
    apt-get install -y --no-install-recommends gh nodejs && \
    rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 targets/nanobot/entrypoint.sh /usr/local/bin/nanobot-overlay-entrypoint
COPY --chmod=0755 targets/nanobot/healthcheck.sh /usr/local/bin/nanobot-healthcheck
COPY targets/nanobot/config/ /opt/nanobot-overlay/config/

EXPOSE 18790
EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD ["/usr/local/bin/nanobot-healthcheck"]

ENTRYPOINT ["/usr/local/bin/nanobot-overlay-entrypoint"]
CMD ["gateway"]
