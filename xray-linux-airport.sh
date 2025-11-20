#!/usr/bin/env bash

set -euo pipefail

#################################
# Parameters (env / cli)
#################################

REALITY_PORT="${REALITY_PORT:-0}"
VMESS_KCP_PORT="${VMESS_KCP_PORT:-0}"
UUID="${UUID:-}"
CORE_VERSION="${CORE_VERSION:-}"
PROXY="${PROXY:-}"
REALITY_DEST="${REALITY_DEST:-cloudflare.com:443}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-cloudflare.com}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"
BASE_DIR="${BASE_DIR:-/opt/xray}"
UNINSTALL="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reality-port)
      REALITY_PORT="$2"; shift 2;;
    --vmess-kcp-port)
      VMESS_KCP_PORT="$2"; shift 2;;
    --uuid)
      UUID="$2"; shift 2;;
    --core-version)
      CORE_VERSION="$2"; shift 2;;
    --proxy)
      PROXY="$2"; shift 2;;
    --reality-dest)
      REALITY_DEST="$2"; shift 2;;
    --reality-server-name)
      REALITY_SERVER_NAME="$2"; shift 2;;
    --reality-short-id)
      REALITY_SHORT_ID="$2"; shift 2;;
    --base-dir)
      BASE_DIR="$2"; shift 2;;
    --uninstall)
      UNINSTALL="true"; shift 1;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1;;
  esac
done

#################################
# Helper functions
#################################

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_INFO=$'\033[36m'
  COLOR_WARN=$'\033[33m'
  COLOR_ERROR=$'\033[31m'
  COLOR_RESET=$'\033[0m'

  COLOR_SUM_TITLE=$'\033[36m'
  COLOR_SUM_SECTION=$'\033[32m'
  COLOR_SUM_LABEL=$'\033[37m'
  COLOR_SUM_HIGHLIGHT=$'\033[35m'
  COLOR_SUM_URL=$'\033[33m'
else
  COLOR_INFO=""
  COLOR_WARN=""
  COLOR_ERROR=""
  COLOR_RESET=""

  COLOR_SUM_TITLE=""
  COLOR_SUM_SECTION=""
  COLOR_SUM_LABEL=""
  COLOR_SUM_HIGHLIGHT=""
  COLOR_SUM_URL=""
fi

log_info()  { printf "%b\n" "${COLOR_INFO}[$(date '+%F %T')] [INFO ] $*${COLOR_RESET}" >&2; }
log_warn()  { printf "%b\n" "${COLOR_WARN}[$(date '+%F %T')] [WARN ] $*${COLOR_RESET}" >&2; }
log_error() { printf "%b\n" "${COLOR_ERROR}[$(date '+%F %T')] [ERROR] $*${COLOR_RESET}" >&2; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "Please run this script as root (sudo)."
    exit 1
  fi
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt-get"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  else
    echo ""
  fi
}

install_dep() {
  local bin_name="$1" pkg_name="${2:-$1}"

  if command -v "$bin_name" >/dev/null 2>&1; then
    return 0
  fi

  local pm
  pm="$(detect_pkg_manager)"
  if [[ -z "$pm" ]]; then
    log_error "Package manager not found (apt-get/yum/dnf). Please install '$pkg_name' manually and retry."
    exit 1
  fi

  log_info "Installing dependency: $pkg_name (via $pm)"
  case "$pm" in
    apt-get)
      DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg_name" || {
        log_error "Failed to install $pkg_name via apt-get."
        exit 1
      }
      ;;
    yum|dnf)
      "$pm" install -y "$pkg_name" || {
        log_error "Failed to install $pkg_name via $pm."
        exit 1
      }
      ;;
  esac
}

ensure_deps() {
  install_dep curl curl
  install_dep unzip unzip
}

#################################
# Uninstall
#################################

uninstall_xray() {
  local service_name="xray-server"

  log_info "Uninstall mode: stopping service and removing files..."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload || true
    log_info "systemd service ${service_name} removed (if existed)."
  fi

  if [[ -d "$BASE_DIR" ]]; then
    rm -rf "$BASE_DIR"
    log_info "Removed directory: $BASE_DIR"
  else
    log_info "Base directory not found: $BASE_DIR"
  fi

  log_info "Xray has been uninstalled on Linux."
}

