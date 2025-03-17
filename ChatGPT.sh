#!/bin/bash

set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$BASE_DIR/data/config.plist"
LOCKDOWND_FILE="$BASE_DIR/data/lockdownd"
TEMP_DIR="$BASE_DIR/data/temp"

PLIST_BUDDY="/usr/libexec/PlistBuddy"

# 创建必要的目录
mkdir -p "$BASE_DIR/data"

# 选择服务器配置
select_server_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "当前无已保存的服务器配置。"
        return 1
    fi

    echo "可用的服务器别名："
    $PLIST_BUDDY -c "Print :Servers" "$CONFIG_FILE" | grep "Dict" | nl
    read -r choice

    selected_alias=$($PLIST_BUDDY -c "Print :Servers:$((choice - 1)):Alias" "$CONFIG_FILE")
    if [[ -z "$selected_alias" ]]; then
        echo "选择无效，请重试。"
        return 1
    fi

    echo "已选择服务器：$selected_alias"
    user=$($PLIST_BUDDY -c "Print :Servers:$((choice - 1)):User" "$CONFIG_FILE")
    server=$($PLIST_BUDDY -c "Print :Servers:$((choice - 1)):Server" "$CONFIG_FILE")
    password=$($PLIST_BUDDY -c "Print :Servers:$((choice - 1)):Password" "$CONFIG_FILE")
    port=$($PLIST_BUDDY -c "Print :Servers:$((choice - 1)):Port" "$CONFIG_FILE")

    return 0
}

# 新建服务器配置
create_server_config() {
    echo "请输入服务器别名:"
    read -r alias
    echo "请输入服务器地址:"
    read -r server
    echo "请输入用户名:"
    read -r user
    echo "请输入密码:"
    read -r -s password
    echo "请输入端口号:"
    read -r port

    echo "测试 SSH 连接..."
    if sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$server" "exit"; then
        echo "服务器测试成功，保存配置..."

        if [[ ! -f "$CONFIG_FILE" ]]; then
            $PLIST_BUDDY -c "Add :Servers array" "$CONFIG_FILE"
        fi

        $PLIST_BUDDY -c "Add :Servers:0 dict" "$CONFIG_FILE"
        $PLIST_BUDDY -c "Add :Servers:0:Alias string $alias" "$CONFIG_FILE"
        $PLIST_BUDDY -c "Add :Servers:0:Server string $server" "$CONFIG_FILE"
        $PLIST_BUDDY -c "Add :Servers:0:User string $user" "$CONFIG_FILE"
        $PLIST_BUDDY -c "Add :Servers:0:Password string $password" "$CONFIG_FILE"
        $PLIST_BUDDY -c "Add :Servers:0:Port string $port" "$CONFIG_FILE"

        echo "配置已保存。"
    else
        echo "连接失败，请检查输入的信息。"
        exit 1
    fi
}

# 选择 SSHRamdisk 挂载目录
select_mnt() {
    echo "请输入 SSHRamdisk 挂载目录 (mnt1, mnt2, mnt3)："
    read -r mnt
}

# iOS 5-6 激活
activate_ios5_6() {
    select_mnt
    if [[ ! -f "$LOCKDOWND_FILE" ]]; then
        echo "错误：lockdownd 文件不存在，请将 lockdownd 文件放入 data/ 目录下。"
        exit 1
    fi

    scp -P "$port" "$LOCKDOWND_FILE" "$user@$server:/$mnt/usr/libexec/lockdownd"
    ssh -p "$port" "$user@$server" "chmod 0755 /$mnt/usr/libexec/lockdownd"
    echo "iOS 5-6 激活完成。"
}

# iOS 7-9 激活
activate_ios7_9() {
    select_mnt
    mkdir -p "$TEMP_DIR"
    scp -P "$port" "$user@$server:/$mnt/mobile/Library/Caches/com.apple.MobileGestalt.plist" "$TEMP_DIR/"

    $PLIST_BUDDY -c "Add :a6vjPkzcRjrsXmniFsm0dg bool true" "$TEMP_DIR/com.apple.MobileGestalt.plist"

    scp -P "$port" "$TEMP_DIR/com.apple.MobileGestalt.plist" "$user@$server:/$mnt/mobile/Library/Caches/com.apple.MobileGestalt.plist"

    echo "iOS 7-9 激活完成，正在清理临时文件..."
    rm -rf "$TEMP_DIR"
    echo "临时文件已删除。"
}

# SFTP 文件管理器
sftp_manager() {
    sftp -oPort="$port" "$user@$server"
}

# 主菜单
main_menu() {
    while true; do
        echo "32位iPhone SSHRamdisk操作工具"
        echo "1. 连接设备"
        echo "2. 一键工厂激活 iOS"
        echo "3. SFTP 文件管理器"
        echo "4. 退出"
        read -r option

        case $option in
        1)
            echo "1. 选择已有配置"
            echo "2. 新建服务器配置"
            read -r sub_option

            if [[ "$sub_option" == "1" ]]; then
                select_server_config || continue
            else
                create_server_config
            fi
            ;;
        2)
            echo "1. iOS 5-6 激活"
            echo "2. iOS 7-9 激活"
            read -r ios_version
            if [[ "$ios_version" == "1" ]]; then
                activate_ios5_6
            else
                activate_ios7_9
            fi
            ;;
        3)
            sftp_manager
            ;;
        4)
            exit 0
            ;;
        *)
            echo "无效输入，请重新选择。"
            ;;
        esac
    done
}

main_menu
