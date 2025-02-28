#!/bin/bash

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "请使用root权限运行此脚本！"
    exit 1
fi

SCRIPT_PATH=$(realpath "$0")
REMOTE_IP="188.172.228.65"
REMOTE_PORT="80"

# 安装依赖
install_deps() {
    if ! command -v socat &>/dev/null; then
        echo "正在安装socat..."
        if command -v apt &>/dev/null; then
            apt update && apt install -y socat iptables
        elif command -v yum &>/dev/null; then
            yum install -y socat iptables
        else
            echo "不支持的包管理器，请手动安装socat和iptables"
            exit 1
        fi
    fi
}

# 内核参数配置
set_kernel() {
    sysctl -w net.ipv4.ip_forward=1
    sed -i 's/^#*net.ipv4.ip_forward=.*$/net.ipv4.ip_forward=1/' /etc/sysctl.conf
}

# 方案一：纯iptables转发
setup_iptables_proxy() {
    local_port=$1
    # 清空旧规则
    iptables -t nat -F
    
    # 设置DNAT规则（包含本地回环）
    iptables -t nat -A PREROUTING -p tcp --dport $local_port -j DNAT --to-destination $REMOTE_IP:$REMOTE_PORT
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport $local_port -j DNAT --to-destination $REMOTE_IP:$REMOTE_PORT
    
    # MASQUERADE
    wan_iface=$(ip route | awk '/default/{print $5}')
    iptables -t nat -A POSTROUTING -p tcp -d $REMOTE_IP --dport $REMOTE_PORT -o $wan_iface -j MASQUERADE
}

# 方案二：socat转发（备用）
setup_socat_proxy() {
    local_port=$1
    nohup socat TCP4-LISTEN:$local_port,fork,reuseaddr TCP4:$REMOTE_IP:$REMOTE_PORT >/dev/null 2>&1 &
}

# 设置转发
set_proxy() {
    install_deps
    set_kernel

    read -p "请输入本地端口（默认8686）: " port
    local_port=${port:-8686}

    # 双方案部署
    setup_iptables_proxy $local_port
    setup_socat_proxy $local_port

    # 防火墙处理
    if command -v ufw &>/dev/null; then
        ufw allow $local_port/tcp
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=$local_port/tcp
        firewall-cmd --reload
    fi

    echo -e "\n✅ 转发设置成功！"
    echo "=============================="
    echo "监听端口: $local_port"
    echo "测试命令: nc -vz 127.0.0.1 $local_port"
    echo "清除命令: iptables -t nat -F && pkill socat"
    echo "=============================="
}

# 清理规则
clean_proxy() {
    iptables -t nat -F
    pkill -9 socat
    echo "✅ 所有转发规则已清除"
}

# 卸载脚本
uninstall() {
    clean_proxy
    rm -f "$SCRIPT_PATH"
    echo "✅ 脚本已彻底移除"
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n===== TCP端口转发管理 ====="
        echo "1) 设置转发"
        echo "2) 清除转发"
        echo "3) 完全卸载"
        echo "4) 退出脚本"
        read -p "请输入选择: " choice

        case $choice in
            1) set_proxy ;;
            2) clean_proxy ;;
            3) uninstall ;;
            4) exit 0 ;;
            *) echo "无效输入";;
        esac
    done
}

main_menu