#!/bin/sh
set -eu

# nanobot-overlay-entrypoint
#
# 容器默认以 root (UID 0) 运行，不会降权。
# 数据目录由 NANOBOT_HOME 环境变量指定，默认使用 $HOME/.nanobot (/root/.nanobot)。
# 启动时自动初始化：数据目录不存在则创建，配置不存在则运行 onboard。
#
# 当 RENDER=true 时，从 /app/render-config.json 初始化配置文件。

dir="$HOME/.nanobot"

# Render deploy 模式：从 render-config.json 初始化配置
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

# 确保数据目录存在且可写
if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
elif [ ! -w "$dir" ]; then
    chmod 755 "$dir"
fi

# 配置不存在时自动初始化（非交互），确保 gateway 等命令可直接运行
if [ ! -f "$dir/config.json" ]; then
    echo "[entrypoint] no config found — running onboard"
    nanobot onboard 2>&1
fi

exec nanobot "$@"
