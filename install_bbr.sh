#!/usr/bin/env bash
# ============================================================
#  BBR 一键开启脚本
#  支持系统: Alpine / Debian / Ubuntu (内核 >= 4.9)
#  仓库:     https://github.com/hytuytujyt/bbr_install
#  用法:     bash <(curl -fsSL https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh)
# ============================================================

# ---------- 颜色输出 ----------
if [ -t 1 ]; then
    C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_CYAN='\033[0;36m'; C_NONE='\033[0m'
else
    C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_NONE=''
fi

ok()   { echo -e "${C_GREEN}[ OK ]${C_NONE} $*"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_NONE} $*"; }
err()  { echo -e "${C_RED}[FAIL]${C_NONE} $*"; }
info() { echo -e "${C_CYAN}[INFO]${C_NONE} $*"; }

# ---------- 0. root 检查 ----------
if [ "$(id -u)" -ne 0 ]; then
    err "请使用 root 运行本脚本 (sudo bash install_bbr.sh)"
    exit 1
fi

# ---------- 1. 系统检测 ----------
if [ -r /etc/os-release ]; then
    . /etc/os-release
    SYS_ID="$ID"
else
    SYS_ID="unknown"
fi

case "$SYS_ID" in
    alpine)  SYS_NAME="Alpine Linux" ;;
    debian)  SYS_NAME="Debian" ;;
    ubuntu)  SYS_NAME="Ubuntu" ;;
    *)
        err "未识别的系统 (ID=$SYS_ID)，本脚本仅适配 Alpine / Debian / Ubuntu"
        exit 1
        ;;
esac
ok "检测到系统: $SYS_NAME"

# ---------- 2. 内核版本检查 (>= 4.9 才支持 BBR) ----------
KERNEL="$(uname -r)"
MAJOR="${KERNEL%%.*}"
REST="${KERNEL#*.}"
MINOR="${REST%%.*}"

if [ "$MAJOR" -lt 4 ] || { [ "$MAJOR" -eq 4 ] && [ "$MINOR" -lt 9 ]; }; then
    err "当前内核 $KERNEL 低于 4.9，不支持 BBR，请先升级内核或重装系统"
    exit 1
fi
ok "内核版本: $KERNEL (>= 4.9, 支持 BBR)"

# ---------- 3. 检查 BBR 是否可用, 必要时加载模块 ----------
if [ -d /sys/module/tcp_bbr ]; then
    ok "BBR 已编译进内核/已加载模块"
else
    AVAILABLE="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)"
    if echo "$AVAILABLE" | grep -qw bbr; then
        ok "内核已内置 BBR"
    else
        info "尝试加载 tcp_bbr 模块 ..."
        if modprobe tcp_bbr 2>/dev/null; then
            ok "tcp_bbr 模块加载成功"
        else
            err "内核未包含 BBR ($(uname -r))，无法开启，请升级内核或重装系统"
            exit 1
        fi
    fi
fi

# ---------- 4. 写入配置 ----------
SYSCTL_CONF="/etc/sysctl.d/99-bbr.conf"
mkdir -p /etc/sysctl.d

cat > "$SYSCTL_CONF" <<'EOF'
# BBR (Google 拥塞控制算法)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
ok "已写入配置 $SYSCTL_CONF"

# ---------- 5. 应用配置 ----------
if sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1; then
    ok "配置已生效"
else
    # 兜底: 部分精简系统 busybox sysctl 不支持 -p 文件, 逐个写入
    warn "sysctl -p 不可用, 尝试逐项设置 ..."
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || warn "fq 队列设置失败(不影响 BBR 主体)"
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || {
        err "BBR 设置失败"; exit 1; }
    ok "配置已生效 (逐项设置)"
fi

# ---------- 6. 验证 ----------
CUR="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
if [ "$CUR" = "bbr" ]; then
    echo
    ok "BBR 开启成功! 当前拥塞控制算法: $CUR"
    info "提示: BBR 仅对新建立的连接生效, 已连接的(如 SSH)重连后即可享受"
else
    err "验证失败: 当前算法为 $CUR, 期望 bbr"
    exit 1
fi

exit 0
