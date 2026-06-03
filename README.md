# Xray_Script

- **Linux 一键部署脚本**：`xray-linux-airport.sh`
- **Windows 一键部署脚本**：`xray-win-airport.ps1`

本项目提供在 Linux 和 Windows 环境下的一键部署脚本，旨在快速搭建 **VLESS + Reality 主节点**，并可选 **VMess mKCP + wechat-video 备用节点**。脚本采用模块化设计，便于维护和扩展，同时保留了对单行命令一键安装的完整支持。

---

## 🚀 快速开始 (Quick Start)

### Linux 一键安装

适用于 Ubuntu, Debian, CentOS, Rocky Linux 等常见发行版（需 systemd）。

标准安装（默认方案：VLESS Reality + VMess mKCP）

```bash
curl -fsSL -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/owokit/Xray_Script/main/xray-linux-airport.sh?nocache=$(date +%s)" | sudo bash
```

**安装过程会自动执行：**
1. 检查 Root 权限与系统依赖（curl, unzip, openssl）。
2. 下载并加载最新的 Profile 配置库。
3. 下载 Xray-core (Linux-64)。
4. 生成配置、证书（如需）与 systemd 服务。
5. 输出客户端连接链接 (`vless://`, `vmess://`)。
6. 安装 `xray` 管理命令到 `/usr/local/bin`。

**后续管理配置：**
```bash
xray
```
运行后进入交互式管理菜单，可添加新配置、查看链接、重启服务、更新内核、卸载等。

### Windows 一键安装

适用于 Windows Server 2016/2019/2022 或 Windows 10/11。请使用 **管理员权限** 打开 PowerShell 执行：

标准安装（默认方案：VLESS Reality + VMess mKCP）

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1" | iex
```

**安装过程会自动执行：**
1. 下载 Xray-core (Windows-64)。
2. 生成配置文件与 Reality 密钥。
3. 配置防火墙规则（需系统支持 `New-NetFirewallRule`）。
4. 创建开机自启计划任务 (XrayServer)。
5. 输出客户端连接链接。
6. 安装 `xray` 管理命令。

**后续管理配置：**
```powershell
xray
```
运行后进入交互式管理菜单，可添加新配置、查看链接、重启服务、更新内核、卸载等。

---

## 🛠️ 源码部署与本地开发 (Manual / Dev)

由于本项目采用了模块化结构，将功能拆分到了 `linux/` 和 `windows/` 目录下，因此也支持 Clone 仓库后在本地直接运行。这对于开发者调试或不希望通过 curl 管道运行的用户非常有用。

### Linux 本地运行

```bash
# 1. 克隆仓库
git clone https://github.com/owokit/Xray_Script.git
cd Xray_Script

# 2. 赋予执行权限
chmod +x xray-linux-airport.sh