#################################
# Port helpers
#################################

ban_ports=(22 80 81 82 83 88 110 143 443 3306 6379 8080 8081 1080 1081 3389 53 25 587 465)

is_port_free() {
  local port="$1" proto="$2"
  if [[ "$proto" == "tcp" ]]; then
    if ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | grep -qE ":${port}$"; then
      return 1
    fi
  else
    if ss -lun 2>/dev/null | awk 'NR>1{print $4}' | grep -qE ":${port}$"; then
      return 1
    fi
  fi
  return 0
}

random_port() {
  local proto="$1" p
  while true; do
    p=$((RANDOM % 50000 + 10000))
    for b in "${ban_ports[@]}"; do
      [[ "$p" == "$b" ]] && continue 2
    done
    if is_port_free "$p" "$proto"; then
      echo "$p"; return 0
    fi
  done
}

ensure_port() {
  local port="$1" proto="$2"
  if [[ -z "$port" || "$port" == "0" ]]; then
    port="$(random_port "$proto")"
    log_info "No $proto port specified, using random free port: $port"
  else
    if ! is_port_free "$port" "$proto"; then
      local old="$port"
      port="$(random_port "$proto")"
      log_warn "Port $old ($proto) is in use, changed to: $port"
    fi
  fi
  echo "$port"
}

#################################
# Main
#################################

require_root

if [[ "$UNINSTALL" == "true" ]]; then
  uninstall_xray
  exit 0
fi

ensure_deps

if [[ -z "$UUID" ]]; then
  if command -v uuidgen >/dev/null 2>&1; then
    UUID="$(uuidgen)"
  else
    UUID="$(cat /proc/sys/kernel/random/uuid)"
  fi
  log_info "Generated UUID: $UUID"
fi

REALITY_PORT="$(ensure_port "$REALITY_PORT" tcp)"
VMESS_KCP_PORT="$(ensure_port "$VMESS_KCP_PORT" udp)"
if [[ "$REALITY_PORT" == "$VMESS_KCP_PORT" ]]; then
  VMESS_KCP_PORT="$(ensure_port 0 udp)"
  log_warn "VMess KCP port conflicts with Reality port, changed to: $VMESS_KCP_PORT"
fi

if [[ -z "$REALITY_SHORT_ID" ]]; then
  REALITY_SHORT_ID="$(openssl rand -hex 4 2>/dev/null || od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  log_info "Generated Reality shortId: $REALITY_SHORT_ID"
fi

CORE_REPO="XTLS/Xray-core"
CORE_FILE_NAME="Xray-linux-64.zip"
CORE_BIN_DIR="${BASE_DIR}/bin"
LOG_DIR="${BASE_DIR}/log"
CONFIG_PATH="${BASE_DIR}/config.json"
LINKS_FILE="${BASE_DIR}/links.txt"
CORE_ZIP_PATH="${BASE_DIR}/${CORE_FILE_NAME}"
CORE_EXE="${CORE_BIN_DIR}/xray"
SERVICE_NAME="xray-server"

mkdir -p "$BASE_DIR" "$CORE_BIN_DIR" "$LOG_DIR"

if [[ -n "$CORE_VERSION" ]]; then
  CORE_VERSION_NORM="v${CORE_VERSION#v}"
  CORE_URL="https://github.com/${CORE_REPO}/releases/download/${CORE_VERSION_NORM}/${CORE_FILE_NAME}"
  log_info "Using Xray version: $CORE_VERSION_NORM"
else
  CORE_URL="https://github.com/${CORE_REPO}/releases/latest/download/${CORE_FILE_NAME}"
  log_info "Using latest Xray from $CORE_REPO"
fi

log_info "Downloading Xray from: $CORE_URL"

curl_args=("-fL" "$CORE_URL" -o "$CORE_ZIP_PATH")
if [[ -n "$PROXY" ]]; then
  log_info "Using proxy for download: $PROXY"
  curl_args=("-fL" "$CORE_URL" -x "$PROXY" -o "$CORE_ZIP_PATH")
