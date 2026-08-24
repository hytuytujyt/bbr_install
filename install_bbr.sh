#!/bin/sh
# =====================================================================
#  install_bbr.sh (单文件自举版)
#  兼容 Alpine / Debian / Ubuntu (内核 >= 4.9)
#
#  支持两种执行方式:
#    1) 已有本地文件:  sh install_bbr.sh
#    2) 管道直接喂:    wget -qO- <URL> | ... sh
#                      curl -fsSL <URL> | ... sh
#                      busybox wget -qO- <URL> | ... sh   (Alpine等精简系统兜底)
#  无论哪种,脚本都会自动补齐 bash/curl,再自动用 bash 自举执行正文。
# =====================================================================

SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh}"

# ---------- 简易打印工具(供引导段与正文共用) ----------
# 用 printf 替代 echo 传递多行,统一错误输出到 stderr
_info() { printf '%s\n' "[*] $*"; }
_ok()   { printf '%s\n' "[✓] $*"; }
_err()  { printf '%s\n' "[!] $*" >&2; }
_cmd()  { command -v "$1" >/dev/null 2>&1; }

if [ -z "${BASH_VERSION:-}" ]; then
  # ---------------------------------------------------------------
  #  引导段 (POSIX sh 兼容,可使 busybox ash 运行)
  # ---------------------------------------------------------------

  _need_install=""
  _cmd bash || _need_install="$_need_install bash"
  _cmd curl || _need_install="$_need_install curl"

  if [ -n "$_need_install" ]; then
    _err "检测到缺少依赖:$_need_install"
    _info "开始自动安装缺少的依赖 ..."
    if _cmd apk; then                                 # Alpine
      _info "使用 apk 安装"
      apk update && apk add --no-cache bash curl
    elif _cmd apt-get; then                           # Debian / Ubuntu
      export DEBIAN_FRONTEND=noninteractive
      _info "使用 apt-get 安装"
      apt-get update
      apt-get install -y bash curl
    elif _cmd dnf; then                               # Fedora / RHEL9+ / Rocky / Alma
      _info "使用 dnf 安装"
      dnf makecache
      dnf install -y bash curl
    elif _cmd yum; then                               # CentOS7 / RHEL7
      _info "使用 yum 安装"
      yum install -y bash curl
    elif _cmd zypper; then                            # openSUSE / SLES
      _info "使用 zypper 安装"
      zypper --non-interactive install bash curl
    elif _cmd pacman; then                            # Arch
      _info "使用 pacman 安装"
      pacman -Sy --noconfirm bash curl
    else
      _err "未识别的包管理器。"
      _err "请手动安装 bash 和 curl,然后重新执行本脚本。"
      _err "   - Alpine:  apk add bash curl"
      _err "   - Debian/Ubuntu:  apt-get install -y bash curl"
      exit 1
    fi
    # 复查
    _cmd bash || { _err "bash 仍未安装成功,请手动排查后重试"; exit 1; }
    _cmd curl || { _err "curl 仍未安装成功,请手动排查后重试"; exit 1; }
    _ok "依赖安装完成"
  else
    _ok "bash / curl 均已就绪"
  fi

  # 用 bash 重新执行本脚本(正文是 bash 语法)
  if [ -n "$0" ] && [ -f "$0" ]; then
    exec bash "$0" "$@"
  else
    _info "管道模式下自举:下载脚本交 bash 执行 ..."
    _tmp_self="/tmp/install_bbr_bootstrap.sh"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --connect-timeout 10 -m 60 "$SCRIPT_URL" -o "$_tmp_self" || { _err "拉取脚本失败(使用 curl): $SCRIPT_URL"; exit 1; }
    elif command -v wget >/dev/null 2>&1; then
      wget -q -T 15 -O "$_tmp_self" "$SCRIPT_URL" || { _err "拉取脚本失败(使用 wget): $SCRIPT_URL"; exit 1; }
    elif command -v busybox >/dev/null 2>&1; then
      busybox wget -q -T 15 -O "$_tmp_self" "$SCRIPT_URL" || { _err "拉取脚本失败(使用 busybox wget): $SCRIPT_URL"; exit 1; }
    else
      _err "需要 curl / wget / busybox 之一才能自举拉取脚本。"
      _err "请先安装其中之一,或将脚本下载到本地后执行: sh install_bbr.sh"
      exit 1
    fi
    exec bash "$_tmp_self" "$@"
  fi
