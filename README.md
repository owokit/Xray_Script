# Xray_Script

windows 部署 Xray 的脚本：`xray-win-airport.ps1`
linux 部署 Xray 的脚本：`xray-linux-airport.sh`

## Windows 一键安装

在目标 Windows 服务器上，用管理员 PowerShell 执行：

```
Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1" | iex
```

上述命令会：
- **下载并解压 Xray-core（XTLS/Xray-core，64 位）**  
- **生成 VLESS + Reality 主节点配置**（自动生成 X25519 密钥和 shortId）  
- **可选生成 VMess mKCP + wechat-video 备用节点**（UDP，仅在 TCP 不通时尝试）  
- 创建开机自启的计划任务（SYSTEM 身份）  
- 在安装目录下生成 `config.json`、日志目录和 `links.txt`（内含订阅链接）

## Windows 参数说明

脚本支持通过 `iex "& { $(irm ...) } -Param ..."` 的形式传参，例如：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iex "& { $(irm 'https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1') } -RealityDest 'www.apple.com:443' -RealityServerName 'www.apple.com' -BaseDir 'D:\xray' -RealityPort 443"
```

- **`-RealityPort`**（可选，`int`，`1-65535`）  
  VLESS+Reality 入站端口（TCP）。未指定时自动随机选择空闲端口，并避免常见业务端口。

- **`-VmessKcpPort`**（可选，`int`，`1-65535`）  
  VMess mKCP 备用节点使用的 UDP 端口。未指定时随机选择空闲 UDP 端口。仅在 TCP/Reality 无法连接时建议尝试，此协议可能被运营商 **QOS/限速或丢包**。

- **`-UUID`**（可选）  
  客户端 ID。未指定时自动生成一个 UUID，并在所有入站上复用。

- **`-CoreVersion`**（可选）  
  指定 Xray-core 版本，例如：`v25.9.5` 或 `25.9.5`。不指定时默认下载最新版本。

- **`-Proxy`**（可选）  
  下载 Xray-core 时使用的上游代理，例如：`http://127.0.0.1:1080` 或 `socks5://127.0.0.1:1080`。

- **`-RealityDest`**（可选，默认 `cloudflare.com:443`）  
  Reality 的伪装目标（`host:port`），必须是真实存在、**能被直连访问** 的网站 443 端口。

- **`-RealityServerName`**（可选，默认 `cloudflare.com`）  
  Reality 的 SNI，与上面的 `RealityDest` 中的域名对应。

- **`-RealityShortId`**（可选）  
  Reality 的 shortId（十六进制字符串，长度 2~16）。未指定时脚本自动生成 8 位 hex。

- **`-BaseDir`**（可选，默认 `$env:SystemDrive\xray`，例如 `C:\xray` 或 `D:\xray`）  
  脚本的安装目录，包含：
  - `bin\\xray.exe`  
  - `config.json`  
  - `log` 日志目录  
  - `links.txt`（包含生成的 VLESS/VMess 链接）

- **`-Uninstall`**（开关）  
  卸载模式：
  - 尝试停止正在运行的 `xray` 进程  
  - 删除名为 `XrayServer` 的计划任务  
  - 删除名为 `Xray_*` 的防火墙规则（如果系统支持 `Get-NetFirewallRule`）  
  - 删除指定的 `-BaseDir` 目录及其中文件  

**示例：卸载并清理安装目录**（需和当初安装时的 `BaseDir` 保持一致）：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iex "& { $(irm 'https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1') } -Uninstall -BaseDir 'D:\xray'"
```

## Linux 一键安装

在目标 Linux 服务器（Ubuntu / CentOS 等，需使用 systemd）上，推荐直接执行下面这一行命令：

```bash
curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh | sudo bash
```

脚本会自动：
- 检测并要求以 root / sudo 运行
- 检测并在需要时自动安装依赖：`curl`、`unzip`（支持 `apt-get` / `yum` / `dnf`)
- 下载并解压 Xray-core（XTLS/Xray-core，linux-64）
- 生成 VLESS + Reality 主节点和 VMess mKCP 备用节点配置
- 在 `BaseDir`（默认 `/opt/xray`）下生成 `config.json`、`log` 目录和 `links.txt`
- 使用 systemd 创建并启用 `xray-server` 服务，自动开机自启

### Linux 参数说明（与 Windows 版对应）

支持通过命令行参数或环境变量传参，常用参数：

- `--reality-port`（对应 `-RealityPort`）  
  VLESS+Reality TCP 端口。未指定时自动随机选择空闲端口。

- `--vmess-kcp-port`（对应 `-VmessKcpPort`）  
  VMess mKCP UDP 端口。未指定时随机选择空闲 UDP 端口。

- `--uuid`（对应 `-UUID`）  
  客户端 ID。未指定时自动生成 UUID，并在所有入站上复用。

- `--core-version`（对应 `-CoreVersion`）  
  指定 Xray-core 版本，例如：`v25.9.5` 或 `25.9.5`。不指定时默认下载最新版本。

- `--proxy`（对应 `-Proxy`）  
  下载 Xray-core 时使用的上游代理，例如：`http://127.0.0.1:1080` 或 `socks5://127.0.0.1:1080`。

