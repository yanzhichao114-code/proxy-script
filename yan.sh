#!/bin/bash

# --- 颜色配置 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 检查 Root ---
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# --- 基础依赖安装 ---
install_base() {
    echo -e "${YELLOW}正在安装必要组件...${PLAIN}"
    apt update -y >/dev/null 2>&1
    apt install -y curl wget jq openssl tar >/dev/null 2>&1
}

# --- 安装 VLESS + Reality ---
install_reality() {
    echo -e "${CYAN}=== 正在安装 VLESS + Reality ===${PLAIN}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    read -p "请输入端口 (默认 443): " PORT
    [[ -z "$PORT" ]] && PORT=443
    read -p "请输入伪装域名 (默认 www.microsoft.com): " DEST_DOMAIN
    [[ -z "$DEST_DOMAIN" ]] && DEST_DOMAIN="www.microsoft.com"
    
    UUID=$(xray uuid)
    KEYS=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEYS" | grep "Public" | awk '{print $3}')
    SHORT_ID=$(openssl rand -hex 4)
    
    cat > /usr/local/etc/xray/config.json <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$UUID", "flow": "xtls-rprx-vision" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST_DOMAIN}:443",
          "xver": 0,
          "serverNames": [ "${DEST_DOMAIN}" ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [ "$SHORT_ID" ]
        }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
}
JSON
    systemctl restart xray
    systemctl enable xray
    IP=$(curl -s4 ifconfig.me)
    LINK="vless://${UUID}@${IP}:${PORT}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${DEST_DOMAIN}&sid=${SHORT_ID}#Reality_Yan"
    
    echo -e "\n${GREEN}✅ Reality 节点部署完成！${PLAIN}\n链接:\n${YELLOW}${LINK}${PLAIN}"
}

# --- 安装 SS-2022 ---
install_ss2022() {
    echo -e "${CYAN}=== 正在安装 Shadowsocks-2022 ===${PLAIN}"
    ARCH=$(uname -m)
    [[ $ARCH == "x86_64" ]] && SS_ARCH="x86_64-unknown-linux-gnu" || SS_ARCH="aarch64-unknown-linux-gnu"
    LATEST_URL=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | jq -r ".assets[] | select(.name | contains(\"$SS_ARCH\")) | .browser_download_url" | grep -v "sha256" | head -n 1)
    
    wget -O ss-rust.tar.xz "$LATEST_URL" && tar -xvf ss-rust.tar.xz && mv ssserver /usr/local/bin/ && rm ss-rust.tar.xz ss* 2>/dev/null
    chmod +x /usr/local/bin/ssserver
    
    read -p "请输入端口 (默认随机): " SSPORT
    [[ -z "$SSPORT" ]] && SSPORT=$((RANDOM % 50000 + 10000))
    PASSWORD=$(openssl rand -base64 32)
    METHOD="2022-blake3-aes-256-gcm"
    
    mkdir -p /etc/shadowsocks-rust
    echo "{\"server\":\"0.0.0.0\",\"server_port\":$SSPORT,\"password\":\"$PASSWORD\",\"method\":\"$METHOD\",\"timeout\":300,\"fast_open\":true}" > /etc/shadowsocks-rust/config.json
    
    cat > /etc/systemd/system/shadowsocks-rust.service <<SERVICE
[Unit]
Description=Shadowsocks-Rust
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks-rust/config.json
Restart=always
User=root
LimitNOFILE=51200
[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable --now shadowsocks-rust
    IP=$(curl -s4 ifconfig.me)
    SS_BASE64=$(echo -n "${METHOD}:${PASSWORD}@${IP}:${SSPORT}" | base64 -w 0)
    echo -e "\n${GREEN}✅ SS-2022 节点部署完成！${PLAIN}\n链接:\n${YELLOW}ss://${SS_BASE64}#SS2022_Yan${PLAIN}"
}

# --- 卸载代理服务 (Xray + SS) ---
uninstall_services() {
    echo -e "${YELLOW}正在停止并移除所有代理服务...${PLAIN}"
    systemctl stop xray shadowsocks-rust >/dev/null 2>&1
    systemctl disable xray shadowsocks-rust >/dev/null 2>&1
    
    rm -rf /usr/local/etc/xray /usr/local/bin/xray 
    rm -rf /etc/shadowsocks-rust /usr/local/bin/ssserver
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/shadowsocks-rust.service
    
    systemctl daemon-reload
    echo -e "${GREEN}✅ 所有代理服务已卸载完毕！${PLAIN}"
}

# --- 卸载脚本本身 (Yan 命令) ---
uninstall_script() {
    read -p "确定要删除 'yan' 管理脚本吗？(y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        echo -e "${YELLOW}正在删除脚本...${PLAIN}"
        rm -f /usr/bin/yan
        echo -e "${GREEN}✅ 脚本已自毁。再见！${PLAIN}"
        exit 0
    else
        echo -e "${CYAN}已取消。${PLAIN}"
    fi
}

# --- 主菜单 ---
show_menu() {
    clear
    echo -e "=================================="
    echo -e "   ${GREEN}Yan 的专属代理管理脚本${PLAIN}"
    echo -e "=================================="
    echo -e " ${GREEN}1.${PLAIN} 安装 VLESS + Reality"
    echo -e " ${GREEN}2.${PLAIN} 安装 SS-2022 (中转专用)"
    echo -e "----------------------------------"
    echo -e " ${RED}3. 卸载代理服务 (清理垃圾)${PLAIN}"
    echo -e " ${RED}4. 卸载本脚本 (移除 yan 命令)${PLAIN}"
    echo -e "----------------------------------"
    echo -e " ${GREEN}0.${PLAIN} 退出"
    echo -e "=================================="
    read -p "请输入选项 [0-4]: " OPT
    case $OPT in
        1) install_base; install_reality ;;
        2) install_base; install_ss2022 ;;
        3) uninstall_services ;;
        4) uninstall_script ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
}

show_menu