fi

# =====================================================================
#  正文段 (此时已在 bash 下运行)
# =====================================================================
set -euo pipefail

_info2() { printf '%s\n' "[*] $*"; }
_ok2()   { printf '%s\n' "[✓] $*"; }
_err2()  { printf '%s\n' "[!] $*" >&2; }
_warn2() { printf '%s\n' "[!] $*" >&2; }

### 0. root 检查 ###
if [ "$(id -u)" -ne 0 ]; then
  _err2 "请使用 root 运行本脚本 (sudo sh install_bbr.sh)"
  exit 1
fi

### 1. 系统检测 ###
if [ -r /etc/os-release ]; then
  . /etc/os-release
  SYS_ID="${ID:-unknown}"
else
  SYS_ID="unknown"
fi

case "$SYS_ID" in
  alpine)  SYS_NAME="Alpine Linux" ;;
  debian)  SYS_NAME="Debian" ;;
  ubuntu)  SYS_NAME="Ubuntu" ;;
  *)
    _err2 "未识别的系统 (ID=$SYS_ID)，本脚本仅适配 Alpine / Debian / Ubuntu"
    exit 1
    ;;
esac
_ok2 "检测到系统: $SYS_NAME"

### 2. 内核版本检查 (>= 4.9 才支持 BBR) ###
KERNEL="$(uname -r)"
MAJOR="${KERNEL%%.*}"
REST="${KERNEL#*.}"
MINOR="${REST%%.*}"

if [ "$MAJOR" -lt 4 ] || { [ "$MAJOR" -eq 4 ] && [ "$MINOR" -lt 9 ]; }; then
  _err2 "当前内核 $KERNEL 低于 4.9，不支持 BBR，请先升级内核或重装系统"
  exit 1
fi
_ok2 "内核版本: $KERNEL (>= 4.9, 支持 BBR)"

### 3. 检查 BBR 是否可用, 必要时加载模块 ###
bbr_available() {
  [ -d /sys/module/tcp_bbr ] && return 0
  sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr
}

if bbr_available; then
  _ok2 "内核已支持 BBR"
else
  _info2 "尝试加载 tcp_bbr 模块 ..."
  if modprobe tcp_bbr 2>/dev/null && bbr_available; then
    _ok2 "tcp_bbr 模块加载成功"
  else
    # 容器(如 Docker/LXC)内无法 modprobe, 但内核可能本就支持 BBR,
    # 改为直接实测设置, 内核真不支持时 sysctl 会报 Invalid argument
    _warn2 "modprobe 不可用或失败(容器环境常见), 尝试直接设置 BBR ..."
    if sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
      _ok2 "直接设置 BBR 成功"
    else
      _err2 "内核不支持 BBR ($(uname -r))，无法开启"
      _err2 "提示: 若本机为容器(系统与内核不匹配), 需在宿主机执行 modprobe tcp_bbr 或升级宿主内核"
      exit 1
    fi
  fi
fi

### 4. 写入配置 ###
SYSCTL_CONF="/etc/sysctl.d/99-bbr.conf"
mkdir -p /etc/sysctl.d

# 检测内核是否支持 qdisc (net.core.default_qdisc 需要内核编译了 NET_SCHED;
# 部分商家精简内核砍掉了该子系统, 此时 fq 写不进去, 跳过即可, 不影响 BBR)
HAS_QDISC=0
sysctl -n net.core.default_qdisc >/dev/null 2>&1 && HAS_QDISC=1

{
  echo "# BBR (Google 拥塞控制算法)"
  if [ "$HAS_QDISC" = "1" ]; then
    echo "net.core.default_qdisc = fq"
  fi
  echo "net.ipv4.tcp_congestion_control = bbr"
  # 空闲后不重置慢启动, 保持原有速率(看视频/间歇性下载更流畅)
  echo "net.ipv4.tcp_slow_start_after_idle = 0"
} > "$SYSCTL_CONF"
_ok2 "已写入配置 $SYSCTL_CONF"
if [ "$HAS_QDISC" = "0" ]; then
  echo
  _warn2 "=============================================================="
  _warn2 "  此系统没有 fq 功能!"
  _warn2 "  原因: 当前内核未编译流量控制子系统(NET_SCHED),"
  _warn2 "        sysctl net.core.default_qdisc 不存在(会报 unknown key)。"
  _warn2 "  影响: 仅缺少 fq 队列, 不影响 BBR 本身, 可正常使用。"
  _warn2 "  注意: 无需再手动执行 sysctl net.core.default_qdisc 验证,"
  _warn2 "        该命令在本系统永远报错, 属正常现象。"
  _warn2 "  查看状态请用: bbrstatus (脚本已自动安装此命令)"
  _warn2 "=============================================================="
  echo