fi

if ! command -v curl >/dev/null 2>&1; then
  log_error "curl is required but not found. Please install curl and retry."
  exit 1
fi

if ! curl "${curl_args[@]}"; then
  log_error "Failed to download Xray core."
  exit 1
fi

log_info "Extracting Xray to $CORE_BIN_DIR"
rm -rf "$CORE_BIN_DIR"/*
if command -v unzip >/dev/null 2>&1; then
  unzip -o "$CORE_ZIP_PATH" -d "$CORE_BIN_DIR" >/dev/null
else
  log_error "unzip is required but not found. Please install unzip and retry."
  exit 1
fi

if [[ ! -x "$CORE_EXE" ]]; then
  log_error "xray executable not found after extraction: $CORE_EXE"
  exit 1
fi

log_info "Generating Reality X25519 key pair (xray x25519)..."
if ! x25519_output="$($CORE_EXE x25519 2>&1)"; then
  log_error "Failed to run 'xray x25519'"
  echo "$x25519_output"
  exit 1
fi

reality_priv="$(printf '%s
' "$x25519_output" | sed -n 's/^Private key:[[:space:]]*\([^[:space:]]\+\).*/\1/p')"
reality_pub="$(printf '%s
' "$x25519_output" | sed -n 's/^Public key:[[:space:]]*\([^[:space:]]\+\).*/\1/p')"
if [[ -z "$reality_priv" || -z "$reality_pub" ]]; then
  reality_priv="$(printf '%s
' "$x25519_output" | sed -n 's/^PrivateKey:[[:space:]]*\([^[:space:]]\+\).*/\1/p')"
  reality_pub="$(printf '%s
' "$x25519_output" | sed -n 's/^Password:[[:space:]]*\([^[:space:]]\+\).*/\1/p')"
fi

if [[ -z "$reality_priv" || -z "$reality_pub" ]]; then
  log_error "Could not parse Reality keys from 'xray x25519' output."
  echo "$x25519_output"
  exit 1
fi

log_info "Reality keys generated."

log_info "Building config: $CONFIG_PATH"

cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${REALITY_PORT},
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST}",
          "xver": 0,
          "serverNames": ["${REALITY_SERVER_NAME}"],
          "privateKey": "${reality_priv}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "in-vless-reality"
    },
    {
      "port": ${VMESS_KCP_PORT},
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0,
            "level": 0
          }
        ]
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 20,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "wechat-video"
          }
        }
      },
      "tag": "in-vmess-kcp-wechatvideo"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF

chmod 600 "$CONFIG_PATH"

log_info "Configuring firewall (if available)"

if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --add-port=${REALITY_PORT}/tcp --permanent || true
  firewall-cmd --add-port=${VMESS_KCP_PORT}/udp --permanent || true
  firewall-cmd --reload || true
  log_info "Opened ports in firewalld: ${REALITY_PORT}/tcp, ${VMESS_KCP_PORT}/udp"
elif command -v ufw >/dev/null 2>&1; then
  ufw allow ${REALITY_PORT}/tcp || true
  ufw allow ${VMESS_KCP_PORT}/udp || true
  log_info "Opened ports in ufw: ${REALITY_PORT}/tcp, ${VMESS_KCP_PORT}/udp"
else
  log_warn "No known firewall manager detected (firewalld/ufw). Please ensure ports ${REALITY_PORT}/tcp and ${VMESS_KCP_PORT}/udp are open manually if needed."
fi

log_info "Configuring systemd service: ${SERVICE_NAME}"

if ! command -v systemctl >/dev/null 2>&1; then
  log_warn "systemd not found. Starting xray directly in background, but it will NOT persist across reboot."
  nohup "$CORE_EXE" run -config "$CONFIG_PATH" >>"${LOG_DIR}/xray.log" 2>&1 &
else
  cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Xray Server (VLESS Reality + VMess mKCP)
After=network.target

[Service]
Type=simple
User=root
ExecStart=${CORE_EXE} run -config ${CONFIG_PATH}
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ${SERVICE_NAME}
  systemctl restart ${SERVICE_NAME}

  sleep 1
  if systemctl is-active --quiet ${SERVICE_NAME}; then
    log_info "systemd service ${SERVICE_NAME} is running."
  else
    log_warn "systemd service ${SERVICE_NAME} is not active. Please check: journalctl -u ${SERVICE_NAME} -xe"
  fi
