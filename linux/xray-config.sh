
generate_xray_config() {
  local config_path="$1"
  local profile="$2"
  local uuid="$3"
  local reality_port="$4"
  local vmess_kcp_port="$5"
  local reality_dest="$6"
  local reality_server_name="$7"
  local reality_short_id="$8"
  local reality_priv="$9"
  local reality_pub="${10}"
  local main_port="${11}"
  local profile_display_name="${12}"

  log_info "Building config: $config_path"

  # Build configuration based on selected profile
  if command -v build_config_for_profile >/dev/null 2>&1; then
    build_config_for_profile "$profile"
  else
    log_error "Profile configuration builder not found. Please check the library file."
    exit 1
  fi

  chmod 600 "$config_path"
}

configure_firewall() {
  local firewall_ports="$1"

  if [[ -n "$firewall_ports" ]]; then
    if command -v firewall-cmd >/dev/null 2>&1; then
      for port_spec in $firewall_ports; do
        if [[ "$port_spec" =~ ^([0-9]+(-[0-9]+)?)/(.+)$ ]]; then
          local port="${BASH_REMATCH[1]}"
          local proto="${BASH_REMATCH[3]}"
          firewall-cmd --add-port=${port}/${proto} --permanent || true
        fi
      done
      firewall-cmd --reload || true
      log_info "Opened ports in firewalld: $firewall_ports"
    elif command -v ufw >/dev/null 2>&1; then
      for port_spec in $firewall_ports; do
        if [[ "$port_spec" =~ ^([0-9]+(-[0-9]+)?)/(.+)$ ]]; then
          local port="${BASH_REMATCH[1]}"
          local proto="${BASH_REMATCH[3]}"
          ufw allow ${port}/${proto} || true
        fi
      done
      log_info "Opened ports in ufw: $firewall_ports"
    else
      log_warn "No known firewall manager detected (firewalld/ufw). Please ensure the ports are open manually: $firewall_ports"
    fi
  fi
}

setup_systemd_service() {
  local service_name="$1"
  local core_exe="$2"
  local config_path="$3"
  local log_dir="$4"

  log_info "Configuring systemd service: ${service_name}"

  if ! command -v systemctl >/dev/null 2>&1; then
    log_warn "systemd not found. Starting xray directly in background, but it will NOT persist across reboot."
    nohup "$core_exe" run -config "$config_path" >>"${log_dir}/xray.log" 2>&1 &
  else
    cat >/etc/systemd/system/${service_name}.service <<EOF
[Unit]
Description=Xray Server (VLESS Reality + VMess mKCP)
After=network.target

[Service]
Type=simple
User=root
ExecStart=${core_exe} run -config ${config_path}
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${service_name}
    systemctl restart ${service_name}

    sleep 1
    if systemctl is-active --quiet ${service_name}; then
      log_info "systemd service ${service_name} is running."
    else
      log_warn "systemd service ${service_name} is not active. Please check: journalctl -u ${service_name} -xe"
    fi
  fi
}

generate_url_for_profile() {
  local profile="$1"
  local public_ip="$2"
  local uuid="$3"
  local reality_port="$4"
  local vmess_kcp_port="$5"
  local reality_server_name="$6"
  local reality_pub="$7"
  local reality_short_id="$8"
  local main_port="$9"
  local profile_display_name="${10}"
  
  case "$profile" in
    reality-kcp|reality-only)
      local vless_name="xray.owokit.com-VLESS-Reality"
      local url="vless://${uuid}@${public_ip}:${reality_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${reality_server_name}&fp=chrome&pbk=${reality_pub}&sid=${reality_short_id}&spx=%2F&type=tcp#${vless_name}"
      echo "$url"
      if [[ "$profile" == "reality-kcp" ]]; then
        local vmess_name="xray.owokit.com-VMess-mKCP-wechat-video"
        local vmess_json=$(cat <<JSON
{
  "v": "2",
  "ps": "${vmess_name}",
  "add": "${public_ip}",
  "port": "${vmess_kcp_port}",
  "id": "${uuid}",
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
        local vmess_b64="$(printf '%s' "$vmess_json" | base64 -w0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
        echo "vmess://${vmess_b64}"
      fi
      ;;
    *vmess*|*vless*|*trojan*|shadowsocks|kcp-only)
      # For other protocols, generate appropriate URLs
      local port="${main_port:-${reality_port:-${vmess_kcp_port}}}"
      case "$profile" in
        *vmess*)
          local vmess_json=$(cat <<JSON
{
  "v": "2",
  "ps": "xray.owokit.com-${profile_display_name}",
  "add": "${public_ip}",
  "port": "${port}",
  "id": "${uuid}",
  "aid": "0",
  "scy": "auto",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "$([[ "$profile" == *tls* ]] && echo "tls" || echo "")",
  "sni": "",
  "alpn": "",
  "fp": ""
}
JSON
)
          local vmess_b64="$(printf '%s' "$vmess_json" | base64 -w0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
          echo "vmess://${vmess_b64}"
          ;;
        *trojan*)
          echo "trojan://${uuid}@${public_ip}:${port}#xray.owokit.com-${profile_display_name}"
          ;;
        shadowsocks)
          # Shadowsocks URL format: ss://base64(method:password)@server:port#name
          local ss_str="aes-256-gcm:${uuid}"
          local ss_b64="$(printf '%s' "$ss_str" | base64 -w0 2>/dev/null || printf '%s' "$ss_str" | base64 | tr -d '\n')"
          echo "ss://${ss_b64}@${public_ip}:${port}#xray.owokit.com-Shadowsocks"
          ;;
      esac
      ;;
  esac
}

