#!/bin/sh
set -eu

# nanobot-overlay-entrypoint
#
# 容器默认以 root (UID 0) 运行，不会降权。
# 数据目录由 NANOBOT_HOME 环境变量指定，默认使用 $HOME/.nanobot (/root/.nanobot)。
# 如果数据目录不存在，将自动创建。
#
# 当 RENDER=true 时（Render 部署平台），从 /app/render-config.json 初始化
# 配置文件到数据目录，并附加 --config 参数。

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

# 非 Render 模式：确保数据目录存在且可写
if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
elif [ ! -w "$dir" ]; then
    chmod 755 "$dir"
fi

exec nanobot "$@"