fi

public_ip=""
if command -v curl >/dev/null 2>&1; then
  public_ip="$(curl -s https://api.ipify.org)" || true
fi
if [[ -z "$public_ip" ]]; then
  public_ip="(public IP unknown, please check yourself)"
fi

vless_name="xray.owokit.com-VLESS-Reality"

vless_url="vless://${UUID}@${public_ip}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${reality_pub}&sid=${REALITY_SHORT_ID}&spx=%2F&type=tcp#${vless_name}"

vmess_name="xray.owokit.com-VMess-mKCP-wechat-video"

vmess_json=$(cat <<JSON
{
  "v": "2",
  "ps": "${vmess_name}",
  "add": "${public_ip}",
  "port": "${VMESS_KCP_PORT}",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "kcp",
  "type": "wechat-video",
  "host": "",
  "path": "",
  "tls": "",
  "sni": "",
  "alpn": "",
  "fp": ""
}
JSON
)

vmess_b64="$(printf '%s' "$vmess_json" | base64 -w0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
vmess_url="vmess://${vmess_b64}"

{
  echo "$vless_url"
  echo "$vmess_url"
} >"$LINKS_FILE"

log_info "All URLs have been saved to: $LINKS_FILE"

printf "\n%s================= Xray server deployed (Linux) =================%s\n" "${COLOR_SUM_TITLE}" "${COLOR_RESET}"
printf "%sServer public IP: %s%s\n\n" "${COLOR_SUM_TITLE}" "${public_ip}" "${COLOR_RESET}"

printf "%s[1] VLESS Reality (main node)%s\n" "${COLOR_SUM_SECTION}" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "Address:" "${public_ip}" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "Port:" "${REALITY_PORT}" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "UUID:" "${UUID}" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "Flow:" "xtls-rprx-vision" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "Dest:" "${REALITY_DEST}" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "SNI:" "${REALITY_SERVER_NAME}" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "shortId:" "${REALITY_SHORT_ID}" "${COLOR_RESET}"
printf "%s  %-11s%s\n" "${COLOR_SUM_LABEL}" "publicKey:" "${COLOR_RESET}"
printf "%s    %s%s\n" "${COLOR_SUM_HIGHLIGHT}" "${reality_pub}" "${COLOR_RESET}"
printf "%s  URL: %s" "${COLOR_SUM_LABEL}" "${COLOR_RESET}"
printf "%s%s%s\n" "${COLOR_SUM_URL}" "${vless_url}" "${COLOR_RESET}"

printf "\n%s[2] VMess mKCP + wechat-video (backup, only try when TCP/Reality is not available; UDP may be limited by ISP/QoS)%s\n" "${COLOR_SUM_SECTION}" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "Address:" "${public_ip}" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "Port(UDP):" "${VMESS_KCP_PORT}" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "UUID:" "${UUID}" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "Transport:" "kcp" "${COLOR_RESET}"
printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "Header:" "wechat-video" "${COLOR_RESET}"
printf "%s  URL: %s" "${COLOR_SUM_LABEL}" "${COLOR_RESET}"
printf "%s%s%s\n" "${COLOR_SUM_URL}" "${vmess_url}" "${COLOR_RESET}"

printf "\n%slinks file:   %s%s\n" "${COLOR_SUM_LABEL}" "${LINKS_FILE}" "${COLOR_RESET}"
printf "%sconfig file:  %s%s\n" "${COLOR_SUM_LABEL}" "${CONFIG_PATH}" "${COLOR_RESET}"
printf "%slog dir:      %s%s\n" "${COLOR_SUM_LABEL}" "${LOG_DIR}" "${COLOR_RESET}"
printf "%sservice:      %s (systemd)%s\n" "${COLOR_SUM_LABEL}" "${SERVICE_NAME}" "${COLOR_RESET}"
printf "%s========================================================%s\n" "${COLOR_SUM_TITLE}" "${COLOR_RESET}"
