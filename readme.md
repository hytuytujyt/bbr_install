# bbr_install

> Linux VPS 一键开启 BBR（Google 拥塞控制算法），支持 **Alpine / Debian / Ubuntu** 三种系统。

## 一键安装

复制下面**一整行**粘贴执行即可（GitHub 直拉，自动选择 wget / curl / busybox，不会被换行符打断）：

```
{ command -v wget >/dev/null 2>&1 && wget -qO- https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh || command -v curl >/dev/null 2>&1 && curl -fsSL https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh || command -v busybox >/dev/null 2>&1 && busybox wget -qO- https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh ; } | sh
```

> 脚本采用「sh 引导段 + bash 自举」结构（与 install_reality.sh 相同）：
> 引导段用 POSIX sh 运行，自动检测 `bash` / `curl`，缺少时按系统自动安装（apk / apt-get / dnf / yum / zypper / pacman 全支持），装好后自动用 bash 自举执行正文，**全程无需手动干预、无需重启**。

## 支持的系统

| 系统 | 默认内核 | BBR 支持 |
| ---- | -------- | -------- |
| Alpine 3.18+ | 6.x | ✅ 内置 |
| Debian 11+ | 5.10+ | ✅ 内置 |
| Ubuntu 20.04+ | 5.4+ | ✅ 内置 |

> 内核要求 ≥ 4.9。CentOS 7 等老内核系统不在支持范围内，请先升级内核或重装系统。

## 验证是否生效

脚本会写入 3 项配置：

| 配置项 | 期望值 | 作用 |
| ------ | ------ | ---- |
| `net.ipv4.tcp_congestion_control` | `bbr` | 拥塞控制算法（核心） |
| `net.core.default_qdisc` | `fq` | 数据包队列调度（BBR 官方推荐搭配） |
| `net.ipv4.tcp_slow_start_after_idle` | `0` | 空闲后保持原速率，不重新慢启动 |

### 方法一：看脚本输出（最简单）

运行脚本时，最后会打印类似这样的验证结果，三项都是 ✓ 即全部生效：

```
[✓] 拥塞控制算法: bbr (期望 bbr) ✓
[✓] 队列调度: fq (期望 fq) ✓
[✓] 空闲慢启动: 已关闭 (slow_start_after_idle=0) ✓
[✓] BBR 开启成功!
```

### 方法二：手动查命令（最可靠）

```sh
sysctl net.ipv4.tcp_congestion_control   # 期望输出: = bbr
sysctl net.core.default_qdisc            # 期望输出: = fq
sysctl net.ipv4.tcp_slow_start_after_idle # 期望输出: = 0
```

**判定标准：**

- 第一行输出 `bbr` → BBR 已开启 ✅（这一条是核心，其余两条是加分项）
- 第二行输出 `fq` → 队列调度正确 ✅
- 第三行输出 `0` → 慢启动优化已生效 ✅

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
