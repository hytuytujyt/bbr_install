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
# 本脚本不判断私钥是否可用；所有 SSH 配置改动均先备份,失败时恢复。
disable_password_login() {
  _info2 "检查是否可以安全关闭密码登录 ..."

  local conf_file="/etc/ssh/sshd_config"
  local drop_dir="/etc/ssh/sshd_config.d"
  local drop_file="$drop_dir/00-disable-password.conf"
  local include_line="Include ${drop_dir}/*.conf"
  local backup_dir="/etc/ssh/bbr-install-backup-$(date +%Y%m%d%H%M%S)-$$"
  local main_backup="$backup_dir/sshd_config"
  local drop_backup="$backup_dir/00-disable-password.conf"
  local drop_existed=0
  local tmp_conf check_err check_out pa kbd cr

  if ! command -v sshd >/dev/null 2>&1; then
    _err2 "未找到 sshd, 无法安全修改 SSH 配置"
    return 1
  fi
  if [ ! -f "$conf_file" ]; then
    _err2 "找不到 SSH 配置文件: $conf_file"
    return 1
  fi

  mkdir -p "$backup_dir" "$drop_dir" || {
    _err2 "无法创建 SSH 配置备份目录"
    return 1
  }
  cp -p "$conf_file" "$main_backup" || {
    _err2 "无法备份 $conf_file"
    rm -rf "$backup_dir"
    return 1
  }
  if [ -f "$drop_file" ]; then
    drop_existed=1
    cp -p "$drop_file" "$drop_backup" || {
      _err2 "无法备份 $drop_file"
      rm -rf "$backup_dir"
      return 1
    }
  fi

  local ssh_restarted=0
  restart_ssh_service() {
    if [ -r /proc/1/comm ] && grep -qx 'systemd' /proc/1/comm && command -v systemctl >/dev/null 2>&1; then
      systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1
    elif command -v rc-service >/dev/null 2>&1; then
      rc-service sshd restart >/dev/null 2>&1 || rc-service ssh restart >/dev/null 2>&1
    elif command -v service >/dev/null 2>&1; then
      service ssh restart >/dev/null 2>&1 || service sshd restart >/dev/null 2>&1
    else
      return 1
    fi
  }
  rollback_ssh() {
    _err2 "正在恢复 SSH 配置 ..."
    cp -p "$main_backup" "$conf_file" || _err2 "恢复 $conf_file 失败"
    if [ "$drop_existed" = "1" ]; then
      cp -p "$drop_backup" "$drop_file" || _err2 "恢复 $drop_file 失败"
    else
      rm -f "$drop_file" || _err2 "删除新建的 $drop_file 失败"
    fi
    if [ "$ssh_restarted" = "1" ]; then
      if restart_ssh_service; then
        _info2 "已重启 SSH 使恢复的旧配置生效"
      else
        _err2 "恢复文件已写回,但无法重启 SSH;请手动重启 SSH 服务"
      fi
    fi
  }

  # 先把已有的 sshd_config.d Include 移到最前面。
  # OpenSSH 对同一配置项采用 first-match-wins；这一步保证 00- 文件
  # 先于供应商的 99-runman.conf 以及主配置中的 PasswordAuthentication yes。
  tmp_conf="$(mktemp /tmp/sshd_config.XXXXXX)" || {
    _err2 "无法创建临时 SSH 配置文件"
    rollback_ssh
    return 1
  }
  {
    printf '%s\n' "$include_line"
    awk '!/^[[:space:]]*Include[[:space:]]+.*sshd_config\.d\/\*\.conf([[:space:]]*#.*)?$/ { print }' "$conf_file"
  } > "$tmp_conf" || {
    rm -f "$tmp_conf"
    rollback_ssh
    return 1
  }
  if ! install -m 600 "$tmp_conf" "$conf_file"; then
    rm -f "$tmp_conf"
    rollback_ssh
    return 1
  fi
  rm -f "$tmp_conf"

  # 精简版或定制版 OpenSSH 可能不支持某些配置项(例如 UsePAM)。
  # 从 sshd 的明确错误中提取选项名,只注释主配置中的对应有效行；
  # 原文件已保存在 backup_dir 中，后续验证失败会完整回滚。
  check_err="$(mktemp /tmp/sshd_check.XXXXXX)" || {
    rollback_ssh
    return 1
  }
  if sshd -t -f "$conf_file" >/dev/null 2>"$check_err"; then
    :
  else
    unsupported_option="$(awk 'tolower($0) ~ /unsupported option/ { for (i = 1; i < NF; i++) if (tolower($i) == "option") { print $(i + 1); exit } }' "$check_err")"
    if [ -n "$unsupported_option" ]; then
      _warn2 "当前 sshd 不支持配置项 $unsupported_option, 已临时注释该无效配置(原文件已备份)"
      tmp_conf="$(mktemp /tmp/sshd_config.XXXXXX)" || {
        rm -f "$check_err"
        rollback_ssh
        return 1
      }
      awk -v opt="$unsupported_option" 'tolower($1) == tolower(opt) { print "# install_bbr.sh: 当前 sshd 不支持 " opt; print "# " $0; next } { print }' "$conf_file" > "$tmp_conf" || {
        rm -f "$tmp_conf" "$check_err"
        rollback_ssh
        return 1
      }
      if ! install -m 600 "$tmp_conf" "$conf_file"; then
        rm -f "$tmp_conf" "$check_err"
        rollback_ssh
        return 1
      fi
      rm -f "$tmp_conf"
    else
    _err2 "sshd 配置语法检查失败, 未重启 SSH:"
    printf '%s\n' "$(cat "$check_err")" >&2
    rm -f "$check_err"
    rollback_ssh
    return 1
    fi
  fi
  rm -f "$check_err"

  printf '%s\n' \
    "PasswordAuthentication no" \
    "KbdInteractiveAuthentication no" \
    "ChallengeResponseAuthentication no" > "$drop_file" || {
    _err2 "无法写入 $drop_file"
    rollback_ssh
    return 1
  }
  _ok2 "已写入 $drop_file"

  if ! sshd -t -f "$conf_file"; then
    _err2 "sshd 配置语法检查失败, 未重启 SSH"
    rollback_ssh
    return 1
  fi

  check_err="$(mktemp /tmp/sshd_check.XXXXXX)" || {
    rollback_ssh
    return 1
  }
  if ! check_out="$(sshd -T -f "$conf_file" 2>"$check_err")"; then
    _err2 "无法读取 sshd 的有效配置, 未重启 SSH:"
    printf '%s\n' "$(cat "$check_err")" >&2
    rm -f "$check_err"
    rollback_ssh
    return 1
  fi
  rm -f "$check_err"
  pa="$(printf '%s\n' "$check_out" | awk '$1 == "passwordauthentication" { print $2; exit }')"
  kbd="$(printf '%s\n' "$check_out" | awk '$1 == "kbdinteractiveauthentication" { print $2; exit }')"
  cr="$(printf '%s\n' "$check_out" | awk '$1 == "challengeresponseauthentication" { print $2; exit }')"
  echo "  PasswordAuthentication=$pa  KbdInteractiveAuthentication=${kbd:-(不存在或未输出)}  ChallengeResponseAuthentication=${cr:-(不存在或未输出)}"
  if [ "$pa" != "no" ]; then
    _err2 "校验失败: 密码登录可能仍为开启(pa=$pa kbd=$kbd cr=$cr), 未重启 SSH"
    _err2 "请手动复核: sshd -T -f '$conf_file' | grep -iE 'password|kbdinteractive|challengeresponse'"
    rollback_ssh
    return 1
  fi
  if [ -n "$kbd" ] && [ "$kbd" != "no" ]; then
    _err2 "校验失败: 键盘交互认证仍为开启(kbd=$kbd), 未重启 SSH"
    rollback_ssh
    return 1
  fi

  _info2 "正在重启 SSH 服务使配置生效 ..."
  if ! restart_ssh_service; then
    _err2 "未识别可用的 SSH 服务管理器,或 SSH 重启失败"
    rollback_ssh
    return 1
  fi
  ssh_restarted=1
  _ok2 "SSH 服务已重启"

  check_err="$(mktemp /tmp/sshd_check.XXXXXX)" || {
    rollback_ssh
    return 1
  }
  if ! check_out="$(sshd -T -f "$conf_file" 2>"$check_err")"; then
    _err2 "重启后无法校验 sshd 配置, 正在回滚"
    printf '%s\n' "$(cat "$check_err")" >&2
    rm -f "$check_err"
    rollback_ssh
    return 1
  fi
  rm -f "$check_err"
  pa="$(printf '%s\n' "$check_out" | awk '$1 == "passwordauthentication" { print $2; exit }')"
  kbd="$(printf '%s\n' "$check_out" | awk '$1 == "kbdinteractiveauthentication" { print $2; exit }')"
  cr="$(printf '%s\n' "$check_out" | awk '$1 == "challengeresponseauthentication" { print $2; exit }')"
  echo "  重启后: PasswordAuthentication=$pa  KbdInteractiveAuthentication=${kbd:-(不存在或未输出)}  ChallengeResponseAuthentication=${cr:-(不存在或未输出)}"
  if [ "$pa" != "no" ] || { [ -n "$kbd" ] && [ "$kbd" != "no" ]; }; then
    _err2 "重启后校验失败: 密码登录可能仍为开启(pa=$pa kbd=$kbd cr=$cr)"
    _err2 "正在恢复修改前的 SSH 配置；现有 SSH 会话不会被主动断开"
    rollback_ssh
    return 1
  fi

  _ok2 "校验通过: 密码登录已确认为关闭。"
  _ok2 "关闭密码登录流程结束。请用另一窗口验证: 密钥登录正常。"
  _info2 "SSH 配置备份保留在: $backup_dir"
}
if [ "${DISABLE_PASSWORD:-1}" != "0" ]; then
  disable_password_login || { _err2 "关闭密码登录未完成(不影响 BBR)"; exit 1; }
else
  _info2 "检测到 DISABLE_PASSWORD=0, 跳过关闭密码登录(保持现状)"
fi

exit 0
