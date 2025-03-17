#!/bin/bash

set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$BASE_DIR/data/config.plist"
LOCKDOWND_FILE="$BASE_DIR/data/lockdownd"
TEMP_DIR="$BASE_DIR/data/temp"

PLIST_BUDDY="/usr/libexec/PlistBuddy"

# 检查 PlistBuddy 是否存在
if [[ ! -x "$PLIST_BUDDY" ]]; then
    echo "错误：PlistBuddy 未找到，请检查您的 macOS 版本！"
    exit 1
fi

# 检查 sshpass 是否安装
USE_SSHPASS=false
if command -v sshpass &>/dev/null; then
    USE_SSHPASS=true
fi

mkdir -p "$BASE_DIR/data"

# 选择 SSHRamdisk 挂载目录
select_mnt() {
    echo "请输入 SSHRamdisk 挂载目录 (mnt1, mnt2, mnt3)："
    read -r mnt
}

# SSH 连接封装（支持 sshpass）
ssh_exec() {
    local cmd="$1"
    if $USE_SSHPASS; then
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$server" "$cmd"
    else
        ssh -o StrictHostKeyChecking=no -p "$port" "$user@$server" "$cmd"
    fi
}

# SCP 传输封装（支持 sshpass）
scp_exec() {
    local src="$1"
    local dest="$2"
    if $USE_SSHPASS; then
        sshpass -p "$password" scp -o StrictHostKeyChecking=no -P "$port" "$src" "$dest"
    else
        scp -o StrictHostKeyChecking=no -P "$port" "$src" "$dest"
    fi
}

# 服务器配置管理
manage_server_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        servers_count=$($PLIST_BUDDY -c "Print :Servers" "$CONFIG_FILE" 2>/dev/null | grep "Dict" | wc -l || echo 0)
        if [[ "$servers_count" -gt 0 ]]; then
            echo "可用的服务器别名："
            $PLIST_BUDDY -c "Print :Servers" "$CONFIG_FILE" | grep "Dict" | nl
            echo "请选择服务器编号 (输入 0 以新建配置)："
            read -r choice

            if [[ "$choice" -gt 0 && "$choice" -le "$servers_count" ]]; then
                index=$((choice - 1))
                user=$($PLIST_BUDDY -c "Print :Servers:$index:User" "$CONFIG_FILE")
                server=$($PLIST_BUDDY -c "Print :Servers:$index:Server" "$CONFIG_FILE")
                password=$($PLIST_BUDDY -c "Print :Servers:$index:Password" "$CONFIG_FILE")
                port=$($PLIST_BUDDY -c "Print :Servers:$index:Port" "$CONFIG_FILE")
                return
            fi
        fi
    fi

    echo "请输入服务器别名:"
    read -r alias
    echo "请输入服务器地址:"
    read -r server
    echo "请输入用户名:"
    read -r user
    if $USE_SSHPASS; then
        echo "请输入密码:"
        read -r -s password
    fi
    echo "请输入端口号:"
    read -r port

    if $USE_SSHPASS; then
        ssh_exec "echo 2>&1" && echo "服务器测试成功，配置已保存。" || echo "服务器连接失败，请检查信息后重试。"
    else
        echo "请输入 SSH 密码进行测试:"
        ssh -o StrictHostKeyChecking=no -p "$port" "$user@$server" "echo 2>&1" && echo "服务器测试成功，配置已保存。" || echo "服务器连接失败，请检查信息后重试。"
    fi

    [[ ! -f "$CONFIG_FILE" ]] && $PLIST_BUDDY -c "Add :Servers array" "$CONFIG_FILE"

    index=$($PLIST_BUDDY -c "Print :Servers" "$CONFIG_FILE" 2>/dev/null | grep "Dict" | wc -l || echo 0)
    $PLIST_BUDDY -c "Add :Servers:$index dict" "$CONFIG_FILE"
    for key in Alias Server User Password Port; do
        value=$(eval echo \$$key)
        $PLIST_BUDDY -c "Add :Servers:$index:$key string $value" "$CONFIG_FILE"
    done
}

# 一键绕过 iCloud 激活锁
bypass_icloud() {
    select_mnt
    echo "一键绕过 iCloud 激活锁功能只能绕过激活锁，设备仍处于未激活状态，建议使用【一键工厂激活 iOS】。"
    echo "是否继续？(Y/N)"
    read -r choice

    if [[ "$choice" == "Y" || "$choice" == "y" ]]; then
        ssh_exec "rm -rf /$mnt/Applications/Setup.app"
        ssh_exec "[ ! -d /$mnt/Applications/Setup.app ]" && echo "成功绕过 iCloud 激活锁，请尝试重启设备。" || echo "绕过失败，可能是权限问题或设备未正确挂载 SSHRamdisk。"
    fi
}

# iOS 5-6 激活
activate_ios5_6() {
    select_mnt

    if [[ ! -f "$LOCKDOWND_FILE" ]]; then
        echo "错误：lockdownd 文件不存在，请将 lockdownd 文件放入 data/ 目录下。"
        return 1
    fi

    scp_exec "$LOCKDOWND_FILE" "$user@$server:/$mnt/usr/libexec/lockdownd"
    ssh_exec "chmod 0755 /$mnt/usr/libexec/lockdownd"
    echo "iOS 5-6 激活完成。"
}

# iOS 7-9 激活
activate_ios7_9() {
    select_mnt
    mkdir -p "$TEMP_DIR"
    scp_exec "$user@$server:/$mnt/mobile/Library/Caches/com.apple.MobileGestalt.plist" "$TEMP_DIR/"

    $PLIST_BUDDY -c "Delete :a6vjPkzcRjrsXmniFsm0dg" "$TEMP_DIR/com.apple.MobileGestalt.plist" 2>/dev/null || true
    $PLIST_BUDDY -c "Add :a6vjPkzcRjrsXmniFsm0dg bool true" "$TEMP_DIR/com.apple.MobileGestalt.plist"

    scp_exec "$TEMP_DIR/com.apple.MobileGestalt.plist" "$user@$server:/$mnt/mobile/Library/Caches/com.apple.MobileGestalt.plist"

    echo "iOS 7-9 激活完成，正在清理临时文件..."
    rm -rf "$TEMP_DIR"
}

# SFTP 文件管理器
sftp_manager() {
    echo "正在通过 SFTP 连接服务器..."
    sftp -oPort="$port" "$user@$server"
}

# 主菜单
main_menu() {
    while true; do
        echo "1. 连接设备"
        echo "2. 一键绕过 iCloud 激活锁"
        echo "3. 一键工厂激活 iOS"
        echo "   3.1 iOS 5-6 激活"
        echo "   3.2 iOS 7-9 激活"
        echo "4. SFTP 文件管理器"
        echo "5. 退出"
        read -r choice

        case $choice in
            1) manage_server_config ;;
            2) bypass_icloud ;;
            3) 
                echo "请选择 iOS 版本："
                read -r sub_choice
                case $sub_choice in
                    1) activate_ios5_6 ;;
                    2) activate_ios7_9 ;;
                esac
                ;;
            4) sftp_manager ;;
            5) exit 0 ;;
        esac
    done
}

main_menu
