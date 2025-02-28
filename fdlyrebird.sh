#!/bin/bash

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "请使用root权限运行此脚本！"
    exit 1
fi

SCRIPT_PATH=$(realpath "$0")
NGINX_CONF_DIR="/etc/nginx/conf.d"
PROXY_CONF="$NGINX_CONF_DIR/reverse-proxy.conf"
REMOTE_SERVER="188.172.228.65:80"

# 安装Nginx
install_nginx() {
    if ! command -v nginx &>/dev/null; then
        echo "正在安装Nginx..."
        if command -v apt &>/dev/null; then
            apt update && apt install -y nginx
        elif command -v yum &>/dev/null; then
            yum install -y epel-release
            yum install -y nginx
        else
            echo "不支持的包管理器，请手动安装Nginx"
            exit 1
        fi
        systemctl enable nginx
    fi
}

# 创建代理配置
create_proxy_config() {
    local local_port=$1
    cat > "$PROXY_CONF" <<EOF
server {
    listen $local_port;
    server_name _;

    location / {
        proxy_pass http://$REMOTE_SERVER;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 重要超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;
        send_timeout 600s;
    }

    access_log /var/log/nginx/reverse-proxy.access.log;
    error_log /var/log/nginx/reverse-proxy.error.log;
}
EOF
}

# 设置防火墙
configure_firewall() {
    local port=$1
    if command -v ufw &>/dev/null; then
        ufw allow "$port/tcp"
        ufw reload
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="$port/tcp"
        firewall-cmd --reload
    fi
}

# 启用代理
enable_proxy() {
    read -p "请输入本地监听端口（默认8686）: " port
    local_port=${port:-8686}

    # 检查端口占用
    if ss -tuln | grep -q ":$local_port "; then
        echo "错误：端口 $local_port 已被占用！"
        exit 1
    fi

    install_nginx
    create_proxy_config "$local_port"
    configure_firewall "$local_port"

    # 重载Nginx配置
    if nginx -t && systemctl reload nginx; then
        echo -e "\n✅ 反向代理设置成功！"
        echo "================================"
        echo "本地访问: 127.0.0.1:$local_port"
        echo "网络访问: $(curl -4 -s https://ip.sb || hostname -I | awk '{print $1}'):$local_port"
        echo "测试命令: curl -v http://127.0.0.1:$local_port"
        echo "================================"
    else
        echo "❌ Nginx配置错误，请检查日志！"
        exit 1
    fi
}

# 禁用代理
disable_proxy() {
    rm -f "$PROXY_CONF"
    systemctl reload nginx
    echo "✅ 已移除反向代理配置"
}

# 完全卸载
full_uninstall() {
    disable_proxy
    rm -f "$SCRIPT_PATH"
    echo "✅ 脚本已彻底卸载"
    read -p "是否要卸载Nginx？[y/N] " choice
    if [[ $choice =~ ^[Yy]$ ]]; then
        if command -v apt &>/dev/null; then
            apt remove --purge -y nginx
        elif command -v yum &>/dev/null; then
            yum remove -y nginx
        fi
        echo "✅ Nginx已卸载"
    fi
}

# 显示菜单
show_menu() {
    echo -e "\n===== Nginx反向代理管理 ====="
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
            echo -e "\n当前代理配置："
            [ -f "$PROXY_CONF" ] && cat "$PROXY_CONF" || echo "未找到代理配置"
            echo -e "\nNginx状态："
            systemctl status nginx --no-pager
            ;;
        4) full_uninstall ;;
        5) exit 0 ;;
        *) echo "无效输入";;
    esac
}

# 主循环
while true; do
    show_menu
    read -p "按回车键继续..."
done