#!/bin/bash

# 全局变量
address=""
username=""
password=""
port=""
mnt_dir=""

# 目录变量
CONFIG_DIR="data"
TEMP_DIR="data/temp"
LOCKDOWND_FILE="data/lockdownd"
CONFIG_FILE="$CONFIG_DIR/config.plist"
TEMP_PLIST="$TEMP_DIR/com.apple.MobileGestalt.plist"
PLUTIL="/usr/libexec/PlistBuddy"

# 提示信息
SUCCESS_BYPASS="成功绕过 iCloud 激活锁！"
FAILED_BYPASS="绕过 iCloud 激活锁失败！"

# 创建目录
mkdir -p "$TEMP_DIR"

# 加载配置文件
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        config=$("$PLUTIL" -c "Print" "$CONFIG_FILE")
    else
        config=""
    fi
}

# 保存配置文件
save_config() {
    "$PLUTIL" -c "Clear" "$CONFIG_FILE"
    for key in "${!config_data[@]}"; do
        "$PLUTIL" -c "Add :$key string ${config_data[$key]}" "$CONFIG_FILE"
    done
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
    if [[ -n "$config" ]]; then
        echo "已保存的服务器："
        "$PLUTIL" -c "Print :Aliases" "$CONFIG_FILE" | while read alias; do
            echo "- $alias"
        done
        read -p "是否选择已保存的服务器？ (y/n): " choice
        if [[ "$choice" == "y" ]]; then
            read -p "请输入服务器别名： " alias
            address=$("$PLUTIL" -c "Print :$alias:address" "$CONFIG_FILE")
            username=$("$PLUTIL" -c "Print :$alias:username" "$CONFIG_FILE")
            password=$("$PLUTIL" -c "Print :$alias:password" "$CONFIG_FILE")
            port=$("$PLUTIL" -c "Print :$alias:port" "$CONFIG_FILE")
            if [[ -n "$address" ]]; then
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
        # 先将配置数据存储在关联数组中
        config_data["$alias:address"]="$address"
        config_data["$alias:username"]="$username"
        config_data["$alias:password"]="$password"
        config_data["$alias:port"]="$port"
        # 然后保存配置文件
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
    "$PLUTIL" -replace "a6vjPkzcRjrsXmniFsm0dg" -bool true "$TEMP_PLIST"
    scp -P "$port" "$TEMP_PLIST" "$username@$address:$mnt_dir/mobile/Library/Caches/com.apple.MobileGestalt.plist"
    if [ $? -eq 0 ]; then
        echo "激活成功！"
        # 删除临时文件夹
        rm -rf "$TEMP_DIR"
        mkdir -p "$TEMP_DIR" #重新创建临时文件夹。
    else
        echo "激活失败！"
    fi
}

# 读取挂载点
read_mount_point() {
    read -p "请输入 SSHRamdisk 挂载目录 (例如 mnt1)： " mnt_dir
}

# 一键工厂激活 iOS
factory_activate_ios() {
    if [[ -z "$address" ]]; then
        echo "请先连接设备！"
        return 1
    fi
    read_mount_point
    echo "该激活无法支持 SIM 卡及通话，是否了解？ (y/n): "
    read -p "请选择： " choice
    if [[ "$choice" != "y" ]]; then
        return 1
    fi
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

# 一键绕过 iCloud 激活锁
bypass_icloud_activation_lock() {
    if [[ -z "$address" ]]; then
        echo "请先连接设备！"
        return 1
    fi
    read_mount_point
    echo "一键绕过 iCloud 激活锁功能只能绕过，设备仍处于未激活状态，无法正常使用 iTunes 同步及爱思助手等设备安装应用，建议使用【一键工厂激活 iOS】功能。"
    read -p "是否跳转到【一键工厂激活 iOS】？ (y/n): " choice
    if [[ "$choice" == "y" ]]; then
        factory_activate_ios
        return
    fi
    ssh -o StrictHostKeyChecking=no "$username@$address" -p "$port" "rm -rf $mnt_dir/Applications/Setup.app"
    if [ $? -eq 0 ]; then
        if ssh -o StrictHostKeyChecking=no "$username@$address" -p "$port" "test -e $mnt_dir/Applications/Setup.app"; then
            echo "$FAILED_BYPASS"
        else
            echo "$SUCCESS_BYPASS"
        fi
    else
        echo "$FAILED_BYPASS"
    fi
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
        echo "2. 一键绕过 iCloud 激活锁"
        echo "3. 一键工厂激活 iOS"
        echo "4. SFTP 文件管理器"
        echo "5. 退出"
        read -p "请选择： " choice
        case "$choice" in
        1)
            connect_device
            ;;
        2)
            bypass_icloud_activation_lock
            ;;
        3)
            factory_activate_ios
            ;;
        4)
            sftp_file_manager
            ;;
        5)
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