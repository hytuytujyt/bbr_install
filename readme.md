# bbr_install

> Linux VPS 一键开启 BBR（Google 拥塞控制算法），支持 **Alpine / Debian / Ubuntu** 三种系统。

## 一键安装

复制下面任意一条命令到你的 VPS 上执行即可（需 root 权限）：

```bash
# 方式一: curl
bash <(curl -fsSL https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh)
```

```bash
# 方式二: wget
wget -qO- https://raw.githubusercontent.com/hytuytujyt/bbr_install/main/install_bbr.sh | bash
```

执行完成后脚本会自动检测系统、检查内核版本、写入配置并生效，**全程不需要重启**。

## 支持的系统

| 系统 | 默认内核 | BBR 支持 |
| ---- | -------- | -------- |
| Alpine 3.18+ | 6.x | ✅ 内置 |
| Debian 11+ | 5.10+ | ✅ 内置 |
| Ubuntu 20.04+ | 5.4+ | ✅ 内置 |

> 内核要求 ≥ 4.9。CentOS 7 等老内核系统不在支持范围内，请先升级内核或重装系统。

## 验证是否生效

```bash
sysctl net.ipv4.tcp_congestion_control
# 输出 bbr 即表示开启成功
```

## 关闭 BBR（恢复默认）

```bash
rm -f /etc/sysctl.d/99-bbr.conf
sysctl -p
```

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
