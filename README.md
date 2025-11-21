# Xray_Script

- **Linux 一键部署脚本**：`xray-linux-airport.sh`  
- **Windows 一键部署脚本**：`xray-win-airport.ps1`

脚本的目标是：在常见的服务器环境下一键部署 **VLESS + Reality 主节点**，并提供 **VMess mKCP + wechat-video 备用节点**，同时支持多种可选协议与卸载/重装场景。

> 默认推荐方案：**VLESS Reality + VMess mKCP（wechat-video）**，在 Linux 与 Windows 上都是默认 Profile。

---

## 项目结构（拆分后的脚本）

- `xray-linux-airport.sh`  
  Linux 主入口脚本，一键安装命令仍然直接指向该文件。内部会按需加载：  
  - `linux/xray-common.sh`：通用辅助函数（日志、多语言、依赖安装、`BASE_DIR` 校验等）  
  - `linux/xray-uninstall.sh`：卸载/卸载配置/仅删配置相关逻辑  
  - `linux/xray-ports.sh`：端口检查与随机端口分配逻辑  
  - `xray-profiles-lib.sh`：各协议 Profile 的配置生成功能（按需从 GitHub 下载）

- `xray-win-airport.ps1`  
  Windows 主入口脚本，一键安装命令仍然直接指向该文件。内部会按需加载：  
  - `windows\\Xray-Ports.ps1`：端口检查与随机端口分配逻辑  
  - `windows\\Xray-Uninstall.ps1`：卸载/卸载配置/仅删配置相关逻辑  
  - `xray-profiles-lib.ps1`：各协议 Profile 的配置生成功能

> 说明：为了保证 `curl | sudo bash` / `irm | iex` 等一键命令在纯脚本环境下也能运行，主脚本内部仍保留一份关键逻辑作为兜底；在本仓库中开发或维护时，建议优先修改 `linux/` 与 `windows/` 目录下的模块文件。

---

## Linux 一键安装

在目标 Linux 服务器（Ubuntu / Debian / CentOS / Rocky 等，需使用 systemd）上执行：

```bash
curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh | sudo bash
```

脚本会自动完成：

- **检查 root 权限**（必须以 root / sudo 运行）
- **自动安装依赖**：`curl`、`unzip`、`openssl`（支持 `apt-get` / `yum` / `dnf`)
- **自动下载 profile 库**：`xray-profiles-lib.sh`（支持多种协议方案）
- **下载并解压 Xray-core**（`XTLS/Xray-core`，linux-64）
- **默认生成 VLESS Reality 主节点 + VMess mKCP(wechat-video) 备用节点** 配置
- 在 `BaseDir`（默认 `/opt/xray`）下生成：`config.json`、`log` 目录、`links.txt`、`ports.env`
- 创建并启用 systemd 服务 `xray-server`，开机自启

### Linux 协议方案（Profile）

在交互式 TTY 中运行时，脚本会弹出菜单让你选择协议方案；非交互模式时，默认使用：**`reality-kcp`**。

- **`reality-kcp`**（默认）  
  VLESS Reality（TCP）+ VMess mKCP（UDP wechat-video），推荐方案。
- **`reality-only`**  
  仅 VLESS Reality 入站，不启用 mKCP 备用节点。
- **`kcp-only`**  
  仅 VMess mKCP + wechat-video（UDP）。
- **`vmess-tcp` / `vmess-mkcp` / `vmess-quic`**  
  传统 VMess TCP / mKCP / QUIC。
- **`vmess-h2-tls` / `vmess-ws-tls` / `vmess-grpc-tls`**  
  VMess + H2 / WebSocket / gRPC，均使用 **自签名证书 + TLS**。
- **`vless-h2-tls` / `vless-ws-tls` / `vless-grpc-tls`**  
  VLESS + H2 / WebSocket / gRPC，自签名证书 + TLS。
- **`trojan-h2-tls` / `trojan-ws-tls` / `trojan-grpc-tls`**  
  Trojan + H2 / WebSocket / gRPC，自签名证书 + TLS。
- **`shadowsocks`**  
  Shadowsocks（`aes-256-gcm`），使用 UUID 作为密码。
- **`vmess-tcp-dynamic` / `vmess-mkcp-dynamic` / `vmess-quic-dynamic`**  
  VMess 动态端口，范围 `20000-30000`。

> **提示：**在大陆环境下不推荐把明文 VMess TCP 作为唯一入口，建议优先使用 `reality-kcp` 或 `reality-only`。

### Linux 参数说明

脚本支持 **命令行参数** 和 **环境变量** 两种方式传参。常用参数：

- **`--reality-port`**（对应环境变量 `REALITY_PORT`）  
  VLESS Reality TCP 端口。未指定时自动随机选择空闲端口。