fi

### 5. 应用配置 ###
if sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1; then
  _ok2 "配置已生效"
else
  # 兜底: 部分精简系统 busybox sysctl 不支持 -p 文件, 逐个写入
  _warn2 "sysctl -p 不可用, 尝试逐项设置 ..."
  [ "$HAS_QDISC" = "1" ] && sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || \
    _warn2 "fq 队列设置失败/跳过(不影响 BBR 主体)"
  sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || { _err2 "BBR 设置失败"; exit 1; }
  sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1 || _warn2 "slow_start 设置失败(不影响 BBR 主体)"
  _ok2 "配置已生效 (逐项设置)"
fi

### 6. 验证 ###
echo
CUR="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
QDISC="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
SLOW="$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null || true)"

if [ "$CUR" = "bbr" ]; then
  _ok2 "拥塞控制算法: $CUR (期望 bbr) ✓"
else
  _err2 "拥塞控制算法: $CUR (期望 bbr) ✗"
  exit 1
fi

if [ "$HAS_QDISC" = "1" ]; then
  if [ "$QDISC" = "fq" ]; then
    _ok2 "队列调度: $QDISC (期望 fq) ✓"
  else
    _warn2 "队列调度: $QDISC (期望 fq, 不影响 BBR 主体)"
  fi
else
  _warn2 "内核不支持 fq(未编译 NET_SCHED), 已跳过, 不影响 BBR"
fi

if [ "$SLOW" = "0" ]; then
  _ok2 "空闲慢启动: 已关闭 (slow_start_after_idle=0) ✓"
else
  _warn2 "空闲慢启动: $SLOW (期望 0, 不影响 BBR 主体)"
fi

echo
_ok2 "BBR 开启成功!"
_info2 "提示: BBR 仅对新建立的连接生效, 已连接的(如 SSH)重连后即可享受"

### 7. 安装 bbrstatus 状态查看命令 (以后输入 bbrstatus 即可查看) ###
cat > /usr/local/bin/bbrstatus <<'EOF'
#!/bin/sh
# BBR 状态查看 (由 install_bbr.sh 自动生成)
CUR="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
QDISC="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
SLOW="$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null || true)"

echo "========== BBR 状态 =========="
if [ "$CUR" = "bbr" ]; then
  printf '[✓] 拥塞控制算法: %s (BBR 已开启)\n' "$CUR"
else
  printf '[!] 拥塞控制算法: %s (BBR 未开启)\n' "$CUR"
fi

if [ -n "$QDISC" ]; then
  if [ "$QDISC" = "fq" ]; then
    printf '[✓] 队列调度: %s (fq 正常)\n' "$QDISC"
  else
    printf '[!] 队列调度: %s (非 fq)\n' "$QDISC"
  fi
else
  printf '[!] 此系统没有 fq 功能 (内核未编译 NET_SCHED), 不影响 BBR\n'
fi

if [ "$SLOW" = "0" ]; then
  printf '[✓] 空闲慢启动: 已关闭 (slow_start_after_idle=0)\n'
else
  printf '[!] 空闲慢启动: %s (期望 0)\n' "$SLOW"
fi
EOF
chmod +x /usr/local/bin/bbrstatus 2>/dev/null || _warn2 "无法安装 bbrstatus 命令"
_ok2 "已安装状态命令: bbrstatus (随时输入查看 BBR 状态)"

