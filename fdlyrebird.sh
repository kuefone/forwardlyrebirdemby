#!/bin/bash

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[31m请使用root权限运行此脚本！\033[0m"
    exit 1
fi

# 配置参数
NGINX_CONF="/etc/nginx/conf.d/reverse-proxy.conf"
TARGET_SERVER="188.172.228.65:80"
SCRIPT_NAME=$(basename "$0")

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 安装依赖
install_deps() {
    echo -e "${BLUE}正在检查系统环境...${RESET}"
    
    # 禁用man-db触发器
    if ! grep -q "man-db" /etc/apt/apt.conf.d/00aptsettings; then
        echo 'DPkg::options { "--skip-man-db"; }' > /etc/apt/apt.conf.d/00aptsettings
    fi

    # 优化APT安装参数
    export DEBIAN_FRONTEND=noninteractive
    export APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
    
    if ! command -v curl &>/dev/null; then
        echo -e "${YELLOW}正在安装curl...${RESET}"
        apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y curl
    fi
    
    if ! command -v nginx &>/dev/null; then
        echo -e "${YELLOW}正在安装Nginx...${RESET}"
        # 分步安装避免服务卡住
        apt-get update
        apt-get download nginx
        dpkg --unpack ./nginx*.deb
        systemctl daemon-reload
        apt-get -f install -y
        
        # 延迟服务启用
        systemctl disable nginx --now 2>/dev/null
        rm -f /etc/nginx/sites-enabled/*
    fi

    # 清理APT优化设置
    rm -f /etc/apt/apt.conf.d/00aptsettings
}

# 检测目标Host头
detect_host() {
    echo -e "${BLUE}正在智能检测目标服务器配置...${RESET}"
    
    # 方法1：从HTTP头检测
    local detected_host=$(curl -sI "http://$TARGET_SERVER" | awk -F': ' '/^[Hh]ost:/{print $2}' | tr -d '\r')
    
    # 方法2：从HTML内容检测
    [ -z "$detected_host" ] && detected_host=$(curl -s "http://$TARGET_SERVER" | grep -oE '<meta[^>]*http-equiv="refresh"[^>]*url=[^>]*>' | grep -oE 'url=([^&"]+)' | cut -d'=' -f2 | awk -F/ '{print $3}')
    
    # 方法3：用户手动输入
    if [ -z "$detected_host" ]; then
        echo -e "${YELLOW}自动检测失败，请输入目标网站域名（如emby.example.com）：${RESET}"
        read -r detected_host
        while [[ -z "$detected_host" ]]; do
            echo -e "${RED}域名不能为空，请重新输入：${RESET}"
            read -r detected_host
        done
    fi
    
    echo "$detected_host"
}

# 创建Nginx配置
create_config() {
    local port=$1
    local host=$2

    cat > "$NGINX_CONF" <<EOF
server {
    listen ${port};
    server_name _;

    # 强制覆盖Host头
    proxy_set_header Host ${host};
    
    # 完整代理头设置
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;

    # 连接优化
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    client_max_body_size 1024M;

    # 超时设置（单位：秒）
    proxy_connect_timeout 60;
    proxy_send_timeout 600;
    proxy_read_timeout 600;

    location / {
        proxy_pass http://${TARGET_SERVER};
        
        # 响应头重写
        proxy_redirect ~^http://${TARGET_SERVER//./\\.}(:\d+)?/(.*) /\$2;
        proxy_cookie_domain ${TARGET_SERVER} \$host;
    }

    access_log /var/log/nginx/reverse-proxy.access.log;
    error_log /var/log/nginx/reverse-proxy.error.log;
}
EOF
}

# 验证配置
verify_proxy() {
    local port=$1
    local host=$2

    echo -e "\n${BLUE}运行深度验证测试...${RESET}"
    
    # 测试1：端口监听检测
    if ! ss -tln | grep -q ":${port} "; then
        echo -e "${RED}❌ Nginx未监听端口${port}${RESET}"
        return 1
    else
        echo -e "${GREEN}✅ 端口${port}监听正常${RESET}"
    fi

    # 测试2：HTTP基础测试
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${port}")
    if [ "$status_code" != "200" ]; then
        echo -e "${RED}❌ 收到异常状态码：${status_code}${RESET}"
    else
        echo -e "${GREEN}✅ 基础访问成功（状态码200）${RESET}"
    fi

    # 测试3：Host头验证
    local response_host=$(curl -sI "http://127.0.0.1:${port}" | awk -F': ' '/^[Hh]ost:/{print $2}' | tr -d '\r')
    if [ "$response_host" == "$host" ]; then
        echo -e "${GREEN}✅ Host头设置正确（${host}）${RESET}"
    else
        echo -e "${RED}❌ Host头不匹配（实际：${response_host:-无}）${RESET}"
    fi

    # 测试4：内容完整性验证
    if curl -s "http://127.0.0.1:${port}" | grep -q "$host"; then
        echo -e "${GREEN}✅ 内容包含目标标识${RESET}"
    else
        echo -e "${YELLOW}⚠️ 内容验证未通过，可能需要进一步检查${RESET}"
    fi
}

# 启用代理
enable_proxy() {
    # 获取配置参数
    read -p "请输入本地监听端口（默认8686）: " port
    local port=${port:-8686}

    # 端口冲突检测
    if ss -tln | grep -q ":${port} "; then
        echo -e "${RED}错误：端口${port}已被占用！${RESET}"
        exit 1
    fi

    # 安装依赖
    install_deps

    # 获取目标Host
    local target_host=$(detect_host)

    # 创建配置文件
    create_config "$port" "$target_host"

    # 配置验证
    echo -e "${BLUE}验证Nginx配置...${RESET}"
    if ! nginx -t; then
        echo -e "${RED}❌ Nginx配置验证失败，请检查：${NGINX_CONF}${RESET}"
        exit 1
    fi

    # 应用配置
    systemctl reload nginx

    # 配置防火墙
    echo -e "${BLUE}配置防火墙...${RESET}"
    if command -v ufw &>/dev/null; then
        ufw allow "$port/tcp"
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="$port/tcp"
        firewall-cmd --reload
    fi

    # 显示结果
    echo -e "\n${GREEN}✅ 反向代理设置成功！${RESET}"
    echo -e "================================"
    echo -e "${BLUE}访问地址：${RESET}"
    echo -e "本地: ${GREEN}http://127.0.0.1:${port}${RESET}"
    echo -e "网络: ${GREEN}http://$(curl -4 -s https://ip.sb || hostname -I | awk '{print $1}'):${port}${RESET}"
    echo -e "================================"

    # 执行验证
    verify_proxy "$port" "$target_host"
}

# 禁用代理
disable_proxy() {
    [ -f "$NGINX_CONF" ] && rm -f "$NGINX_CONF"
    systemctl reload nginx
    echo -e "${GREEN}✅ 已移除反向代理配置${RESET}"
}

# 完全卸载
uninstall() {
    disable_proxy
    [ -f "$0" ] && rm -f "$0"
    echo -e "${GREEN}✅ 脚本已彻底卸载${RESET}"
    
    read -p "是否要卸载Nginx？[y/N] " choice
    if [[ $choice =~ ^[Yy]$ ]]; then
        if command -v apt &>/dev/null; then
            apt remove --purge -y nginx
        elif command -v yum &>/dev/null; then
            yum remove -y nginx
        fi
        echo -e "${GREEN}✅ Nginx已卸载${RESET}"
    fi
}

# 显示菜单
show_menu() {
    echo -e "\n${BLUE}===== Nginx反向代理管理 ====${RESET}"
    echo "1) 启用反向代理"
    echo "2) 禁用反向代理"
    echo "3) 查看代理状态"
    echo "4) 完全卸载"
    echo "5) 退出脚本"
    read -p "请输入选项: " choice

    case $choice in
        1) enable_proxy ;;
        2) disable_proxy ;;
        3) 
            echo -e "\n${BLUE}当前代理配置：${RESET}"
            [ -f "$NGINX_CONF" ] && cat "$NGINX_CONF" || echo "未找到代理配置"
            echo -e "\n${BLUE}Nginx状态：${RESET}"
            systemctl status nginx --no-pager
            ;;
        4) uninstall ;;
        5) exit 0 ;;
        *) echo -e "${RED}无效输入${RESET}";;
    esac
}

# 主循环
while true; do
    show_menu
    read -p "按回车键继续..."
done