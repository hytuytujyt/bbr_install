# bbr_install

> Linux VPS 一键开启 BBR（Google 拥塞控制算法），支持 **Alpine / Debian / Ubuntu** 三种系统。

## 一键安装

复制下面**一整行**粘贴执行即可（先把脚本下载到本地，再执行；全程带超时，避免双栈机器 IPv6 黑洞时静默卡住无输出）：

```
if command -v curl >/dev/null 2>&1; then curl -fL --connect-timeout 10 -m 60 -o /tmp/install_bbr.sh https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh; elif command -v wget >/dev/null 2>&1; then wget -q -T 15 -O /tmp/install_bbr.sh https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh; elif command -v busybox >/dev/null 2>&1; then busybox wget -q -T 15 -O /tmp/install_bbr.sh https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh; else echo '需要 curl/wget/busybox 之一' >&2; exit 1; fi && sh /tmp/install_bbr.sh
```

> ⚠️ 上面的命令**默认会关闭密码登录**（只留密钥登录）。运行前请先用 SSH 私钥确认能成功登录，避免脚本运行后自己进不去。若你**不想关闭密码登录**，把这一行末尾的 `sh /tmp/install_bbr.sh` 改成 `DISABLE_PASSWORD=0 sh /tmp/install_bbr.sh` 即可。详见下方"关闭密码登录"一节。

> 脚本采用「sh 引导段 + bash 自举」结构（与 install_reality.sh 相同）：
> 引导段用 POSIX sh 运行，自动检测 `bash` / `curl`，缺少时按系统自动安装（apk / apt-get / dnf / yum / zypper / pacman 全支持），装好后自动用 bash 自举执行正文，**全程无需手动干预、无需重启**。

## 支持的系统

| 系统 | 默认内核 | BBR 支持 |
| ---- | -------- | -------- |
| Alpine 3.18+ | 6.x | ✅ 内置 |
| Debian 11+ | 5.10+ | ✅ 内置 |
| Ubuntu 20.04+ | 5.4+ | ✅ 内置 |

> 内核要求 ≥ 4.9。CentOS 7 等老内核系统不在支持范围内，请先升级内核或重装系统。

## 关闭密码登录

脚本在完成 BBR 之后，会**自动关闭 SSH 密码登录**（改为密钥登录）。

> ⚠️ **重要前提**：关闭密码登录后，SSH 只能靠密钥登录，无法再输密码。运行本脚本前，请务必**先用 SSH 私钥确认能成功登录**（你的公钥已在服务器 `authorized_keys` 中），避免脚本运行后自己进不去。

关闭逻辑说明：
- 写入排在最前的 drop-in `/etc/ssh/sshd_config.d/00-disable-password.conf`（`PasswordAuthentication no` 等），确保优先生效、不被系统默认配置覆盖。
- 执行 `sshd -t` 语法校验，不过就**自动回滚**（删除 drop-in、不重启），不因配置错误导致无法登录。
- 重启 sshd（自动识别 systemd / openrc），并自动校验真实生效值。

**默认行为：脚本会关闭密码登录。** 直接用上面的一键安装命令或本地 `sh install_bbr.sh` 就会关。

**不想关闭密码登录？** 在命令前面加环境变量 `DISABLE_PASSWORD=0 `（注意 `0` 后面要有空格），完整命令如下，直接整行复制：

> 方式一（本地已有脚本文件）：
> ```
> DISABLE_PASSWORD=0 sh install_bbr.sh
> ```
>
> 方式二（还没下载、用一键安装）：把下面这一整行复制执行即可（末尾的 `DISABLE_PASSWORD=0 sh /tmp/install_bbr.sh` 就是跳过关密码的部分）：
> ```
> if command -v curl >/dev/null 2>&1; then curl -fL --connect-timeout 10 -m 60 -o /tmp/install_bbr.sh https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh; elif command -v wget >/dev/null 2>&1; then wget -q -T 15 -O /tmp/install_bbr.sh https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh; elif command -v busybox >/dev/null 2>&1; then busybox wget -q -T 15 -O /tmp/install_bbr.sh https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh; else echo '需要 curl/wget/busybox 之一' >&2; exit 1; fi && DISABLE_PASSWORD=0 sh /tmp/install_bbr.sh
> ```
>
> 也就是说：默认执行（不带 `DISABLE_PASSWORD=0`）= 关闭密码登录；加了 `DISABLE_PASSWORD=0 ` = 跳过、保持密码登录。

关闭密码登录后，若想查看当前密码登录是开是关，可随时执行：

```
sshd -T | grep -iE 'password|kbdinteractive|challengeresponse'
```