- `--reality-dest` / `--reality-server-name`（对应 `-RealityDest` / `-RealityServerName`）  
  Reality 的伪装目标与 SNI，默认：`cloudflare.com:443` / `cloudflare.com`。

- `--reality-short-id`（对应 `-RealityShortId`）  
  Reality 的 shortId（十六进制字符串，长度 2~16）。未指定时脚本自动生成 8 位 hex。

- `--base-dir`（对应 `-BaseDir`，默认 `/opt/xray`）  
  安装目录，包含：`bin/xray`、`config.json`、`log` 目录和 `links.txt`。

- `--uninstall`（对应 `-Uninstall`）  
  卸载模式：停止 systemd 服务、删除 service 文件并清理 `BaseDir`。

**示例：卸载并清理安装目录**（需和当初安装时的 `--base-dir` 保持一致）：

```bash
sudo ./xray-linux-airport.sh --uninstall --base-dir /opt/xray
```

## Reality Dest / SNI 选择建议

默认：

- `RealityDest = cloudflare.com:443`
- `RealityServerName = cloudflare.com`

如果你的服务器 IP 被 Cloudflare 认为是“脏 IP”，可能会出现无法连接或频繁 403/5xx 的情况。可以改用其他大厂 HTTPS 网站，例如：

- `www.apple.com:443` / SNI: `www.apple.com`  
- `www.microsoft.com:443` / SNI: `www.microsoft.com`  
- `www.bing.com:443` / SNI: `www.bing.com`  

**注意：**

- `RealityDest` 和 `RealityServerName` 的域名部分应保持一致（同一个站点），否则可能无法正常握手。  
- 不要填明显违规或不存在的域名，以免被对方服务器或中间设备快速拉黑。

## 协议与安全性说明

- **主节点：VLESS + Reality (TCP)**  
  - 使用 X25519 密钥对 + `xtls-rprx-vision` 流控  
  - 入站仅开放一个 `vless+reality` 端口，作为推荐的安全方案

- **备用节点：VMess + mKCP + wechat-video (UDP)**  
  - 仅在 TCP/Reality 无法使用时，作为“兜底”方案  
  - 使用 UDP 传输，可能被运营商 QOS/限速或直接丢包  
  - 脚本在总结时会明确标注“仅在 TCP/Reality 不可用时尝试”

**已移除的不安全配置：**  

- 原先的 **VMess + TCP（无 TLS）** 入站已从默认配置中删除，因为在大陆 GFW 环境下特征明显，极易导致服务器 IP 被快速封禁。

## 客户端导入说明

脚本执行完成后会在控制台输出：

- VLESS Reality 主节点的详细参数  
- VMess mKCP 备用节点参数  
- 每个节点对应的一条 `vless://` 或 `vmess://` 链接  
- 所有链接也会保存到：`<BaseDir>\\links.txt`

你可以在以下客户端中导入：

- **v2rayN（Windows）**  
  - 打开 v2rayN → 右键托盘图标或主窗口 → `从剪贴板导入 URL`  
  - 或在“服务器”列表中选择 `导入自 URL`，粘贴 `links.txt` 中的链接

- **v2rayNG（Android）**  
  - 打开 v2rayNG → 点击右下角 `+` → 选择 `从剪贴板导入`  
  - 或选择 `手动输入`，将脚本输出的 URL 复制进去

- **Shadowrocket（iOS）**  
  - 打开 Shadowrocket → 在配置列表点击右上角 `+` → 选择 `类型: Subscribe/URL`  
  - 将 `vless://` 或 `vmess://` 链接粘贴进去保存

导入后，建议优先使用：

1. **VLESS Reality 主节点**（更隐蔽、更稳）  
2. **仅在 TCP/Reality 不可用时，才尝试 VMess mKCP 备用节点**，并留意运营商对 UDP 的限制情况。

## 免责声明

本脚本仅用于学习和研究 Xray/Reality 协议的部署方式。请确保你的使用行为符合当地法律法规及服务提供商的使用条款。作者及贡献者对任何因使用本脚本导致的法律风险或损失不承担责任。

## License / 开源协议

本项目使用 **GPL-3.0** 协议发布，具体条款请参见仓库中的 `LICENSE` 文件（GNU General Public License v3.0）。