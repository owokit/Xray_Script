#!/usr/bin/env bash
set -euo pipefail

REALITY_PORT="${REALITY_PORT:-443}"
VMESS_KCP_PORT="${VMESS_KCP_PORT:-0}"
UUID="${UUID:-}"
CORE_VERSION="${CORE_VERSION:-}"
PROXY="${PROXY:-}"
REALITY_DEST="${REALITY_DEST:-www.microsoft.com:443}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.microsoft.com}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"
BASE_DIR="${BASE_DIR:-/opt/xray}"
PROFILE="${PROFILE:-reality-kcp}"
FORCE_REBUILD_CONFIG="${FORCE_REBUILD_CONFIG:-false}"
KEEP_CONFIG="${KEEP_CONFIG:-false}"
ENABLE_SWAP="${ENABLE_SWAP:-auto}"
SWAP_SIZE="${SWAP_SIZE:-1G}"
SWAP_FILE="${SWAP_FILE:-/swapfile}"
LOW_MEM_SWAP_THRESHOLD_MIB="${LOW_MEM_SWAP_THRESHOLD_MIB:-1024}"
UNINSTALL="false"
REMOVE_SWAP="false"
FORCE_INSTALL_MANAGER="${FORCE_INSTALL_MANAGER:-false}"

usage() {
  cat <<'USAGE'
Usage:
  sudo bash xray-linux-airport.sh [options]

Main profiles:
  --profile reality-kcp        VLESS Reality TCP + VMess mKCP UDP (default)
  --profile reality-only       VLESS Reality TCP only
  --profile kcp-only           VMess mKCP UDP only

Key options:
  --reality-port <port>        Default: 443
  --vmess-kcp-port <port>      Default: random free UDP port
  --reality-dest <host:port>   Default: www.microsoft.com:443
  --reality-server-name <sni>  Default: www.microsoft.com
  --enable-swap                Force swap handling on
  --no-swap                    Disable automatic swap handling
  --swap-size <size>           Default: 1G
  --swap-file <path>           Default: /swapfile
  --force-rebuild-config       Overwrite existing config.json
  --keep-config                Update core only and keep existing config
  --uninstall                  Remove Xray files/service/firewall rules
  --remove-swap                With --uninstall, also remove managed swapfile
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --reality-port) REALITY_PORT="$2"; shift 2 ;;
    --vmess-kcp-port) VMESS_KCP_PORT="$2"; shift 2 ;;
    --uuid) UUID="$2"; shift 2 ;;
    --core-version) CORE_VERSION="$2"; shift 2 ;;
    --proxy) PROXY="$2"; shift 2 ;;
    --reality-dest) REALITY_DEST="$2"; shift 2 ;;
    --reality-server-name) REALITY_SERVER_NAME="$2"; shift 2 ;;
    --reality-short-id) REALITY_SHORT_ID="$2"; shift 2 ;;
    --base-dir) BASE_DIR="$2"; shift 2 ;;
    --enable-swap) ENABLE_SWAP="true"; shift ;;
    --no-swap) ENABLE_SWAP="false"; shift ;;
    --swap-size) SWAP_SIZE="$2"; shift 2 ;;
    --swap-file) SWAP_FILE="$2"; shift 2 ;;
    --force-rebuild-config) FORCE_REBUILD_CONFIG="true"; shift ;;
    --keep-config) KEEP_CONFIG="true"; shift ;;
    --uninstall) UNINSTALL="true"; shift ;;
    --remove-swap) REMOVE_SWAP="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

log_info()  { printf '[%s] [INFO ] %s\n' "$(date '+%F %T')" "$*" >&2; }
log_warn()  { printf '[%s] [WARN ] %s\n' "$(date '+%F %T')" "$*" >&2; }
log_error() { printf '[%s] [ERROR] %s\n' "$(date '+%F %T')" "$*" >&2; }

require_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]] || { log_error "Please run as root (sudo)."; exit 1; }; }

