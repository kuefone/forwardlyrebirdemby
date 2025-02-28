#!/bin/bash

# 获取本机IP地址
LOCAL_IP=$(ip addr show | grep -w inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n 1)

# 显示菜单
show_menu() {
    echo "==================================="
    echo "        反代鸟服一键脚本"
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
    if [ -f /etc/redhat-release ]; then
        yum install -y nginx
    elif [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y nginx
    else
        echo "不支持的操作系统"
        exit 1
    fi
}

# 配置反代
setup_proxy() {
    # 检查nginx是否安装
    if ! command -v nginx &> /dev/null; then
        echo "正在安装nginx..."
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
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
        proxy_ssl_verify off;
    }
}
EOF

    # 检查nginx配置是否正确
    nginx -t

    # 重启nginx
    systemctl restart nginx

    echo "反代设置完成！"
    echo "您可以通过访问 http://$LOCAL_IP:$port 来访问鸟服"
}

# 取消反代
remove_proxy() {
    rm -f /etc/nginx/conf.d/flybird.conf
    systemctl restart nginx
    echo "已取消反代配置"
}

# 卸载脚本
uninstall() {
    if command -v nginx &> /dev/null; then
        if [ -f /etc/redhat-release ]; then
            yum remove -y nginx
        elif [ -f /etc/debian_version ]; then
            apt-get remove -y nginx
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
done