### 8. 关闭密码登录 ###
# 说明: 运行本脚本前请先用 SSH 私钥确认能登录(公钥已在 authorized_keys 中)。
# 本脚本只关闭密码登录, 不做私钥存在性检查(由运行者预先确认)。
disable_password_login() {
  _info2 "检查是否可以安全关闭密码登录 ..."

  local conf_file="/etc/ssh/sshd_config"
  local drop_dir="/etc/ssh/sshd_config.d"
  local drop_file="$drop_dir/00-disable-password.conf"
  local include_line="Include ${drop_dir}/*.conf"

  # --- ① 写入最优先的 drop-in(00- 确保 first-match-wins 生效) ---
  # OpenSSH 的 sshd_config 是"先出现的值生效"(first-match-wins)。
  # 很多系统(Debian/Ubuntu)会在 sshd_config.d/*.conf 放 PasswordAuthentication yes,
  # 排在前面, 手写的 no 会被静默覆盖。写入排序最靠前的 00-, 让 no 最先生效。
  mkdir -p "$drop_dir"
  printf '%s\n' \
    "PasswordAuthentication no" \
    "KbdInteractiveAuthentication no" \
    "ChallengeResponseAuthentication no" > "$drop_file"
  _ok2 "已写入 $drop_file"

  # --- ② 确保主配置在最顶 include 该目录(Alpine/老系统可能没有) ---
  if ! grep -qE "^[[:space:]]*Include .*sshd_config\.d" "$conf_file" 2>/dev/null; then
    _info2 "主配置缺少 include 语句, 在最顶部补上 ..."
    local tmp_conf="/tmp/sshd_config.$$"
    {
      echo "$include_line"
      cat "$conf_file"
    } > "$tmp_conf"
    install -m 600 "$tmp_conf" "$conf_file"
    rm -f "$tmp_conf"
    _ok2 "已在 $conf_file 顶部插入 include 语句"
  fi

  # --- ③ sshd -t 语法检查(安全闸门, 不过就回滚, 绝不因配置错误导致无法登录) ---
  if ! sshd -t >/dev/null 2>&1; then
    _err2 "sshd 配置语法检查失败, 已回滚, 未关闭密码登录:"
    _err2 "  sshd -t"
    rm -f "$drop_file"
    return 1
  fi

  # --- ④ 重启 sshd(自动识别 systemd / openrc) ---
  _info2 "正在重启 sshd 使配置生效 ..."
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || {
      _err2 "systemd 重启 sshd 失败, 请手动: systemctl restart sshd"
      return 1
    }
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service sshd restart >/dev/null 2>&1 || rc-service ssh restart >/dev/null 2>&1 || {
      _err2 "openrc 重启 sshd 失败, 请手动: rc-service sshd restart"
      return 1
    }
  else
    _err2 "未识别 systemd/openrc, 请手动重启 sshd 后执行 sshd -T 校验。"
    return 1
  fi
  _ok2 "sshd 已重启"

  # --- ⑤ 自动校验真实生效值 ---
  # ChallengeResponse 在新版 OpenSSH(9.8+)已移除, 不存在也算通过。
  _info2 "自动校验实际生效的认证设置 ..."
  local pa kbd cr
  pa=$(sshd -T 2>/dev/null | awk -F' ' '/^passwordauthentication/{print $2}')
  kbd=$(sshd -T 2>/dev/null | awk -F' ' '/^kbdinteractiveauthentication/{print $2}')
  cr=$(sshd -T 2>/dev/null | awk -F' ' '/^challengeresponseauthentication/{print $2}')
  echo "  PasswordAuthentication=$pa  KbdInteractiveAuthentication=${kbd:-(不存在,旧版)}  ChallengeResponseAuthentication=${cr:-(不存在,9.8+已移除,视为通过)}"
  if [ "$pa" = "no" ] && [ "$kbd" = "no" ] && { [ "$cr" = "no" ] || [ -z "$cr" ]; }; then
    _ok2 "校验通过: 密码登录已确认为关闭。"
  else
    _err2 "校验失败: 密钥登录可能仍为开启(pa=$pa kbd=$kbd cr=$cr)。"
    _err2 "请手动复核: sshd -T | grep -iE 'password|kbdinteractive|challengeresponse'"
  fi
  _ok2 "关闭密码登录流程结束。请用另一窗口验证: 密码登录已失效、密钥登录正常。"
}
if [ "${DISABLE_PASSWORD:-1}" != "0" ]; then
  disable_password_login || _err2 "关闭密码登录未完成(不影响 BBR)"
else
  _info2 "检测到 DISABLE_PASSWORD=0, 跳过关闭密码登录(保持现状)"
fi

exit 0
