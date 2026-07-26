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
#   未设置或为空 → 使用国内源 (mirrors.tuna.tsinghua.edu.cn)
#   设为 "original" → 还原为 Debian 官方源
#   设为镜像 URL  → 使用自定义源

dir="$HOME/.nanobot"

# ── apt 源切换 ──────────────────────────────────────────────────────
APT_SOURCES="/etc/apt/sources.list.d/debian.sources"
DEFAULT_MIRROR="mirrors.tuna.tsinghua.edu.cn"
APT_MIRROR="${APT_MIRROR:-$DEFAULT_MIRROR}"

case "$APT_MIRROR" in
  original|official|debian)
    cat > "$APT_SOURCES" <<-SOURCES
Types: deb
URIs: http://deb.debian.org/debian
Suites: bookworm bookworm-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian-security
Suites: bookworm-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCES
    ;;
  ?*)
    cat > "$APT_SOURCES" <<-SOURCES
Types: deb
URIs: https://${APT_MIRROR}/debian
Suites: bookworm bookworm-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://${APT_MIRROR}/debian-security
Suites: bookworm-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCES
    ;;
esac

# ── apt 兜底：清理残留锁和进程 ─────────────────────────────────────
for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock; do
  pids="$(lsof -t "$lock" 2>/dev/null || true)"
  if [ -n "$pids" ]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
done

python3 -c "
import os, glob
for f in glob.glob('/var/lib/dpkg/lock*') + glob.glob('/var/cache/apt/archives/lock*') + ['/var/lib/apt/lists/lock']:
    try:
        if os.path.exists(f): os.remove(f)
    except: pass
" 2>/dev/null || true

dpkg --configure -a 2>/dev/null || true

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