- **`--vmess-kcp-port`**（对应 `VMESS_KCP_PORT`）  
  VMess mKCP UDP 端口。未指定时自动随机选择空闲 UDP 端口。

- **`--uuid`**（对应 `UUID`）  
  客户端 ID。未指定时自动生成 UUID，并在所有入站上复用。

- **`--core-version`**（对应 `CORE_VERSION`）  
  指定 Xray-core 版本，例如：`v25.9.5` 或 `25.9.5`。不指定时默认下载最新版本。

- **`--proxy`**（对应 `PROXY`）  
  下载 Xray-core 时使用的上游代理，例如：`http://127.0.0.1:1080`、`socks5://127.0.0.1:1080`。

- **`--reality-dest` / `--reality-server-name`**（对应 `REALITY_DEST` / `REALITY_SERVER_NAME`）  
  Reality 的伪装目标与 SNI，默认：`cloudflare.com:443` / `cloudflare.com`。

- **`--reality-short-id`**（对应 `REALITY_SHORT_ID`）  
  Reality 的 shortId（十六进制字符串，长度 2~16）。未指定时脚本自动生成 8 位 hex。

- **`--profile`**（对应 `PROFILE`）  
  明确指定协议方案，如 `reality-kcp`、`reality-only` 等。未指定且为交互式终端时，会弹出菜单；非交互模式下默认 `reality-kcp`。

- **`--base-dir`**（对应 `BASE_DIR`，默认 `/opt/xray`）  
  安装目录，包含：`bin/xray`、`config.json`、`log` 目录、`links.txt`、`ports.env` 等。  
  出于安全考虑，脚本会拒绝使用：`/`、`/root`、`/home`、`/usr`、`/var`、`/etc`、`/opt`、`/tmp` 等顶层系统目录作为 `--base-dir`，必须使用诸如 `/opt/xray` 这样的子目录（默认值已符合要求）。

- **`--keep-config`**（对应 `KEEP_CONFIG=true`，布尔开关）  
  当 `--base-dir` 下已存在 `config.json` 时，只更新 Xray-core 二进制文件，**不覆盖现有配置、不变更防火墙规则和 systemd 服务**。适合“只升级核心版本”。

- **`--force-rebuild-config`**（对应 `FORCE_REBUILD_CONFIG=true`，布尔开关）  
  即使目标目录中已存在 `config.json`，也会强制覆盖为新的默认配置（UUID、端口等会重新生成）。与 `--keep-config` 互斥。

- **`--rebuild-config-only`**（对应 `REBUILD_CONFIG_ONLY=true`，布尔开关）  
  仅根据当前参数 **重新生成 `config.json`**，不下载/更新 Xray-core，也不改动 systemd 服务及防火墙。  
  - 需要已有 `config.json` 和 `bin/xray`。  
  - 不能与 `--keep-config` / `--force-rebuild-config` 同时使用。

- **`--uninstall`**  
  完整卸载：停止 systemd 服务、删除 service 文件、关闭相关端口防火墙规则并删除整个 `BaseDir` 目录。

- **`--uninstall-config`**  
  卸载配置：停止 `xray-server` 服务、清理防火墙规则，只删除 `config.json`、`links.txt`、`ports.env`，保留核心和日志。

- **`--delete-config`**  
  仅删除 `config.json`、`links.txt`、`ports.env`，不停止服务、不改动 systemd 与防火墙（适合手动调试后清理配置）。

### Linux 常见用法示例

- **首次部署（默认 Reality + VMess mKCP）**：

  ```bash
  curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh | sudo bash
  ```

- **更新 Xray-core（保留现有配置）**：

  ```bash
  curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh \
    | sudo BASE_DIR=/opt/xray KEEP_CONFIG=true CORE_VERSION=v25.9.5 bash
  ```

  或：

  ```bash
  curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh \
    | sudo bash -s -- --base-dir /opt/xray --keep-config --core-version v25.9.5
  ```

- **强制重新生成配置（覆盖原有 `config.json`）**：

  ```bash
  curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh \
    | sudo bash -s -- --base-dir /opt/xray --force-rebuild-config
  ```

- **仅重建配置（不下载核心，不改 systemd）**：

  ```bash
  sudo ./xray-linux-airport.sh --rebuild-config-only --base-dir /opt/xray --profile reality-only
  ```

- **卸载并清理安装目录**（`--base-dir` 与安装时保持一致）：

  ```bash
  sudo ./xray-linux-airport.sh --uninstall --base-dir /opt/xray
  ```

---

## Windows 一键安装