print_summary() {
  local profile="$1"
  local public_ip="$2"
  local uuid="$3"
  local reality_port="$4"
  local vmess_kcp_port="$5"
  local reality_dest="$6"
  local reality_server_name="$7"
  local reality_short_id="$8"
  local reality_pub="$9"
  local links_file="${10}"
  local config_path="${11}"
  local log_dir="${12}"
  local service_name="${13}"
  local main_port="${14}"
  local profile_display_name="${15}"
  local urls=("${@:16}")

  printf "\n%s%s%s\n" "${COLOR_SUM_TITLE}" "$(t "================= Xray 服务器部署完成（Linux） =================" "================= Xray server deployed (Linux) =================")" "${COLOR_RESET}"
  printf "%s%s%s%s\n" "${COLOR_SUM_TITLE}" "$(t "服务器公网 IP: " "Server public IP: ")" "${public_ip}" "${COLOR_RESET}"
  printf "%s%s%s%s\n\n" "${COLOR_SUM_TITLE}" "$(t "部署方案: " "Profile: ")" "${profile_display_name}" "${COLOR_RESET}"

  # Print summary based on profile
  case "$profile" in
    reality-kcp|reality-only)
      printf "%s%s%s\n" "${COLOR_SUM_SECTION}" "$(t "[1] VLESS Reality" "[1] VLESS Reality")" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "地址:" "Address:")" "${public_ip}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "端口:" "Port:")" "${reality_port}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "UUID:" "${uuid}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "流控:" "Flow:")" "xtls-rprx-vision" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "目标站:" "Dest:")" "${reality_dest}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "SNI:" "${reality_server_name}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "shortId:" "${reality_short_id}" "${COLOR_RESET}"
      printf "%s  %-11s%s\n" "${COLOR_SUM_LABEL}" "$(t "公钥:" "publicKey:")" "${COLOR_RESET}"
      printf "%s    %s%s\n" "${COLOR_SUM_HIGHLIGHT}" "${reality_pub}" "${COLOR_RESET}"
      if [[ "$profile" == "reality-kcp" ]]; then
        printf "\n%s%s%s\n" "${COLOR_SUM_SECTION}" "$(t "[2] VMess mKCP + wechat-video" "[2] VMess mKCP + wechat-video")" "${COLOR_RESET}"
        printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "地址:" "Address:")" "${public_ip}" "${COLOR_RESET}"
        printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "端口(UDP):" "Port(UDP):")" "${vmess_kcp_port}" "${COLOR_RESET}"
        printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "UUID:" "${uuid}" "${COLOR_RESET}"
      fi
      ;;
    *dynamic*)
      printf "%s%s%s\n" "${COLOR_SUM_SECTION}" "${profile_display_name}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "地址:" "Address:")" "${public_ip}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "端口范围:" "Port Range:")" "20000-30000" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "UUID:" "${uuid}" "${COLOR_RESET}"
      ;;
    shadowsocks)
      printf "%s%s%s\n" "${COLOR_SUM_SECTION}" "Shadowsocks (AES-256-GCM)" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "地址:" "Address:")" "${public_ip}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "端口:" "Port:")" "${main_port}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "密码:" "Password:")" "${uuid}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "加密:" "Encryption:")" "aes-256-gcm" "${COLOR_RESET}"
      ;;
    *)
      printf "%s%s%s\n" "${COLOR_SUM_SECTION}" "${profile_display_name}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "地址:" "Address:")" "${public_ip}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "端口:" "Port:")" "${main_port:-${reality_port:-${vmess_kcp_port}}}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "UUID/Password:" "${uuid}" "${COLOR_RESET}"
      if [[ "$profile" == *tls* ]]; then
        printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "TLS:" "TLS:")" "$(t "已启用（自签名证书）" "Enabled (self-signed)")" "${COLOR_RESET}"
      fi
      ;;
  esac

  printf "\n%s%s%s\n" "${COLOR_SUM_LABEL}" "$(t "订阅链接:" "URLs:")" "${COLOR_RESET}"
  for url in "${urls[@]}"; do
    printf "%s%s%s\n" "${COLOR_SUM_URL}" "$url" "${COLOR_RESET}"
  done

  printf "\n%s%s%s\n" "${COLOR_SUM_LABEL}" "$(t "链接文件:   ${links_file}" "links file:   ${links_file}")" "${COLOR_RESET}"
  printf "%s%s%s\n" "${COLOR_SUM_LABEL}" "$(t "配置文件:  ${config_path}" "config file:  ${config_path}")" "${COLOR_RESET}"
  printf "%s%s%s\n" "${COLOR_SUM_LABEL}" "$(t "日志目录:      ${log_dir}" "log dir:      ${log_dir}")" "${COLOR_RESET}"
  printf "%s%s%s\n" "${COLOR_SUM_LABEL}" "$(t "服务:        ${service_name} (systemd)" "service:      ${service_name} (systemd)")" "${COLOR_RESET}"
  printf "%s%s%s\n" "${COLOR_SUM_TITLE}" "$(t "========================================================" "========================================================")" "${COLOR_RESET}"
}
