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

XRAY_LANG_DETECTED=""

detect_lang() {
  if [[ -n "${XRAY_LANG:-}" ]]; then
    case "${XRAY_LANG,,}" in
      zh*) XRAY_LANG_DETECTED="zh"; return ;;
      en*) XRAY_LANG_DETECTED="en"; return ;;
      *)   XRAY_LANG_DETECTED="en"; return ;;
    esac
  fi

  local lc="${LC_ALL:-${LANG:-}}"
  if [[ "$lc" == zh_* || "$lc" == zh-* ]]; then
    XRAY_LANG_DETECTED="zh"
  else
    XRAY_LANG_DETECTED="en"
  fi
}

t() {
  local zh="$1" en="$2"
  if [[ "${XRAY_LANG_DETECTED:-en}" == "zh" ]]; then
    printf "%s" "$zh"
  else
    printf "%s" "$en"
  fi
}

detect_lang

log_info()  { printf "%b\n" "${COLOR_INFO}[$(date '+%F %T')] [INFO ] $*${COLOR_RESET}" >&2; }
log_warn()  { printf "%b\n" "${COLOR_WARN}[$(date '+%F %T')] [WARN ] $*${COLOR_RESET}" >&2; }
log_error() { printf "%b\n" "${COLOR_ERROR}[$(date '+%F %T')] [ERROR] $*${COLOR_RESET}" >&2; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "Please run this script as root (sudo)."
    exit 1
  fi
}