判定标准：
- `passwordauthentication no` → 密码登录已关闭 ✅（关成功了）
- `passwordauthentication yes` → 密码登录还开着（没关成）
- `kbdinteractiveauthentication` 和 `challengeresponseauthentication` 显示 `no` 或不显示，都属正常（`challengeresponse` 在新版 OpenSSH 已移除，不出现即视为通过）

脚本运行结束并关闭密码后，用另一窗口验证：密码登录已失效、密钥登录正常；BBR 状态用 `bbrstatus` 查看。

## 验证是否生效

脚本会写入 3 项配置：

| 配置项 | 期望值 | 作用 |
| ------ | ------ | ---- |
| `net.ipv4.tcp_congestion_control` | `bbr` | 拥塞控制算法（核心） |
| `net.core.default_qdisc` | `fq` | 数据包队列调度（BBR 官方推荐搭配） |
| `net.ipv4.tcp_slow_start_after_idle` | `0` | 空闲后保持原速率，不重新慢启动 |

### 方法一：bbrstatus 命令（最简单，脚本自动安装）

脚本运行后会自动安装 `bbrstatus` 命令，任何时候输入即可查看友好状态：

```sh
bbrstatus
```

输出示例：

```
========== BBR 状态 ==========
[✓] 拥塞控制算法: bbr (BBR 已开启)
[!] 此系统没有 fq 功能 (内核未编译 NET_SCHED), 不影响 BBR
[✓] 空闲慢启动: 已关闭 (slow_start_after_idle=0)
```

> 若系统无 fq 功能，脚本运行时会用醒目提示告知，**无需再手动执行 `sysctl net.core.default_qdisc`**（该命令在此类系统上会报 `unknown key`，属正常现象，不影响 BBR）。

### 方法二：手动查命令（最可靠，可一键粘贴）

复制下面**一整行**粘贴执行即可，三条结果一次全出（无需逐条输入）：

```sh
sysctl net.ipv4.tcp_congestion_control; sysctl net.core.default_qdisc; sysctl net.ipv4.tcp_slow_start_after_idle
```

**判定标准：**

- 第一条输出 `bbr` → BBR 已开启 ✅（这一条是核心）
- 第二条输出 `fq` → 队列调度正确 ✅（无 fq 的内核会报 `unknown key`，属正常现象，不影响 BBR）
- 第三条输出 `0` → 慢启动优化已生效 ✅

> 注意：`sysctl net.xxx` 查的是**当前生效值**；如果和期望不符，多半是配置没应用，手动执行 `sysctl -p /etc/sysctl.d/99-bbr.conf` 后再查。

## 关闭 BBR（恢复默认）

删除配置文件，并把运行时值改回系统默认：

```bash
rm -f /etc/sysctl.d/99-bbr.conf
sysctl -w net.ipv4.tcp_congestion_control=cubic
sysctl -w net.core.default_qdisc=pfifo_fast
sysctl -w net.ipv4.tcp_slow_start_after_idle=1
```

> 注意：只删配置文件不会立即改回，因为运行时值仍停留在 `bbr`，必须显式写回默认值。重启后也会恢复默认（配置文件已删除）。

## 常见问题

**Q: 报错「内核未包含 BBR / 无法开启」？**
A: 先确认是不是容器环境（Docker/LXC 等）：容器里系统是 Alpine 但 `uname -r` 显示的是宿主内核（如 `6.1.0-48-cloud-amd64` 是 Debian 云主机内核）。容器内无法 `modprobe` 加载内核模块，但内核本身往往支持 BBR。新版本脚本已兼容：modprobe 失败时会改为直接实测设置，内核支持即可开启；若仍失败，需在宿主机执行 `modprobe tcp_bbr` 或升级宿主内核。

**Q: 开了之后感觉没变化？**
A: BBR 对"长距离 + 高延迟 + 有丢包"的国际线路提升最明显；如果服务器和访问者同城、线路质量极好，本身就能跑满带宽，体感差异不大。另外瓶颈若在 CPU/磁盘或对方限速，BBR 也救不了。

**Q: 开启后需要重启吗？**
A: 不需要。但 BBR 只对新建立的连接生效，已存在的连接（比如当前 SSH 会话）重连一次即可。

**Q: 对 Shadowsocks / VLESS+Reality / Trojan 等节点有效吗？**
A: 有效。这些节点都走 TCP，BBR 在内核 TCP 栈层面生效，所有 TCP 节点自动享受，无需逐个配置。走 UDP/QUIC 的协议（如 Hysteria2）不归内核 BBR 管，但它们自带用户态拥塞控制，不受影响。

**Q: 有什么副作用吗？**
A: 基本没有。极少数场景下 BBR 会增加一点延迟抖动，可忽略。

## 项目结构

```
bbr_install/
├── readme.md          # 说明文档
└── install_bbr.sh     # 一键开启脚本
```

## License

MIT
