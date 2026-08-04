#!/bin/sh
set -eu

# cli-proxy-api-overlay-entrypoint
#
# 容器默认以 root (UID 0) 运行，不会降权。
# 工作目录为 /CLIProxyAPI，上游已在此放入二进制与 config.example.yaml。
# 启动时自动初始化：config.yaml 不存在则从 config.example.yaml 拷贝；认证目录不存在则创建。
#
# 环境变量 CONFIG_PATH：
#   设为外部挂载的配置文件路径 → 通过 --config 显式指定，跳过自动 bootstrap。
#
# 环境变量 APT_MIRROR：
#   设为 "tuna"              → mirrors.tuna.tsinghua.edu.cn
#   设为 "aliyun"            → mirrors.aliyun.com
#   设为 "ustc"              → mirrors.ustc.edu.cn
#   设为完整 URL             → 使用自定义镜像
#   未设置或空值             → 保持镜像内默认源（Debian 官方）

workdir="/CLIProxyAPI"

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

# ── 配置 bootstrap ──────────────────────────────────────────────────
# 默认配置路径为工作目录下的 config.yaml，使二进制的 $wd/config.yaml 查找无需任何 flag。
config_path="${CONFIG_PATH:-}"

if [ -z "$config_path" ]; then
  # 未显式指定 CONFIG_PATH：首次启动从 config.example.yaml 初始化（幂等，不覆盖已存在/已挂载的配置）
  if [ ! -f "$workdir/config.yaml" ] && [ -f "$workdir/config.example.yaml" ]; then
    echo "[entrypoint] bootstrapping $workdir/config.yaml from config.example.yaml"
    cp "$workdir/config.example.yaml" "$workdir/config.yaml"
  fi
fi

# ── 认证目录 ────────────────────────────────────────────────────────
auth_dir="$HOME/.cli-proxy-api"
if [ ! -d "$auth_dir" ]; then
  mkdir -p "$auth_dir"
fi

# ── 启动服务 ────────────────────────────────────────────────────────
# 仅在显式指定 CONFIG_PATH 时通过 --config 传参；否则依赖默认 $wd/config.yaml 查找。
if [ -n "$config_path" ]; then
  exec /CLIProxyAPI/CLIProxyAPI --config "$config_path" "$@"
fi

exec /CLIProxyAPI/CLIProxyAPI "$@"
