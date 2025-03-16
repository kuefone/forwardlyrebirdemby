#!/bin/bash

# 获取本机IP地址
get_local_ip() {
    LOCAL_IP=$(ip addr show | grep -w inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    PUBLIC_IP=$(curl -s ifconfig.me)
    
    echo "检测到本地IP: $LOCAL_IP"
    echo "检测到公网IP: $PUBLIC_IP"
    read -p "请确认使用的IP地址 [默认: $PUBLIC_TP]: " selected_ip
    SELECTED_IP=${selected_ip:-$PUBLIC_IP}
}

# 显示菜单
show_menu() {
    echo "==================================="
    echo "        反代鸟服一键脚本 v2.0"
    echo "==================================="
    echo "1. 设置反代"
    echo "2. 取消反代" 
    echo "3. 退出脚本"
    echo "4. 卸载脚本"
    echo "==================================="
    read -p "请输入选项 [1-4]: " choice
}

# 安装nginx
install_nginx() {
    echo "正在安装nginx..."
    if [ -f /etc/redhat-release ]; then
        yum install -y nginx || { echo "安装失败！请检查yum配置"; exit 1; }
        systemctl enable nginx
    elif [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y nginx || { echo "安装失败！请检查apt源"; exit 1; }
        systemctl enable nginx
    else
        echo "不支持的操作系统"
        exit 1
    fi
}

# 配置防火墙
configure_firewall() {
    if firewall-cmd --state &> /dev/null; then
        firewall-cmd --permanent --add-port=${port}/tcp
        firewall-cmd --reload
    elif ufw status | grep -q active; then
        ufw allow ${port}/tcp
        ufw reload
    else
        echo "警告：未找到活动的防火墙，请确保 ${port} 端口已开放"
    fi
}

# 配置反代
setup_proxy() {
    # 检查nginx是否安装
    if ! command -v nginx &> /dev/null; then
        install_nginx
    fi

    # 获取端口号
    read -p "请输入要使用的端口号 [默认8686]: " port
    port=${port:-8686}

    # 创建nginx配置
    cat > /etc/nginx/conf.d/flybird.conf << EOF
server {
    listen $port;
    server_name _;
    
    location / {
        proxy_pass http://188.172.228.65;
        proxy_set_header Host direct.lyrebirdemby.com;  # 固定目标域名
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOF

    # 配置防火墙
    configure_firewall

    # 检查nginx配置
    if ! nginx -t; then
        echo "! Nginx配置测试失败，请检查配置文件 !"
        exit 1
    fi

    systemctl restart nginx || { echo "Nginx重启失败！请检查日志"; exit 1; }

    get_local_ip
    echo "------------------------------------------------"
    echo "反代设置完成！"
    echo "您现在可以通过以下方式访问："
    echo "内网访问: http://${LOCAL_IP}:${port}"
    echo "公网访问: http://${SELECTED_IP}:${port}"
    echo "------------------------------------------------"
}

# 取消反代
remove_proxy() {
    rm -f /etc/nginx/conf.d/flybird.conf
    systemctl restart nginx
    echo "已取消反代配置"
}

# 卸载脚本
uninstall() {
    read -p "是否要完全卸载Nginx？[y/N]: " remove_nginx
    if [[ $remove_nginx =~ [Yy] ]]; then
        if [ -f /etc/redhat-release ]; then
            yum remove -y nginx
        elif [ -f /etc/debian_version ]; then
            apt-get purge -y nginx
        fi
    fi
    rm -f "$0"
    echo "脚本已卸载"
}

# 主程序
while true; do
    show_menu
    case $choice in
        1)
            setup_proxy
            ;;
        2)
            remove_proxy
            ;;
        3)
            echo "退出脚本"
            exit 0
            ;;
        4)
            uninstall
            exit 0
            ;;
        *)
            echo "无效的选项，请重新选择"
            ;;
    esac
    read -p "按回车键继续..."
done