# 3. 运行脚本（支持所有参数）
sudo ./xray-linux-airport.sh --profile reality-kcp
```

*注意：本地运行时，脚本会优先加载当前目录下的 `linux/*.sh` 模块文件，方便调试修改。*

### Windows 本地运行

1. 下载或 Clone 本仓库到本地（例如 `D:\GitHub\Xray_Script`）。
2. 以**管理员身份**打开 PowerShell。
3. 进入目录并运行：

```powershell
cd D:\GitHub\Xray_Script
.\xray-win-airport.ps1 -Profile reality-kcp
```

*注意：本地运行时，脚本会优先加载当前目录下的 `windows\*.ps1` 模块文件。*

---

## ⚙️ 参数说明 (Arguments)

脚本支持通过环境变量或命令行参数进行自定义。

### Linux 参数

| 参数 | 环境变量 | 说明 |
| :--- | :--- | :--- |
| `--profile <name>` | `PROFILE` | 协议方案名称（见下文列表），默认交互式选择或 `reality-kcp` |
| `--reality-port <port>` | `REALITY_PORT` | Reality TCP 端口，默认随机 |
| `--vmess-kcp-port <port>` | `VMESS_KCP_PORT` | VMess UDP 端口，默认随机 |
| `--main-port <port>` | `MAIN_PORT` | 非 Reality 协议的主端口（VMess/VLESS/Trojan/Shadowsocks 等），默认随机 |
| `--uuid <uuid>` | `UUID` | 自定义 UUID，默认随机生成 |
| `--core-version <ver>` | `CORE_VERSION` | 指定 Xray 版本，如 `v1.8.4`，为空则使用最新版本 |
| `--proxy <url>` | `PROXY` | 下载 Xray 时使用的代理，如 `http://127.0.0.1:1080` |
| `--reality-dest <host:port>` | `REALITY_DEST` | Reality 伪装目标，默认 `cloudflare.com:443` |
| `--reality-server-name <domain>` | `REALITY_SERVER_NAME` | Reality SNI 域名，默认 `cloudflare.com` |
| `--reality-short-id <hex>` | `REALITY_SHORT_ID` | Reality shortId（2–16 位十六进制），为空则随机生成 |
| `--base-dir <path>` | `BASE_DIR` | 安装目录，默认 `/opt/xray` |
| `--tls-cert-mode <mode>` | `TLS_CERT_MODE` | TLS 证书模式：`self-signed` / `letsencrypt` / `custom` |
| `--tls-domain <domain>` | `TLS_DOMAIN` | TLS 使用的域名（Let’s Encrypt 或自有证书模式必填） |
| `--keep-config` | `KEEP_CONFIG=true` | 仅更新内核，保留现有配置、防火墙与 systemd 服务 |
| `--force-rebuild-config` | `FORCE_REBUILD_CONFIG=true` | 强制覆盖现有配置，重新生成 config.json |
| `--rebuild-config-only` | `REBUILD_CONFIG_ONLY=true` | 只重建配置文件，不下载/更新内核 |
| `--add` | `ADD_TO_CONFIG=true` | 将新协议方案追加到现有 config.json（多入站并存） |
| `--uninstall` | - | 完整卸载 Xray、服务、配置与防火墙规则 |
| `--uninstall-config` | - | 卸载配置（含服务/防火墙），但保留内核与日志 |
| `--delete-config` | - | 仅删除配置文件与链接/端口记录，不动服务与内核 |

**示例：**
```bash
# 指定端口和 UUID 安装 Reality + KCP（默认方案）
curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh \
  | sudo bash -s -- --reality-port 443 --uuid "your-uuid-here"

# 仅更新内核，不改配置
curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh \
  | sudo bash -s -- --keep-config

# 添加新协议到现有配置（多入站共存）
curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh \
  | sudo bash -s -- --profile vmess-ws-tls --add

# 只重建配置，不重新下载内核
curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh \
  | sudo bash -s -- --rebuild-config-only --profile shadowsocks
```

### Windows 参数

Windows 脚本通过 PowerShell 参数传递：

| 参数 | 类型 | 说明 |
| :--- | :--- | :--- |
| `-Profile` | String | 协议方案名称，仅支持 `reality-kcp`(默认)、`reality-only`、`kcp-only`，其他值会报错 |
| `-RealityPort` | Int | Reality TCP 端口，默认随机可用端口 |
| `-VmessKcpPort` | Int | VMess mKCP UDP 端口，默认随机可用端口 |
| `-MainPort` | Int | 预留给后续多协议方案的主端口，当前三个 Profile 不使用，可忽略 |
| `-UUID` | String | 自定义 UUID，默认随机生成 |
| `-CoreVersion` | String | 指定 Xray 版本，如 `v1.8.4`，为空则使用最新版本 |
| `-Proxy` | String | 下载 Xray 时使用的代理，如 `http://127.0.0.1:1080` |
| `-RealityDest` | String | Reality 伪装目标，默认 `cloudflare.com:443` |
| `-RealityServerName` | String | Reality SNI 域名，默认 `cloudflare.com` |
| `-RealityShortId` | String | Reality shortId（2–16 位十六进制），为空则随机生成 |
| `-BaseDir` | String | 安装目录，默认 `$env:SystemDrive\xray` |
| `-KeepConfig` | Switch | 仅更新内核，保留现有配置、防火墙规则与计划任务 |
| `-ForceRebuildConfig` | Switch | 覆盖现有 config.json 并重建配置 |
| `-RebuildConfigOnly` | Switch | 只重建配置，不重新下载内核 |
| `-Uninstall` | Switch | 完整卸载 Xray（包含目录、计划任务、防火墙规则） |
| `-UninstallConfig` | Switch | 卸载配置（删除 config/links 和防火墙/计划任务），但保留内核与日志 |
| `-DeleteConfig` | Switch | 仅删除 config.json 和 links.txt，不动内核与防火墙 |
| `-Add` | Switch | 预留给多入站合并功能，目前主脚本尚未使用，可忽略 |

**示例：**
```powershell
# 在 PowerShell（管理员）中一键安装默认方案
Set-ExecutionPolicy Bypass -Scope Process -Force; \
  irm "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1" | iex

# 指定端口和 Profile 安装
irm "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1" | iex \
  "-RealityPort 443 -VmessKcpPort 20000 -Profile reality-only"

# 仅更新内核，不改配置
irm "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1" | iex \
  "-KeepConfig"

# 卸载（保留内核和日志，仅移除配置）
irm "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1" | iex \
  "-UninstallConfig"
```

---

## 📦 协议方案 (Profiles)

### Linux 支持的方案

Linux 主脚本已接入完整 Profile 库，交互菜单中可选择以下方案（1–19）：

1. **`reality-kcp`** (默认推荐): VLESS Reality (TCP) + VMess mKCP (UDP)
2. **`reality-only`**: 仅 VLESS Reality
3. **`kcp-only`**: 仅 VMess mKCP
4. `vmess-tcp` / `vmess-mkcp` / `vmess-quic`
5. `vmess-tcp-dynamic` / `vmess-mkcp-dynamic` / `vmess-quic-dynamic` (动态端口 20000–30000)
6. **TLS 系列 (证书模式可选：Let’s Encrypt / 自签名 / 自有证书):**
   - `vmess-ws-tls` / `vless-ws-tls` / `trojan-ws-tls`
   - `vmess-grpc-tls` / `vless-grpc-tls` / `trojan-grpc-tls`
   - `vmess-h2-tls` / `vless-h2-tls` / `trojan-h2-tls`
7. `shadowsocks` (AES-256-GCM)

### xray 管理命令

安装完成后，可运行 `xray` 命令进入交互式管理菜单：

```
【配置方案 1-19】      - 直接选择并添加新配置
【查看信息 101-102】   - 查看连接链接 / 当前配置
【服务管理 201-203】   - 查看状态 / 重启服务 / 更新内核
【卸载选项 301-303】   - 删除配置 / 卸载保留配置 / 彻底卸载
```

### Windows 支持的方案

当前 **Windows 主脚本** 仅实现以下三种核心方案（`-Profile` 参数）：

- **`reality-kcp`** (推荐): VLESS Reality (TCP) + VMess mKCP (UDP)
- **`reality-only`**: 仅 VLESS Reality
- **`kcp-only`**: 仅 VMess mKCP

Windows 端的 `xray-profiles-lib.ps1` 已包含与 Linux 一致的 Profile 生成逻辑，后续版本会逐步将更多协议接入主脚本。以本 README 所述为准：如果 Windows 主脚本尚未声明支持某个 Profile 名称，则直接传入该名称会报错。

---

## 📂 项目结构说明

为了便于维护，项目采用了模块化结构：

```text
.
├── xray-linux-airport.sh    # [入口] Linux 主脚本
├── xray-win-airport.ps1     # [入口] Windows 主脚本
├── xray-profiles-lib.sh     # [库] Linux 协议配置生成库
├── xray-profiles-lib.ps1    # [库] Windows 协议配置生成库 (内置于主脚本或单独加载)
├── linux/
│   ├── xray-common.sh       # 通用函数 (日志, 依赖安装)
│   ├── xray-ports.sh        # 端口管理 (随机端口, 占用检测)
│   ├── xray-manager.sh      # xray 管理命令脚本
│   └── xray-uninstall.sh    # 卸载逻辑
└── windows/
    ├── Xray-Ports.ps1       # Windows 端口管理
    ├── Xray-Manager.ps1     # Windows xray 管理命令脚本
    └── Xray-Uninstall.ps1   # Windows 卸载逻辑
```

- **一键安装时**：主脚本 (`xray-linux-airport.sh` / `xray-win-airport.ps1`) 内置了核心逻辑，并会自动从 GitHub 下载 `xray-profiles-lib.sh`，确保单文件运行能力。
- **本地开发时**：脚本会自动检测并加载 `linux/` 或 `windows/` 目录下的子模块，覆盖内置逻辑。

---

## 📝 License

GPL-3.0
