# Xray_Script

- **Linux 一键部署脚本**：`xray-linux-airport.sh`
- **Windows 一键部署脚本**：`xray-win-airport.ps1`

本项目提供在 Linux 和 Windows 环境下的一键部署脚本，旨在快速搭建 **VLESS + Reality 主节点**，并可选 **VMess mKCP + wechat-video 备用节点**。脚本采用模块化设计，便于维护和扩展，同时保留了对单行命令一键安装的完整支持。

---

## 🚀 快速开始 (Quick Start)

### Linux 一键安装

适用于 Ubuntu, Debian, CentOS, Rocky Linux 等常见发行版（需 systemd）。

```bash
# 标准安装（默认方案：VLESS Reality + VMess mKCP）
curl -fsSL https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh | sudo bash
```

**安装过程会自动执行：**
1. 检查 Root 权限与系统依赖（curl, unzip, openssl）。
2. 下载并加载最新的 Profile 配置库。
3. 下载 Xray-core (Linux-64)。
4. 生成配置、证书（如需）与 systemd 服务。
5. 输出客户端连接链接 (`vless://`, `vmess://`)。

### Windows 一键安装

适用于 Windows Server 2016/2019/2022 或 Windows 10/11。请使用 **管理员权限** 打开 PowerShell 执行：

```powershell
# 标准安装
Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1" | iex
```

**安装过程会自动执行：**
1. 下载 Xray-core (Windows-64)。
2. 生成配置文件与 Reality 密钥。
3. 配置防火墙规则（需系统支持 `New-NetFirewallRule`）。
4. 创建开机自启计划任务 (XrayServer)。
5. 输出客户端连接链接。

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
| `--uuid <uuid>` | `UUID` | 自定义 UUID，默认随机生成 |
| `--reality-dest <host:port>` | `REALITY_DEST` | 伪装目标，默认 `cloudflare.com:443` |
| `--reality-server-name <domain>` | `REALITY_SERVER_NAME` | SNI 域名，默认 `cloudflare.com` |
| `--base-dir <path>` | `BASE_DIR` | 安装目录，默认 `/opt/xray` |
| `--core-version <ver>` | `CORE_VERSION` | 指定 Xray 版本，如 `v1.8.4` |
| `--keep-config` | `KEEP_CONFIG=true` | 仅更新内核，保留现有配置 |
| `--force-rebuild-config` | `FORCE_REBUILD_CONFIG=true` | 强制覆盖现有配置 |
| `--uninstall` | - | 完整卸载 Xray 及配置 |

**示例：**
```bash
# 指定端口和 UUID 安装
curl -fsSL ... | sudo bash -s -- --reality-port 443 --uuid "your-uuid-here"

# 仅更新内核，不改配置
curl -fsSL ... | sudo bash -s -- --keep-config
```

### Windows 参数

Windows 脚本通过 PowerShell 参数传递：

| 参数 | 类型 | 说明 |
| :--- | :--- | :--- |
| `-Profile` | String | 仅支持 `reality-kcp` (默认), `reality-only`, `kcp-only` |
| `-RealityPort` | Int | Reality TCP 端口 |
| `-VmessKcpPort` | Int | VMess UDP 端口 |
| `-UUID` | String | 自定义 UUID |
| `-RealityDest` | String | 伪装目标 |
| `-BaseDir` | String | 安装目录，默认 `$env:SystemDrive\xray` |
| `-KeepConfig` | Switch | 仅更新内核，保留配置 |
| `-Uninstall` | Switch | 完整卸载 |

**示例：**
```powershell
# 指定参数安装
... | iex "& { $(irm ...) } -RealityPort 443 -Profile reality-only"
```

---

## 📦 协议方案 (Profiles)

### Windows 支持的方案
目前 Windows 脚本仅支持以下三种核心方案：
- **`reality-kcp`** (推荐): VLESS Reality (TCP) + VMess mKCP (UDP)
- **`reality-only`**: 仅 VLESS Reality
- **`kcp-only`**: 仅 VMess mKCP

### Linux 支持的方案
Linux 脚本功能更全，支持以下所有方案（交互模式下可选）：

1. **`reality-kcp`** (默认推荐)
2. **`reality-only`**
3. **`kcp-only`**
4. `vmess-tcp` / `vmess-mkcp` / `vmess-quic`
5. `vmess-tcp-dynamic` / `vmess-mkcp-dynamic` / `vmess-quic-dynamic` (动态端口)
6. **TLS 系列 (自动生成自签名证书):**
   - `vmess-ws-tls` / `vless-ws-tls` / `trojan-ws-tls`
   - `vmess-grpc-tls` / `vless-grpc-tls` / `trojan-grpc-tls`
   - `vmess-h2-tls` / `vless-h2-tls` / `trojan-h2-tls`
7. `shadowsocks` (AES-256-GCM)

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
│   └── xray-uninstall.sh    # 卸载逻辑
└── windows/
    ├── Xray-Ports.ps1       # Windows 端口管理
    └── Xray-Uninstall.ps1   # Windows 卸载逻辑
```

- **一键安装时**：主脚本 (`xray-linux-airport.sh` / `xray-win-airport.ps1`) 内置了核心逻辑，并会自动从 GitHub 下载 `xray-profiles-lib.sh`，确保单文件运行能力。
- **本地开发时**：脚本会自动检测并加载 `linux/` 或 `windows/` 目录下的子模块，覆盖内置逻辑。

---

## 📝 License

GPL-3.0
