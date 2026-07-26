#!/bin/sh
set -eu

# nanobot-overlay-entrypoint
#
# 容器默认以 root (UID 0) 运行，不会降权。
# 数据目录由 NANOBOT_HOME 环境变量指定，默认使用 $HOME/.nanobot (/root/.nanobot)。
# 启动时自动初始化：数据目录不存在则创建，配置不存在则运行 onboard。
#
# 当 RENDER=true 时，从 /app/render-config.json 初始化配置文件。
#
# 环境变量 APT_MIRROR：
#   设为 "tuna"              → mirrors.tuna.tsinghua.edu.cn
#   设为 "aliyun"            → mirrors.aliyun.com
#   设为 "ustc"              → mirrors.ustc.edu.cn
#   设为完整 URL             → 使用自定义镜像
#   未设置或空值             → 保持镜像内默认源（Debian 官方）

dir="$HOME/.nanobot"

# ── apt 源切换 ──────────────────────────────────────────────────────
APT_SOURCES="/etc/apt/sources.list.d/debian.sources"
case "${APT_MIRROR:-}" in
  tuna)     APT_MIRROR_URL="mirrors.tuna.tsinghua.edu.cn" ;;
  aliyun)   APT_MIRROR_URL="mirrors.aliyun.com" ;;
  ustc)     APT_MIRROR_URL="mirrors.ustc.edu.cn" ;;
  ?*)       APT_MIRROR_URL="$APT_MIRROR" ;;
esac

if [ -n "${APT_MIRROR_URL:-}" ]; then
  cat > "$APT_SOURCES" <<-SOURCES
Types: deb
URIs: https://${APT_MIRROR_URL}/debian
Suites: bookworm bookworm-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://${APT_MIRROR_URL}/debian-security
Suites: bookworm-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCES
fi

# ── Render deploy 模式 ──────────────────────────────────────────────
if [ "${RENDER:-}" = "true" ]; then
    echo "[entrypoint] Render deploy — starting as $(id)"
    mkdir -p "$dir" || echo "[entrypoint] warning: mkdir $dir failed"
    config="$dir/config.json"
    if [ ! -f "$config" ]; then
        echo "[entrypoint] initializing $config from render-config.json"
        cp /app/render-config.json "$config" || echo "[entrypoint] warning: cp config failed"
    else
        echo "[entrypoint] existing $config found — leaving it in place"
    fi
    set -- "$@" --config "$config"
fi

# ── 数据目录 ────────────────────────────────────────────────────────
if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
elif [ ! -w "$dir" ]; then
    chmod 755 "$dir"
fi

# ── 自动初始化 ──────────────────────────────────────────────────────
if [ ! -f "$dir/config.json" ]; then
    echo "[entrypoint] no config found — running onboard"
    nanobot onboard 2>&1
fi

exec nanobot "$@"
