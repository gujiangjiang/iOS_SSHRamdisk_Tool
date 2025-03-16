#!/bin/bash

# 程序目录
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPENDENCIES_DIR="$BASE_DIR/data/dependencies"
CONFIG_DIR="$BASE_DIR/data"
TEMP_DIR="$BASE_DIR/data/temp"
LOCKDOWND_FILE="$BASE_DIR/data/lockdownd"

# 确保目录存在
mkdir -p "$DEPENDENCIES_DIR" "$CONFIG_DIR" "$TEMP_DIR"

# 检查并下载 jq
if ! command -v jq &> /dev/null; then
    echo "Downloading jq..."
    curl -L -o "$DEPENDENCIES_DIR/jq" https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
    chmod +x "$DEPENDENCIES_DIR/jq"
    alias jq="$DEPENDENCIES_DIR/jq"
fi

# 主菜单
main_menu() {
    while true; do
        clear
        echo "32位iPhone SSHRamdisk操作工具"
        echo "1. 连接设备"
        echo "2. 一键工厂激活iOS"
        echo "3. sftp文件管理器"
        echo "4. 退出"
        read -p "请选择选项: " choice

        case $choice in
            1) connect_device ;;
            2) activate_ios ;;
            3) sftp_manager ;;
            4) exit ;;
            *) echo "无效选项，请重试" ;;
        esac
    done
}

# 连接设备
connect_device() {
    CONFIG_FILE="$CONFIG_DIR/device_config.json"
    if [ -f "$CONFIG_FILE" ]; then
        read -p "存在已保存的数据，是否一键引用? (y/n): " use_saved
        if [[ "$use_saved" == "y" ]]; then
            config=$(jq -r '.' "$CONFIG_FILE")
            eval "$config"
            echo "配置已加载"
            return
        fi
    fi

    read -p "输入服务器别名: " alias
    read -p "输入用户名: " username
    read -sp "输入密码: " password
    echo
    read -p "输入端口号: " port
    read -p "输入服务器地址: " server

    # 测试连接
    ssh -p "$port" "$username@$server" "echo 'Connection successful'" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "服务器测试成功，配置已保存"
        jq -n --arg alias "$alias" --arg username "$username" --arg password "$password" --arg port "$port" --arg server "$server" \
            '{alias: $alias, username: $username, password: $password, port: $port | tonumber, server: $server}' > "$CONFIG_FILE"
    else
        echo "连接失败，请检查输入信息"
    fi
}

# 一键工厂激活iOS
activate_ios() {
    read -p "该激活无法支持SIM卡及通话，是否了解? (y/n): " understand
    if [[ "$understand" != "y" ]]; then
        echo "请先了解相关提示"
        return
    fi

    read -p "选择激活版本 (1. iOS5-iOS6, 2. iOS7-iOS9): " version
    read -p "输入SSHRamdisk挂载目录 (如mnt1): " mnt_dir

    if [[ "$version" == "1" ]]; then
        scp -P "$port" "$LOCKDOWND_FILE" "$username@$server:/mnt$mnt_dir/usr/libexec/lockdownd"
        ssh -p "$port" "$username@$server" "chmod 0755 /mnt$mnt_dir/usr/libexec/lockdownd"
        if [ $? -eq 0 ]; then
            echo "激活成功"
        else
            echo "激活失败"
        fi
    elif [[ "$version" == "2" ]]; then
        scp -P "$port" "$username@$server:/mnt$mnt_dir/mobile/Library/Caches/com.apple.MobileGestalt.plist" "$TEMP_DIR"
        plist_file="$TEMP_DIR/com.apple.MobileGestalt.plist"
        # 使用 PlistBuddy 或其他工具修改 plist 文件
        /usr/libexec/PlistBuddy -c "Add :a6vjPkzcRjrsXmniFsm0dg bool true" "$plist_file"
        scp -P "$port" "$plist_file" "$username@$server:/mnt$mnt_dir/mobile/Library/Caches/com.apple.MobileGestalt.plist"
        if [ $? -eq 0 ]; then
            echo "激活成功"
        else
            echo "激活失败"
        fi
    else
        echo "无效选项"
    fi
}

# sftp文件管理器
sftp_manager() {
    sftp -P "$port" "$username@$server"
}

# 启动程序
main_menu
