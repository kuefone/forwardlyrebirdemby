#!/bin/bash

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "请使用root权限运行此脚本！"
    exit 1
fi

SCRIPT_PATH=$(realpath "$0")
REMOTE_IP="188.172.228.65"
REMOTE_PORT="80"

# 增强版IP获取函数
get_local_ip() {
    # 尝试获取公网IP
    if command -v curl &>/dev/null; then
        public_ip=$(curl ip.sb -4 2>/dev/null)
        [[ $public_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$public_ip" && return
    fi

    # 获取内网IP
    local_ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
    [[ $local_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$local_ip" && return

    # 最终回退方案
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1
}

# 安装必要组件
install_deps() {
    # 安装curl
    if ! command -v curl &>/dev/null; then
        echo "正在安装curl..."
        if command -v apt &>/dev/null; then
            apt update && apt install -y curl
        elif command -v yum &>/dev/null; then
            yum install -y curl
        fi
    fi

    # 安装iptables
    if ! command -v iptables &>/dev/null; then
        echo "正在安装iptables..."
        if command -v apt &>/dev/null; then
            apt install -y iptables
        elif command -v yum &>/dev/null; then
            yum install -y iptables
        fi
    fi
}

# 设置内核参数
set_kernel_params() {
    sysctl -w net.ipv4.ip_forward=1
    sed -i 's/^#*net.ipv4.ip_forward=.*$/net.ipv4.ip_forward=1/' /etc/sysctl.conf
}

# 设置防火墙规则
configure_firewall() {
    local port=$1
    if command -v ufw &>/dev/null; then
        ufw allow "$port"/tcp >/dev/null 2>&1
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="$port"/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
}

# 设置转发规则
set_proxy() {
    install_deps
    set_kernel_params

    read -p "请输入本地端口号（默认8686）: " port
    local_port=${port:-8686}

    # 验证端口
    [[ ! "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -gt 65535 ] && echo "无效端口！" && exit 1

    # 清除旧规则
    remove_proxy silent

    # 设置NAT规则（包含本地访问支持）
    iptables -t nat -A PREROUTING -p tcp --dport "$local_port" -j DNAT --to-destination "${REMOTE_IP}:${REMOTE_PORT}"
    iptables -t nat -A OUTPUT -p tcp -d "$(get_local_ip)" --dport "$local_port" -j DNAT --to-destination "${REMOTE_IP}:${REMOTE_PORT}"
    
    # 设置MASQUERADE
    wan_iface=$(ip route | awk '/default/{print $5}')
    iptables -t nat -A POSTROUTING -p tcp -d "$REMOTE_IP" --dport "$REMOTE_PORT" -o "$wan_iface" -j MASQUERADE

    # 允许转发
    iptables -I FORWARD -p tcp -d "$REMOTE_IP" --dport "$REMOTE_PORT" -j ACCEPT

    # 配置防火墙
    configure_firewall "$local_port"

    # 显示结果
    echo -e "\n✅ 反代设置成功！"
    echo "================================"
    echo "本地访问: 127.0.0.1:$local_port"
    echo "内网访问: $(get_local_ip):$local_port"
    echo "公网访问: $(curl -4 -s https://ip.sb 2>/dev/null || echo '公网IP'):$local_port"
    echo "================================"
}

# 清理规则
remove_proxy() {
    # 清理PREROUTING
    while true; do
        rule_num=$(iptables -t nat -L PREROUTING --line-numbers | grep -i "$REMOTE_IP:$REMOTE_PORT" | awk 'NR==1{print $1}')
        [ -z "$rule_num" ] && break
        iptables -t nat -D PREROUTING "$rule_num"
    done

    # 清理OUTPUT
    while true; do
        rule_num=$(iptables -t nat -L OUTPUT --line-numbers | grep -i "$REMOTE_IP:$REMOTE_PORT" | awk 'NR==1{print $1}')
        [ -z "$rule_num" ] && break
        iptables -t nat -D OUTPUT "$rule_num"
    done

    # 清理POSTROUTING
    iptables -t nat -D POSTROUTING -p tcp -d "$REMOTE_IP" --dport "$REMOTE_PORT" -j MASQUERADE 2>/dev/null

    # 清理FORWARD
    while true; do
        rule_num=$(iptables -L FORWARD --line-numbers | grep -i "$REMOTE_IP" | awk 'NR==1{print $1}')
        [ -z "$rule_num" ] && break
        iptables -D FORWARD "$rule_num"
    done

    [ -z "$1" ] && echo "✅ 反代规则已清除"
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n======== 反向代理管理 ========"
        echo "1) 设置反代"
        echo "2) 取消反代"
        echo "3) 退出脚本"
        echo "4) 卸载脚本"
        echo "============================="
        read -p "请输入选项: " choice

        case $choice in
            1) set_proxy ;;
            2) remove_proxy ;;
            3) exit 0 ;;
            4) rm -f "$SCRIPT_PATH"; echo "脚本已卸载"; exit 0 ;;
            *) echo "无效输入";;
        esac
    done
}

# 启动脚本
main_menu