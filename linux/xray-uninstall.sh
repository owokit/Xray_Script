cleanup_firewall_rules_from_ports_file() {
  local ports_file="$1" reality_port="" vmess_kcp_port="" firewall_ports="" k v port proto

  if [[ -f "$ports_file" ]]; then
    while IFS='=' read -r k v; do
      case "$k" in
        REALITY_PORT) reality_port="$v" ;;
        VMESS_KCP_PORT) vmess_kcp_port="$v" ;;
        FIREWALL_PORTS) firewall_ports="$v" ;;
      esac
    done <"$ports_file"
  fi

  if [[ -z "$firewall_ports" && ( -n "$reality_port" || -n "$vmess_kcp_port" ) ]]; then
    if [[ -n "$reality_port" ]]; then
      firewall_ports="${firewall_ports}${firewall_ports:+ }${reality_port}/tcp"
    fi
    if [[ -n "$vmess_kcp_port" ]]; then
      firewall_ports="${firewall_ports}${firewall_ports:+ }${vmess_kcp_port}/udp"
    fi
  fi

  if [[ -z "$firewall_ports" ]]; then
    log_warn "Ports file not found or empty (${ports_file}); firewall rules may need manual cleanup."
    return 0
  fi

  log_info "Removing firewall rules (if available)..."
  if command -v firewall-cmd >/dev/null 2>&1; then
    for port_spec in $firewall_ports; do
      if [[ "$port_spec" =~ ^([0-9]+(-[0-9]+)?)/(.+)$ ]]; then
        port="${BASH_REMATCH[1]}"
        proto="${BASH_REMATCH[3]}"
        firewall-cmd --remove-port=${port}/${proto} --permanent || true
      fi
    done
    firewall-cmd --reload || true
  elif command -v ufw >/dev/null 2>&1; then
    for port_spec in $firewall_ports; do
      if [[ "$port_spec" =~ ^([0-9]+(-[0-9]+)?)/(.+)$ ]]; then
        port="${BASH_REMATCH[1]}"
        proto="${BASH_REMATCH[3]}"
        ufw delete allow ${port}/${proto} || true
      fi
    done
  else
    log_warn "No known firewall manager detected while uninstalling. Please check firewall rules for Xray ports manually if needed."
  fi
}

uninstall_xray() {
  local service_name="xray-server"
  local ports_file="${BASE_DIR}/ports.env"

  log_info "Uninstall mode: stopping service and removing files..."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload || true
    log_info "systemd service ${service_name} removed (if existed)."
  fi

  if command -v pgrep >/dev/null 2>&1; then
    if pgrep -x xray >/dev/null 2>&1; then
      pkill -x xray || true
      log_info "Stopped running xray processes (if any)."
    fi
  fi

  cleanup_firewall_rules_from_ports_file "$ports_file"
  remove_swapfile_if_requested "${REMOVE_SWAP:-false}"

  if [[ -d "$BASE_DIR" ]]; then
    rm -rf "$BASE_DIR"
    log_info "Removed directory: $BASE_DIR"
  else
    log_info "Base directory not found: $BASE_DIR"
  fi

  log_info "Xray has been uninstalled on Linux."
}

uninstall_xray_config_only() {
  local service_name="xray-server"
  local ports_file="${BASE_DIR}/ports.env"
  local config_path="${BASE_DIR}/config.json"
  local links_file="${BASE_DIR}/links.txt"

  log_info "Uninstall-config mode: stopping service and removing configuration files..."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload || true
    log_info "systemd service ${service_name} removed (if existed)."
  fi

  if command -v pgrep >/dev/null 2>&1; then
    if pgrep -x xray >/dev/null 2>&1; then
      pkill -x xray || true
      log_info "Stopped running xray processes (if any)."
    fi
  fi

  cleanup_firewall_rules_from_ports_file "$ports_file"
  remove_swapfile_if_requested "${REMOVE_SWAP:-false}"

  rm -f "$config_path" "$links_file" "$ports_file"
  log_info "Removed configuration files under ${BASE_DIR} (config.json, links.txt, ports.env)."
  log_info "Xray configuration has been uninstalled on Linux. Core binaries and logs were kept."
}

delete_xray_config_files() {
  local config_path="${BASE_DIR}/config.json"
  local links_file="${BASE_DIR}/links.txt"
  local ports_file="${BASE_DIR}/ports.env"

  rm -f "$config_path" "$links_file" "$ports_file"
  log_info "Deleted configuration files (if existed): $config_path, $links_file, $ports_file"
}