validate_base_dir() {
  local dir="$1"

  if [[ -z "$dir" ]]; then
    log_error "BASE_DIR is empty. Please set a non-empty directory such as /opt/xray."
    exit 1
  fi

  if [[ "$dir" != /* ]]; then
    log_error "BASE_DIR must be an absolute path, e.g. /opt/xray."
    exit 1
  fi

  if [[ "$dir" == "/" ]]; then
    log_error "Refusing to use '/' as BASE_DIR."
    exit 1
  fi

  case "$dir" in
    /root|/home|/usr|/var|/etc|/opt|/tmp)
      log_error "Refusing to use system directory '$dir' as BASE_DIR. Please use a subdirectory such as /opt/xray."
      exit 1
      ;;
  esac

  if [[ "$dir" =~ ^/[^/]+$ ]]; then
    log_error "Refusing to use top-level directory '$dir' as BASE_DIR. Please use a subdirectory such as /opt/xray."
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
  install_dep openssl openssl
}

validate_port_value() {
  local name="$1" value="$2" num

  if [[ -z "$value" || "$value" == "0" ]]; then
    return 0
  fi

  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    log_error "Invalid $name: '$value' is not a valid number."
    exit 1
  fi

  num="$value"
  if (( num < 1 || num > 65535 )); then
    log_error "Invalid $name: '$value' is out of range (1-65535)."
    exit 1
  fi
}

swap_size_to_bytes() {
  local size_input="${1:-1G}"
  local size_num size_unit size_bytes

  size_input="${size_input// /}"
  if [[ ! "$size_input" =~ ^([0-9]+)([KkMmGgTt]?)([Ii]?[Bb])?$ ]]; then
    log_error "Invalid swap size '${size_input}'. Use values such as 512M or 1G."
    exit 1
  fi

  size_num="${BASH_REMATCH[1]}"
  size_unit="${BASH_REMATCH[2],,}"

  case "$size_unit" in
    k) size_bytes=$((size_num * 1024)) ;;
    m|"") size_bytes=$((size_num * 1024 * 1024)) ;;
    g) size_bytes=$((size_num * 1024 * 1024 * 1024)) ;;
    t) size_bytes=$((size_num * 1024 * 1024 * 1024 * 1024)) ;;
    *)
      log_error "Unsupported swap size unit in '${size_input}'."
      exit 1
      ;;
  esac

  printf '%s' "$size_bytes"
}

swap_size_to_mib() {
  local size_bytes
  size_bytes="$(swap_size_to_bytes "${1:-1G}")"
  printf '%s' "$(((size_bytes + 1048575) / 1048576))"
}

detect_total_mem_mib() {
  local mem_kib=""

  if [[ -r /proc/meminfo ]]; then
    mem_kib="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)"
  elif command -v free >/dev/null 2>&1; then
    mem_kib="$(free -k | awk '/^Mem:/ {print $2; exit}')"
  fi

  if [[ -z "$mem_kib" ]]; then
    printf '0'
    return 0
  fi

  printf '%s' "$(((mem_kib + 1023) / 1024))"
}

detect_swap_total_mib() {
  local swap_kib="0"

  if [[ -r /proc/swaps ]]; then
    swap_kib="$(awk 'NR>1 {sum += $3} END {print sum + 0}' /proc/swaps)"
  elif command -v swapon >/dev/null 2>&1; then
    swap_kib="$(swapon --show --noheadings --bytes 2>/dev/null | awk '{sum += $2} END {print int((sum + 1048575) / 1048576) * 1024}')"
  fi

  printf '%s' "$(((swap_kib + 1023) / 1024))"
}

is_swapfile_active() {
  local swapfile_path="${1:-/swapfile}"

  if [[ -r /proc/swaps ]]; then
    awk -v swapfile="$swapfile_path" 'NR>1 && $1 == swapfile {found=1} END {exit(found ? 0 : 1)}' /proc/swaps
    return $?
  fi

  if command -v swapon >/dev/null 2>&1; then
    swapon --show=NAME --noheadings 2>/dev/null | awk -v swapfile="$swapfile_path" '$1 == swapfile {found=1} END {exit(found ? 0 : 1)}'
    return $?
  fi

  return 1
}

append_fstab_once() {
  local swapfile_path="${1:-/swapfile}"
  local fstab_path="/etc/fstab"

  if [[ ! -f "$fstab_path" ]]; then
    touch "$fstab_path"
  fi

  if grep -qE "^[[:space:]]*${swapfile_path}[[:space:]]+none[[:space:]]+swap[[:space:]]" "$fstab_path"; then
    return 0
  fi

  printf '%s none swap sw 0 0\n' "$swapfile_path" >>"$fstab_path"
}

create_swapfile() {
  local swapfile_path="$1"
  local swap_size="$2"
  local swap_size_mib

  swap_size_mib="$(swap_size_to_mib "$swap_size")"

  if command -v fallocate >/dev/null 2>&1; then
    if fallocate -l "$swap_size" "$swapfile_path"; then
      return 0
    fi
    log_warn "fallocate failed for ${swapfile_path}; falling back to dd."
  fi

  dd if=/dev/zero of="$swapfile_path" bs=1M count="$swap_size_mib" status=none
}

ensure_swap() {
  local swapfile_path="${SWAPFILE_PATH:-/swapfile}"
  local swap_mode="${ENABLE_SWAP:-auto}"
  local swap_size="${SWAP_SIZE:-1G}"
  local total_mem_mib swap_total_mib swapfile_exists swapfile_active should_create created_mib

  case "${swap_mode,,}" in
    true|false|auto) ;;
    1|yes|on) swap_mode="true" ;;
    0|no|off) swap_mode="false" ;;
    "")
      swap_mode="auto"
      ;;
    *)
      log_error "Invalid ENABLE_SWAP value '${swap_mode}'. Use true, false, or leave it unset for auto mode."
      exit 1
      ;;
  esac

  total_mem_mib="$(detect_total_mem_mib)"
  swap_total_mib="$(detect_swap_total_mib)"
  swapfile_exists="false"
  swapfile_active="false"
  should_create="false"

  if [[ -e "$swapfile_path" ]]; then
    swapfile_exists="true"
  fi

  if is_swapfile_active "$swapfile_path"; then
    swapfile_active="true"
  fi

  log_info "Memory total: ${total_mem_mib} MiB"
  log_info "Swap total: ${swap_total_mib} MiB"
  log_info "Swapfile path: ${swapfile_path}"
  log_info "Swapfile exists: ${swapfile_exists}"
  log_info "Swapfile active: ${swapfile_active}"
  log_info "Swap mode: ${swap_mode}"
  log_info "Swap size: ${swap_size}"

  if [[ "${PROFILE:-}" == "reality-kcp" && "$total_mem_mib" -lt 512 ]]; then
    log_warn "Memory is below 512 MiB. VMess mKCP is not recommended on this host; Reality TCP is the safer path."
  fi

  if [[ "$swap_mode" == "false" ]]; then
    log_info "Swap creation was disabled explicitly."
    return 0
  fi

  if (( swap_total_mib > 0 )); then
    log_info "Existing swap was detected; no new swapfile will be created."
    return 0
  fi

  if [[ "$swap_mode" == "auto" && "$total_mem_mib" -ge 768 ]]; then
    log_info "Memory is at or above 768 MiB and no swap was detected; skipping automatic swap creation."
    return 0
  fi

  should_create="true"

  if [[ "$swapfile_active" == "true" ]]; then
    append_fstab_once "$swapfile_path"
    log_info "Swapfile is already active; ensured /etc/fstab contains the entry once."
    return 0
  fi

  if [[ "$swapfile_exists" == "true" ]]; then
    log_info "An existing swapfile was found at ${swapfile_path}; attempting to activate it without overwriting."
    if swapon "$swapfile_path"; then
      append_fstab_once "$swapfile_path"
      log_info "Activated the existing swapfile and ensured /etc/fstab contains the entry once."
      return 0
    fi

    log_error "Existing ${swapfile_path} could not be activated. Refusing to overwrite it."
    exit 1
  fi

  if [[ "$should_create" == "true" ]]; then
    log_info "Creating swapfile..."
    if ! create_swapfile "$swapfile_path" "$swap_size"; then
      log_error "Failed to create swapfile at ${swapfile_path}."
      rm -f "$swapfile_path"
      exit 1
    fi

    chmod 600 "$swapfile_path" || {
      log_error "Failed to set permissions on ${swapfile_path}."
      rm -f "$swapfile_path"
      exit 1
    }

    if ! mkswap "$swapfile_path" >/dev/null; then
      log_error "mkswap failed for ${swapfile_path}."
      rm -f "$swapfile_path"
      exit 1
    fi

    if ! swapon "$swapfile_path"; then
      log_error "swapon failed for ${swapfile_path}."
      rm -f "$swapfile_path"
      exit 1
    fi

    append_fstab_once "$swapfile_path"
    created_mib="$(swap_size_to_mib "$swap_size")"
    log_info "Swapfile created and activated: path=${swapfile_path}, size=${swap_size} (~${created_mib} MiB)"
  fi
}

remove_swapfile() {
  local swapfile_path="${1:-/swapfile}"
  local fstab_path="/etc/fstab"
  local tmp_fstab

  if is_swapfile_active "$swapfile_path"; then
    log_info "Disabling active swapfile ${swapfile_path}..."
    if ! swapoff "$swapfile_path"; then
      log_error "Failed to disable ${swapfile_path}."
      exit 1
    fi
  fi

  if [[ -f "$fstab_path" ]]; then
    tmp_fstab="$(mktemp)"
    awk -v swapfile="$swapfile_path" '($1 == swapfile && $3 == "swap") {next} {print}' "$fstab_path" >"$tmp_fstab" || {
      rm -f "$tmp_fstab"
      log_error "Failed to rewrite ${fstab_path} without ${swapfile_path}."
      exit 1
    }
    mv "$tmp_fstab" "$fstab_path"
  fi

  if [[ -e "$swapfile_path" ]]; then
    rm -f "$swapfile_path"
    log_info "Removed swapfile: ${swapfile_path}"
  else
    log_info "Swapfile not found: ${swapfile_path}"
  fi
}

remove_swapfile_if_requested() {
  local remove_swap="${1:-false}"

  case "${remove_swap,,}" in
    true|1|yes|on)
      remove_swapfile "${SWAPFILE_PATH:-/swapfile}"
      ;;
  esac
}
