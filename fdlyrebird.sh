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
        echo "正在安装socat和依赖..."
        apt-get update >/dev/null 2>&1 && apt-get install -y socat iptables httping || yum install -y socat iptables httping
    fi
}

# 设置内核参数
set_kernel() {
    sysctl -w net.ipv4.ip_forward=1
    sed -i 's/^#*net.ipv4.ip_forward=.*$/net.ipv4.ip_forward=1/' /etc/sysctl.conf
}

# 获取真实Host头（自动嗅探）
detect_host_header() {
    echo "正在自动检测目标服务器域名..."
    timeout 5 curl -sI "http://$REMOTE_IP:$REMOTE_PORT" | grep -i 'Location: \|Host: ' | awk -F'[: ]+' '/Host:/{print $2}'
    [ $? -ne 0 ] && echo "检测失败，请手动输入域名：" && read manual_host && echo "$manual_host"
}

# 设置透明代理
setup_proxy() {
    local_port=$1
    host_header=$2

    # 清空旧规则
    iptables -t nat -F

    # TCP透明转发规则
    iptables -t nat -A PREROUTING -p tcp --dport $local_port -j DNAT --to-destination $REMOTE_IP:$REMOTE_PORT
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport $local_port -j DNAT --to-destination $REMOTE_IP:$REMOTE_PORT
    
    # MASQUERADE规则
    wan_iface=$(ip route | awk '/default/{print $5}')
    iptables -t nat -A POSTROUTING -p tcp -d $REMOTE_IP --dport $REMOTE_PORT -o $wan_iface -j MASQUERADE

    # 启动socat进行Host头注入
    nohup socat TCP4-LISTEN:$local_port,fork,reuseaddr PROXY:$REMOTE_IP:$REMOTE_PORT,proxyport=$local_port,proxyauth=user:pass,header-add="Host: $host_header" >/dev/null 2>&1 &
}

# 验证设置
verify_proxy() {
    local_port=$1
    host_header=$2

    echo -e "\n🔍 运行验证测试..."
    
    # 基础端口测试
    nc -zv 127.0.0.1 $local_port 2>&1 | grep "succeeded" && echo "✅ 端口转发正常" || echo "❌ 端口转发失败"

    # HTTP协议测试
    httping -c 3 -t 5 http://127.0.0.1:$local_port -H "Host: $host_header" | grep "connected" && echo "✅ HTTP连接正常" || echo "❌ HTTP连接失败"

    # Host头验证
    curl -s -H "Host: invalid.host" http://127.0.0.1:$local_port -I | grep "HTTP/1.1 200 OK" >/dev/null && echo "✅ Host头强制生效" || echo "❌ Host头未生效"
}

set_proxy() {
    install_deps
    set_kernel

    read -p "请输入本地端口（默认8686）: " port
    local_port=${port:-8686}

    # 自动获取Host头
    detected_host=$(detect_host_header)
    [ -z "$detected_host" ] && read -p "请输入目标服务器域名: " detected_host

    # 设置代理
    setup_proxy $local_port "$detected_host"

    # 防火墙处理
    ufw allow $local_port/tcp >/dev/null 2>&1 || firewall-cmd --add-port=$local_port/tcp --permanent >/dev/null 2>&1

    # 显示配置信息
    echo -e "\n✅ 代理设置成功！"
    echo "=============================="
    echo "监听端口: $local_port"
    echo "强制Host头: $detected_host"
    echo "测试命令:"
    echo "curl -H 'Host: $detected_host' http://127.0.0.1:$local_port"
    echo "=============================="

    # 运行验证
    verify_proxy $local_port "$detected_host"
}

# 清理规则
clean_proxy() {
    iptables -t nat -F
    pkill -9 socat
    echo "✅ 所有代理规则已清除"
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
        echo -e "\n===== 智能反代管理 ====="
        echo "1) 设置反代"
        echo "2) 清除反代"
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