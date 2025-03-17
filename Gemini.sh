#!/bin/bash

# 全局变量
address=""
username=""
password=""
port=""
mnt_dir=""

# 目录变量
DEPENDENCIES_DIR="data/dependencies"
CONFIG_DIR="data"
TEMP_DIR="data/temp"
LOCKDOWND_FILE="data/lockdownd"
CONFIG_FILE="$CONFIG_DIR/config.json"
TEMP_PLIST="$TEMP_DIR/com.apple.MobileGestalt.plist"
JQ_FILE="$DEPENDENCIES_DIR/jq"

# 创建目录
mkdir -p "$DEPENDENCIES_DIR"
mkdir -p "$TEMP_DIR"

# 检查 jq 是否存在，如果不存在则下载
if [ ! -f "$JQ_FILE" ]; then
    echo "检测到 jq 不存在，正在下载..."
    curl -L -o "$JQ_FILE" "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64"
    chmod +x "$JQ_FILE"
    echo "jq 下载完成！"
fi

# 加载配置文件
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        config=$(cat "$CONFIG_FILE")
    else
        config="{}"
    fi
}

# 保存配置文件
save_config() {
    echo "$config" > "$CONFIG_FILE"
}

# 测试 SSH 连接
test_ssh_connection() {
    ssh -o StrictHostKeyChecking=no "$username@$address" -p "$port" "echo 'SSH 连接测试成功！'" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "SSH 连接测试成功！"
        return 0
    else
        echo "SSH 连接测试失败！"
        return 1
    fi
}

# 连接设备
connect_device() {
    load_config
    if [[ $(echo "$config" | "$JQ_FILE" -r 'keys | length') -gt 0 ]]; then
        echo "已保存的服务器："
        echo "$config" | "$JQ_FILE" -r 'keys[]' | while read alias; do
            echo "- $alias"
        done
        read -p "是否选择已保存的服务器？ (y/n): " choice
        if [[ "$choice" == "y" ]]; then
            read -p "请输入服务器别名： " alias
            server_data=$(echo "$config" | "$JQ_FILE" -r ".[\"$alias\"]")
            if [[ -n "$server_data" ]]; then
                address=$(echo "$server_data" | "$JQ_FILE" -r ".address")
                username=$(echo "$server_data" | "$JQ_FILE" -r ".username")
                password=$(echo "$server_data" | "$JQ_FILE" -r ".password")
                port=$(echo "$server_data" | "$JQ_FILE" -r ".port")
                return 0
            else
                echo "未找到该服务器！"
                return 1
            fi
        fi
    fi
    read -p "服务器别名： " alias
    read -p "服务器地址： " address
    read -p "用户名： " username
    read -p "密码： " password
    read -p "端口号： " port
    if test_ssh_connection; then
        echo "服务器测试成功，配置已保存！"
        config=$(echo "$config" | "$JQ_FILE" --arg alias "$alias" --arg address "$address" --arg username "$username" --arg password "$password" --arg port "$port" '. + { ($alias): {address: $address, username: $username, password: $password, port: $port} }')
        save_config
        return 0
    else
        echo "服务器测试失败！"
        return 1
    fi
}

# iOS 5-iOS 6 激活
activate_ios_5_6() {
    scp -P "$port" "$LOCKDOWND_FILE" "$username@$address:$mnt_dir/usr/libexec/lockdownd"
    ssh -o StrictHostKeyChecking=no "$username@$address" -p "$port" "chmod 0755 $mnt_dir/usr/libexec/lockdownd"
    if [ $? -eq 0 ]; then
        echo "激活成功！"
    else
        echo "激活失败！"
    fi
}

# iOS 7-iOS 9 激活
activate_ios_7_9() {
    scp -P "$port" "$username@$address:$mnt_dir/mobile/Library/Caches/com.apple.MobileGestalt.plist" "$TEMP_PLIST"
    plutil -replace "a6vjPkzcRjrsXmniFsm0dg" -bool true "$TEMP_PLIST"
    scp -P "$port" "$TEMP_PLIST" "$username@$address:$mnt_dir/mobile/Library/Caches/com.apple.MobileGestalt.plist"
    if [ $? -eq 0 ]; then
        echo "激活成功！"
    else
        echo "激活失败！"
    fi
}

# 一键工厂激活 iOS
factory_activate_ios() {
    if [[ -z "$address" ]]; then
        echo "请先连接设备！"
        return 1
    fi
    read -p "该激活无法支持 SIM 卡及通话，是否了解？ (y/n): " choice
    if [[ "$choice" != "y" ]]; then
        return 1
    fi
    read -p "请输入 SSHRamdisk 挂载目录 (例如 mnt1)： " mnt_dir
    echo "选择激活方式："
    echo "1. iOS 5-iOS 6 激活"
    echo "2. iOS 7-iOS 9 激活"
    read -p "请选择： " choice
    case "$choice" in
    1)
        activate_ios_5_6
        ;;
    2)
        activate_ios_7_9
        ;;
    *)
        echo "无效的选择！"
        ;;
    esac
}

# SFTP 文件管理器
sftp_file_manager() {
    if [[ -z "$address" ]]; then
        echo "请先连接设备！"
        return 1
    fi
    sftp -o StrictHostKeyChecking=no -P "$port" "$username@$address"
}

# 主菜单
main_menu() {
    while true; do
        echo ""
        echo "32 位 iPhone SSHRamdisk 操作工具"
        echo "1. 连接设备"
        echo "2. 一键工厂激活 iOS"
        echo "3. SFTP 文件管理器"
        echo "4. 退出"
        read -p "请选择： " choice
        case "$choice" in
        1)
            connect_device
            ;;
        2)
            factory_activate_ios
            ;;
        3)
            sftp_file_manager
            ;;
        4)
            exit 0
            ;;
        *)
            echo "无效的选择！"
            ;;
        esac
    done
}

# 运行主菜单
main_menu