在目标 Windows 服务器上，用 **管理员 PowerShell** 执行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1" | iex
```

上述命令会：

- **下载并解压 Xray-core（XTLS/Xray-core，64 位）**  
- **根据 Profile 生成配置**（默认：VLESS Reality 主节点 + VMess mKCP wechat-video 备用）  
- 生成 Reality 所需 X25519 密钥对与 shortId  
- 创建开机自启计划任务（SYSTEM 身份）  
- 在安装目录下生成 `config.json`、日志目录和 `links.txt`（内含订阅链接）

### Windows 参数说明

支持通过 `iex "& { $(irm ...) } -Param ..."` 的形式传参，例如：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; \
  iex "& { $(irm 'https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1') } `
    -RealityDest 'www.apple.com:443' -RealityServerName 'www.apple.com' `
    -BaseDir 'D:\xray' -RealityPort 443"
```

- **`-RealityPort`**（可选，`int`，`1-65535`）  
  VLESS Reality 入站端口（TCP）。未指定时自动随机选择空闲端口，并避免常见业务端口。

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

- **`-Profile`**（可选，默认 `reality-kcp`）  
  支持：`reality-kcp`、`reality-only`、`kcp-only`。  
  - `reality-kcp`：VLESS Reality + VMess mKCP wechat-video（推荐）。  
  - `reality-only`：仅 Reality 主节点。  
  - `kcp-only`：仅 VMess mKCP 备用节点（UDP）。

- **`-BaseDir`**（可选，默认 `$env:SystemDrive\xray`，如 `C:\xray` 或 `D:\xray`）  
  安装目录，包含：
  - `bin\\xray.exe`  
  - `config.json`  
  - `log` 日志目录  
  - `links.txt`（包含生成的 VLESS/VMess 链接）

  出于安全原因，脚本会拒绝使用驱动器根目录（如 `C:\`）、`Windows`、`Program Files`、`Users` 等系统目录作为 `BaseDir`，必须使用类似 `C:\xray` 这样的专用子目录。

- **`-KeepConfig`**（开关）  
  如果目标目录下已存在 `config.json`，只更新 Xray-core 可执行文件，**不修改现有配置、计划任务和防火墙规则**。推荐用于“更新核心版本”。

- **`-ForceRebuildConfig`**（开关）  
  即使目标目录中已存在 `config.json`，也会强制覆盖为新的默认配置（UUID、端口等会重新生成）。与 `-KeepConfig` 互斥。

- **`-RebuildConfigOnly`**（开关）  
  仅根据当前参数重新生成 `config.json`，不下载/更新 Xray-core，也不改动计划任务和防火墙。  
  - 需要已有 `config.json` 与 `xray.exe`。  
  - 不可与 `-KeepConfig` / `-ForceRebuildConfig` 一起使用。

- **`-Uninstall`**（开关）  
  完整卸载模式：
  - 停止正在运行的 `xray` 进程  
  - 删除名为 `XrayServer` 的计划任务  
  - 删除名为 `Xray_*` 的防火墙规则（如果系统支持 `Get-NetFirewallRule`）  
  - 删除指定的 `-BaseDir` 目录及其中文件

- **`-UninstallConfig`**（开关）  
  仅卸载配置：停止 Xray、删除计划任务和防火墙规则，只删除 `config.json` 和 `links.txt`，**保留核心与日志目录**。

- **`-DeleteConfig`**（开关）  
  只删除 `config.json` 和 `links.txt`，不停止进程、不删除计划任务和防火墙规则（调试时清理配置用）。

### Windows 常见用法示例

- **首次部署（默认 Reality + VMess mKCP）**：

  ```powershell
  Set-ExecutionPolicy Bypass -Scope Process -Force; \
    irm "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1" | iex
  ```

- **更新 Xray-core（保留配置）**：

  ```powershell
  Set-ExecutionPolicy Bypass -Scope Process -Force; \
    iex "& { $(irm 'https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1') } -BaseDir 'D:\xray' -KeepConfig -CoreVersion 'v25.9.5'"
  ```

- **强制重新生成配置（覆盖 `config.json`）**：

  ```powershell
  Set-ExecutionPolicy Bypass -Scope Process -Force; \
    iex "& { $(irm 'https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1') } -BaseDir 'D:\xray' -ForceRebuildConfig -Profile 'reality-only'"
  ```

- **仅重建配置（不重新下载 Xray-core）**：

  ```powershell
  Set-ExecutionPolicy Bypass -Scope Process -Force; \
    iex "& { $(irm 'https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1') } -BaseDir 'D:\xray' -RebuildConfigOnly -Profile 'reality-kcp'"
  ```

- **卸载并清理安装目录**（`-BaseDir` 与安装时保持一致）：

  ```powershell
  Set-ExecutionPolicy Bypass -Scope Process -Force; \
    iex "& { $(irm 'https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1') } -Uninstall -BaseDir 'D:\xray'"
  ```

---
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