validate_base_dir() {
  [[ -n "$BASE_DIR" && "$BASE_DIR" == /* && "$BASE_DIR" != "/" ]] || { log_error "BASE_DIR must be a non-root absolute path."; exit 1; }
  case "$BASE_DIR" in /root|/home|/usr|/var|/etc|/opt|/tmp) log_error "Refusing system directory as BASE_DIR: $BASE_DIR"; exit 1 ;; esac
}

validate_port() {
  local name="$1" value="$2"
  [[ -z "$value" || "$value" == "0" ]] && return 0
  [[ "$value" =~ ^[0-9]+$ ]] || { log_error "Invalid $name: $value"; exit 1; }
  (( value >= 1 && value <= 65535 )) || { log_error "Invalid $name range: $value"; exit 1; }
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then echo apt-get
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v yum >/dev/null 2>&1; then echo yum
  else echo ""; fi
}

install_dep() {
  local bin="$1" pkg="${2:-$1}" pm
  command -v "$bin" >/dev/null 2>&1 && return 0
  pm="$(detect_pkg_manager)"
  [[ -n "$pm" ]] || { log_error "No package manager found; install $pkg manually."; exit 1; }
  log_info "Installing dependency: $pkg"
  case "$pm" in
    apt-get) DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" ;;
    dnf|yum) "$pm" install -y "$pkg" ;;
  esac
}

ensure_deps() {
  install_dep curl curl
  install_dep unzip unzip
  install_dep openssl openssl
  install_dep jq jq
  command -v ss >/dev/null 2>&1 || install_dep ss iproute2 || true
}

swap_size_to_mib() {
  local s="${1// /}" n u
  [[ "$s" =~ ^([0-9]+)([KkMmGgTt]?)([Ii]?[Bb])?$ ]] || { log_error "Invalid swap size: $1"; exit 1; }
  n="${BASH_REMATCH[1]}"; u="${BASH_REMATCH[2],,}"
  case "$u" in
    k) echo $(((n + 1023) / 1024)) ;;
    ""|m) echo "$n" ;;
    g) echo $((n * 1024)) ;;
    t) echo $((n * 1024 * 1024)) ;;
    *) log_error "Unsupported swap unit: $1"; exit 1 ;;
  esac
}

detect_total_mem_mib() { awk '/^MemTotal:/ {print int(($2+1023)/1024); exit}' /proc/meminfo 2>/dev/null || echo 0; }
detect_swap_total_mib() { awk 'NR>1 {sum+=$3} END {print int((sum+1023)/1024)}' /proc/swaps 2>/dev/null || echo 0; }

is_swapfile_active() {
  awk -v f="$1" 'NR>1 && $1 == f {found=1} END {exit(found ? 0 : 1)}' /proc/swaps 2>/dev/null
}

append_fstab_once() {
  local f="$1" esc
  touch /etc/fstab
  esc="$(printf '%s' "$f" | sed 's/[.[\*^$()+?{}|]/\\&/g')"
  grep -qE "^[[:space:]]*${esc}[[:space:]]+none[[:space:]]+swap[[:space:]]" /etc/fstab || printf '%s none swap sw 0 0\n' "$f" >> /etc/fstab
}

ensure_swap() {
  local mode="${ENABLE_SWAP,,}" mem swap size_mib
  case "$mode" in true|false|auto|1|yes|on|0|no|off) ;; *) log_error "Invalid ENABLE_SWAP: $ENABLE_SWAP"; exit 1 ;; esac
  case "$mode" in 1|yes|on) mode=true ;; 0|no|off) mode=false ;; esac
  mem="$(detect_total_mem_mib)"; swap="$(detect_swap_total_mib)"
  log_info "Memory total: ${mem} MiB"
  log_info "Swap total: ${swap} MiB"
  log_info "Swap mode: ${mode}; threshold: ${LOW_MEM_SWAP_THRESHOLD_MIB} MiB; file: ${SWAP_FILE}; size: ${SWAP_SIZE}"
  [[ "$mode" == "false" ]] && { log_info "Swap handling disabled."; return 0; }
  (( swap > 0 )) && { log_info "Existing swap detected; no new swapfile will be created."; return 0; }
  if [[ "$mode" == "auto" && "$mem" -ge "$LOW_MEM_SWAP_THRESHOLD_MIB" ]]; then
    log_info "Memory is >= ${LOW_MEM_SWAP_THRESHOLD_MIB} MiB; automatic swap creation skipped."
    return 0
  fi
  if is_swapfile_active "$SWAP_FILE"; then append_fstab_once "$SWAP_FILE"; return 0; fi
  if [[ -e "$SWAP_FILE" ]]; then
    log_info "Existing inactive swapfile found; attempting to activate: $SWAP_FILE"
    chmod 600 "$SWAP_FILE"
    swapon "$SWAP_FILE" || { log_error "Existing $SWAP_FILE cannot be activated; refusing to overwrite."; exit 1; }
    append_fstab_once "$SWAP_FILE"
    return 0
  fi
  size_mib="$(swap_size_to_mib "$SWAP_SIZE")"
  log_info "Creating swapfile: $SWAP_FILE (${SWAP_SIZE})"
  if command -v fallocate >/dev/null 2>&1; then fallocate -l "$SWAP_SIZE" "$SWAP_FILE" || dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$size_mib" status=none
  else dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$size_mib" status=none; fi
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE" >/dev/null
  swapon "$SWAP_FILE"
  append_fstab_once "$SWAP_FILE"
  log_info "Swapfile created and activated: $SWAP_FILE"
}

remove_swapfile_if_requested() {
  [[ "$REMOVE_SWAP" == "true" ]] || return 0
  log_warn "Removing managed swapfile: $SWAP_FILE"
  is_swapfile_active "$SWAP_FILE" && swapoff "$SWAP_FILE"
  if [[ -f /etc/fstab ]]; then awk -v f="$SWAP_FILE" '!(($1==f) && ($3=="swap")) {print}' /etc/fstab > /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab; fi
  rm -f "$SWAP_FILE"
}

is_port_free() {
  local port="$1" proto="$2"
  if command -v ss >/dev/null 2>&1; then
    if [[ "$proto" == tcp ]]; then ! ss -ltn | awk 'NR>1{print $4}' | grep -qE ":${port}$"
    else ! ss -lun | awk 'NR>1{print $4}' | grep -qE ":${port}$"; fi
  else return 0; fi
}

random_port() {
  local proto="$1" p
  while :; do p=$((RANDOM % 50000 + 10000)); case "$p" in 22|53|80|443|3389) continue ;; esac; is_port_free "$p" "$proto" && { echo "$p"; return 0; }; done
}

ensure_port() {
  local p="$1" proto="$2"
  if [[ -z "$p" || "$p" == "0" ]]; then random_port "$proto"; return 0; fi
  if is_port_free "$p" "$proto"; then echo "$p"; else log_warn "$proto port $p is in use; using random port."; random_port "$proto"; fi
}

uninstall_xray() {
  local service=xray-server ports_file="${BASE_DIR}/ports.env" ports=""
  log_info "Uninstall mode: removing Xray service and files. Swap is preserved unless --remove-swap is set."
  systemctl stop "$service" 2>/dev/null || true
  systemctl disable "$service" 2>/dev/null || true
  rm -f "/etc/systemd/system/${service}.service"
  systemctl daemon-reload 2>/dev/null || true
  if [[ -f "$ports_file" ]]; then ports="$(grep '^FIREWALL_PORTS=' "$ports_file" | cut -d= -f2- || true)"; fi
  if command -v ufw >/dev/null 2>&1; then for ps in $ports; do ufw delete allow "$ps" || true; done; fi
  if command -v firewall-cmd >/dev/null 2>&1; then for ps in $ports; do firewall-cmd --remove-port="$ps" --permanent || true; done; firewall-cmd --reload || true; fi
  pkill -x xray 2>/dev/null || true
  rm -rf "$BASE_DIR"
  remove_swapfile_if_requested
  log_info "Xray uninstalled."
}

download_core() {
  local repo="XTLS/Xray-core" zip="Xray-linux-64.zip" url args
  CORE_BIN_DIR="${BASE_DIR}/bin"; LOG_DIR="${BASE_DIR}/log"; CONFIG_PATH="${BASE_DIR}/config.json"; LINKS_FILE="${BASE_DIR}/links.txt"; PORTS_FILE="${BASE_DIR}/ports.env"; CORE_EXE="${CORE_BIN_DIR}/xray"; SERVICE_NAME="xray-server"
  mkdir -p "$BASE_DIR" "$CORE_BIN_DIR" "$LOG_DIR"
  if [[ -n "$CORE_VERSION" ]]; then url="https://github.com/${repo}/releases/download/v${CORE_VERSION#v}/${zip}"; else url="https://github.com/${repo}/releases/latest/download/${zip}"; fi
  [[ "$KEEP_CONFIG" == "true" && -x "$CORE_EXE" ]] && log_info "Existing config will be kept; Xray core will be updated."
  log_info "Downloading Xray from: $url"
  args=(-fL "$url" -o "${BASE_DIR}/${zip}"); [[ -n "$PROXY" ]] && args=(-fL "$url" -x "$PROXY" -o "${BASE_DIR}/${zip}")
  curl "${args[@]}"
  rm -rf "${CORE_BIN_DIR:?}"/*
  unzip -o "${BASE_DIR}/${zip}" -d "$CORE_BIN_DIR" >/dev/null
  [[ -x "$CORE_EXE" ]] || { log_error "xray executable not found: $CORE_EXE"; exit 1; }
}

generate_uuid() { if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr '[:upper:]' '[:lower:]'; else cat /proc/sys/kernel/random/uuid; fi; }

generate_keys() {
  [[ -n "$UUID" ]] || { UUID="$(generate_uuid)"; log_info "No UUID specified, generated: $UUID"; }
  if [[ "$PROFILE" == reality* ]]; then
    [[ -n "$REALITY_SHORT_ID" ]] || { REALITY_SHORT_ID="$(openssl rand -hex 4)"; log_info "No Reality shortId specified, generated: $REALITY_SHORT_ID"; }
    local out line
    out="$($CORE_EXE x25519 2>&1)"
    reality_priv=""; reality_pub=""
    while IFS= read -r line; do
      line="${line%$'\r'}"
      case "$line" in
        "Private key:"*|"PrivateKey:"*) reality_priv="${line#*:}"; reality_priv="${reality_priv#${reality_priv%%[![:space:]]*}}" ;;
        "Public key:"*|"Password:"*|"Password (PublicKey):"*) reality_pub="${line#*:}"; reality_pub="${reality_pub#${reality_pub%%[![:space:]]*}}" ;;
      esac
    done <<< "$out"
    [[ -n "$reality_priv" && -n "$reality_pub" ]] || { log_error "Could not parse xray x25519 output."; echo "$out"; exit 1; }
  fi
}

build_config() {
  local inbounds='[]' firewall_ports='' display=''
  case "$PROFILE" in
    reality-kcp|reality-only)
      REALITY_PORT="$(ensure_port "$REALITY_PORT" tcp)"
      inbounds="$(jq -n --argjson port "$REALITY_PORT" --arg id "$UUID" --arg dest "$REALITY_DEST" --arg sni "$REALITY_SERVER_NAME" --arg pk "$reality_priv" --arg sid "$REALITY_SHORT_ID" '[{port:$port,listen:"0.0.0.0",protocol:"vless",settings:{clients:[{id:$id,flow:"xtls-rprx-vision"}],decryption:"none"},streamSettings:{network:"tcp",security:"reality",realitySettings:{show:false,dest:$dest,xver:0,serverNames:[$sni],privateKey:$pk,shortIds:[$sid]},sockopt:{tcpFastOpen:true,tcpNoDelay:true}},sniffing:{enabled:true,destOverride:["http","tls"]},tag:"in-vless-reality"}]')"
      firewall_ports="${REALITY_PORT}/tcp"; display="VLESS Reality"
      if [[ "$PROFILE" == "reality-kcp" ]]; then
        VMESS_KCP_PORT="$(ensure_port "$VMESS_KCP_PORT" udp)"
        inbounds="$(jq --argjson port "$VMESS_KCP_PORT" --arg id "$UUID" '. + [{port:$port,listen:"0.0.0.0",protocol:"vmess",settings:{clients:[{id:$id,alterId:0,level:0}]},streamSettings:{network:"kcp",kcpSettings:{mtu:1350,tti:20,uplinkCapacity:5,downlinkCapacity:20,congestion:false,readBufferSize:2,writeBufferSize:2},finalmask:{udp:[{type:"header-wechat",settings:{}}]}},tag:"in-vmess-kcp-wechatvideo"}]' <<< "$inbounds")"
        firewall_ports="$firewall_ports ${VMESS_KCP_PORT}/udp"; display="VLESS Reality + VMess mKCP"
      fi ;;
    kcp-only)
      VMESS_KCP_PORT="$(ensure_port "$VMESS_KCP_PORT" udp)"
      inbounds="$(jq -n --argjson port "$VMESS_KCP_PORT" --arg id "$UUID" '[{port:$port,listen:"0.0.0.0",protocol:"vmess",settings:{clients:[{id:$id,alterId:0,level:0}]},streamSettings:{network:"kcp",kcpSettings:{mtu:1350,tti:20,uplinkCapacity:5,downlinkCapacity:20,congestion:false,readBufferSize:2,writeBufferSize:2},finalmask:{udp:[{type:"header-wechat",settings:{}}]}},tag:"in-vmess-kcp-wechatvideo"}]')"
      firewall_ports="${VMESS_KCP_PORT}/udp"; display="VMess mKCP" ;;
    *) log_error "Unsupported profile: $PROFILE. Supported: reality-kcp, reality-only, kcp-only."; exit 1 ;;
  esac
  PROFILE_DISPLAY_NAME="$display"; FIREWALL_PORTS="$firewall_ports"
  jq -n --arg access "${LOG_DIR}/access.log" --arg error "${LOG_DIR}/error.log" --argjson inbounds "$inbounds" '{log:{access:$access,error:$error,loglevel:"warning"},inbounds:$inbounds,outbounds:[{protocol:"freedom",settings:{},tag:"direct"},{protocol:"blackhole",settings:{},tag:"blocked"}],routing:{domainStrategy:"AsIs",rules:[]}}' > "$CONFIG_PATH"
  chmod 600 "$CONFIG_PATH"
  { echo "PROFILE=${PROFILE}"; echo "REALITY_PORT=${REALITY_PORT:-}"; echo "VMESS_KCP_PORT=${VMESS_KCP_PORT:-}"; echo "FIREWALL_PORTS=${FIREWALL_PORTS}"; } > "$PORTS_FILE"
  chmod 600 "$PORTS_FILE"
}

configure_firewall() {
  [[ -n "${FIREWALL_PORTS:-}" ]] || return 0
  log_info "Configuring firewall ports: $FIREWALL_PORTS"
  if command -v firewall-cmd >/dev/null 2>&1; then for ps in $FIREWALL_PORTS; do firewall-cmd --add-port="$ps" --permanent || true; done; firewall-cmd --reload || true
  elif command -v ufw >/dev/null 2>&1; then for ps in $FIREWALL_PORTS; do ufw allow "$ps" || true; done
  else log_warn "No known firewall manager detected. Ensure ports are open manually: $FIREWALL_PORTS"; fi
}

configure_service() {
  local desc="Xray Server (${PROFILE_DISPLAY_NAME:-$PROFILE})"
  if ! command -v systemctl >/dev/null 2>&1; then nohup "$CORE_EXE" run -config "$CONFIG_PATH" >>"${LOG_DIR}/xray.log" 2>&1 & return 0; fi
  cat >"/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=${desc}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${CORE_EXE} run -config ${CONFIG_PATH}
Restart=on-failure
RestartSec=10s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
  sleep 1
  systemctl is-active --quiet "$SERVICE_NAME" && log_info "systemd service $SERVICE_NAME is running." || log_warn "systemd service $SERVICE_NAME is not active. Check: journalctl -u $SERVICE_NAME -xe"
}

urlencode() { local s="$1" out="" c h i; for ((i=0;i<${#s};i++)); do c="${s:i:1}"; case "$c" in [a-zA-Z0-9.~_-]) out+="$c" ;; *) printf -v h '%%%02X' "'$c"; out+="$h" ;; esac; done; printf '%s' "$out"; }

detect_public_ip() { curl -s https://api.ipify.org || curl -s https://ifconfig.me || echo '(public IP unknown)'; }

generate_links() {
  local ip="$1" fm_json fm vmess_json vmess_b64
  : > "$LINKS_FILE"
  if [[ "$PROFILE" == reality-kcp || "$PROFILE" == reality-only ]]; then
    printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&spx=%%2F&type=tcp#xray.owokit.com-VLESS-Reality\n' "$UUID" "$ip" "$REALITY_PORT" "$REALITY_SERVER_NAME" "$reality_pub" "$REALITY_SHORT_ID" >> "$LINKS_FILE"
  fi
  if [[ "$PROFILE" == reality-kcp || "$PROFILE" == kcp-only ]]; then
    fm_json='{"udp":[{"type":"header-wechat","settings":{}}]}'
    fm="$(urlencode "$fm_json")"
    vmess_json="$(jq -n --arg ps 'xray.owokit.com-VMess-mKCP-wechat-video' --arg add "$ip" --arg port "$VMESS_KCP_PORT" --arg id "$UUID" --arg fm "$fm" '{v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:"0",scy:"auto",net:"kcp",type:"wechat-video",fm:$fm,host:"",path:"",tls:"",sni:"",alpn:"",fp:""}')"
    vmess_b64="$(printf '%s' "$vmess_json" | base64 -w0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
    printf 'vmess://%s\n' "$vmess_b64" >> "$LINKS_FILE"
  fi
  chmod 600 "$LINKS_FILE"
}

print_summary() {
  local ip="$1"
  echo
  echo "================= Xray server deployed (Linux) ================="
  echo "Server public IP: $ip"
  echo "Profile: ${PROFILE_DISPLAY_NAME:-$PROFILE}"
  if [[ "$PROFILE" == reality-kcp || "$PROFILE" == reality-only ]]; then
    echo
    echo "[1] VLESS Reality"
    echo "  Address:    $ip"
    echo "  Port:       $REALITY_PORT"
    echo "  UUID:       $UUID"
    echo "  Flow:       xtls-rprx-vision"
    echo "  Dest:       $REALITY_DEST"
    echo "  SNI:        $REALITY_SERVER_NAME"
    echo "  shortId:    $REALITY_SHORT_ID"
    echo "  publicKey:  $reality_pub"
  fi
  if [[ "$PROFILE" == reality-kcp || "$PROFILE" == kcp-only ]]; then
    echo
    echo "[2] VMess mKCP + wechat-video"
    echo "  Address:    $ip"
    echo "  Port(UDP):  $VMESS_KCP_PORT"
    echo "  UUID:       $UUID"
  fi
  echo
  echo "URLs:"; cat "$LINKS_FILE"
  echo
  echo "links file:   $LINKS_FILE"
  echo "config file:  $CONFIG_PATH"
  echo "ports file:   $PORTS_FILE"
  echo "log dir:      $LOG_DIR"
  echo "service:      $SERVICE_NAME (systemd)"
  echo "========================================================"
  log_info "Post-check: systemctl status $SERVICE_NAME --no-pager; ss -lntup | grep -E ':${REALITY_PORT}|xray'; ss -lunp | grep -E ':${VMESS_KCP_PORT}|xray'; free -h; swapon --show"
}

install_manager_command() {
  local url="https://github.com/owokit/Xray_Script/raw/main/linux/xray-manager.sh?nocache=$(date +%s)" path="/usr/local/bin/xray"
  [[ ! -f "$path" || "$FORCE_INSTALL_MANAGER" == "true" ]] || return 0
  if curl -fsSL "$url" -o "$path" 2>/dev/null; then chmod +x "$path"; log_info "Installed management command: xray"; else log_warn "Manager command install failed; Xray service is not affected."; fi
}

require_root
validate_base_dir
validate_port REALITY_PORT "$REALITY_PORT"
validate_port VMESS_KCP_PORT "$VMESS_KCP_PORT"

if [[ "$UNINSTALL" == "true" ]]; then uninstall_xray; exit 0; fi

ensure_deps
ensure_swap

download_core
if [[ "$KEEP_CONFIG" == "true" && -f "${BASE_DIR}/config.json" ]]; then configure_service; exit 0; fi
if [[ -f "${BASE_DIR}/config.json" && "$FORCE_REBUILD_CONFIG" != "true" ]]; then log_info "Existing config detected. Use --force-rebuild-config to overwrite."; exit 0; fi

generate_keys
build_config
configure_firewall
configure_service
public_ip="$(detect_public_ip)"
generate_links "$public_ip"
log_info "Port info has been saved to: $PORTS_FILE"
log_info "All URLs have been saved to: $LINKS_FILE"
print_summary "$public_ip"
install_manager_command
