#!/bin/bash

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "请使用root权限运行此脚本！"
    exit 1
fi

SCRIPT_PATH=$(realpath "$0")

# 获取本机IP地址
get_local_ip() {
    hostname -I | awk '{print $1}'
}

# 安装iptables
install_iptables() {
    if command -v apt &>/dev/null; then
        apt update && apt install -y iptables
    elif command -v yum &>/dev/null; then
        yum install -y iptables
    elif command -v dnf &>/dev/null; then
        dnf install -y iptables
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm iptables
    elif command -v apk &>/dev/null; then
        apk add iptables
    else
        echo "无法自动安装iptables，请手动安装后重试"
        exit 1
    fi
}

# 设置反代
set_proxy() {
    # 检查并安装iptables
    if ! command -v iptables &>/dev/null; then
        echo "检测到未安装iptables，正在安装..."
        install_iptables
    fi

    # 开启IP转发
    sysctl -w net.ipv4.ip_forward=1
    sed -i 's/^#*net.ipv4.ip_forward=.*$/net.ipv4.ip_forward=1/' /etc/sysctl.conf

    # 获取端口号
    read -p "请输入本地端口号（默认8686）: " port
    local_port=${port:-8686}

    # 验证端口号有效性
    if ! [[ "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -gt 65535 ]; then
        echo "无效的端口号！"
        exit 1
    fi

    # 设置iptables规则
    iptables -t nat -A PREROUTING -p tcp --dport "$local_port" -j DNAT --to-destination 188.172.228.65:80
    iptables -I FORWARD -p tcp -d 188.172.228.65 --dport 80 -j ACCEPT

    echo -e "\n反代设置成功！"
    echo "访问地址: $(get_local_ip):$local_port"
}

# 取消反代
remove_proxy() {
    # 删除PREROUTING规则
    while true; do
        rule_num=$(iptables -t nat -L PREROUTING --line-numbers | grep '188.172.228.65:80' | awk 'NR==1{print $1}')
        [ -z "$rule_num" ] && break
        iptables -t nat -D PREROUTING "$rule_num"
    done

    # 删除FORWARD规则
    while true; do
        rule_num=$(iptables -L FORWARD --line-numbers | grep '188.172.228.65' | awk 'NR==1{print $1}')
        [ -z "$rule_num" ] && break
        iptables -D FORWARD "$rule_num"
    done

    echo "反代规则已成功移除"
}

# 主菜单
while true; do
    echo -e "\n============ 管理菜单 ============"
    echo "1) 设置反代"
    echo "2) 取消反代"
    echo "3) 退出脚本"
    echo "4) 卸载脚本"
    echo "==================================="
    read -p "请输入选项数字: " choice

    case $choice in
        1) set_proxy ;;
        2) remove_proxy ;;
        3) exit 0 ;;
        4) 
            rm -f "$SCRIPT_PATH" 
            echo "脚本已卸载"
            exit 0 
            ;;
        *) echo "无效输入，请重新选择" ;;
    esac
done