#!/bin/bash

# 程序目录
PROGRAM_DIR=$(dirname "$0")
DATA_DIR="$PROGRAM_DIR/data"
CONFIG_PLIST="$DATA_DIR/config.plist"
TEMP_DIR="$DATA_DIR/temp"

# 确保目录存在
mkdir -p "$DATA_DIR" "$TEMP_DIR"

# 定义PlistBuddy路径
PLIST_BUDDY="/usr/libexec/PlistBuddy"

# 主菜单
main_menu() {
    echo "32位iPhone SSHRamdisk操作工具"
    echo "1. 连接设备"
    echo "2. 一键绕过iCloud激活锁"
    echo "3. 一键工厂激活iOS"
    echo "4. SFTP文件管理器"
    echo "5. 退出"
    read -p "请选择: " choice
    case $choice in
        1) connect_device ;;
        2) bypass_icloud_lock ;;
        3) factory_activate_ios ;;
        4) sftp_manager ;;
        5) exit 0 ;;
        *) echo "无效选择，请重试。" ; main_menu ;;
    esac
}

# 连接设备
connect_device() {
    if [ -f "$CONFIG_PLIST" ]; then
        echo "存在已保存的数据，是否一键引用？(y/n)"
        read choice
        if [ "$choice" = "y" ]; then
            alias=$($PLIST_BUDDY -c "Print :alias" "$CONFIG_PLIST")
            username=$($PLIST_BUDDY -c "Print :username" "$CONFIG_PLIST")
            password=$($PLIST_BUDDY -c "Print :password" "$CONFIG_PLIST")
            port=$($PLIST_BUDDY -c "Print :port" "$CONFIG_PLIST")
            echo "引用配置: $alias"
        else
            create_new_config
        fi
    else
        create_new_config
    fi
    test_ssh_connection
}

# 创建新配置
create_new_config() {
    read -p "请输入服务器别名: " alias
    read -p "请输入用户名: " username
    read -p "请输入密码: " password
    read -p "请输入端口号: " port
    save_config "$alias" "$username" "$password" "$port"
}

# 保存配置
save_config() {
    local alias=$1
    local username=$2
    local password=$3
    local port=$4
    $PLIST_BUDDY -c "Add :alias string $alias" "$CONFIG_PLIST" 2>/dev/null || $PLIST_BUDDY -c "Set :alias $alias" "$CONFIG_PLIST"
    $PLIST_BUDDY -c "Add :username string $username" "$CONFIG_PLIST" 2>/dev/null || $PLIST_BUDDY -c "Set :username $username" "$CONFIG_PLIST"
    $PLIST_BUDDY -c "Add :password string $password" "$CONFIG_PLIST" 2>/dev/null || $PLIST_BUDDY -c "Set :password $password" "$CONFIG_PLIST"
    $PLIST_BUDDY -c "Add :port integer $port" "$CONFIG_PLIST" 2>/dev/null || $PLIST_BUDDY -c "Set :port $port" "$CONFIG_PLIST"
    echo "配置已保存。"
}

# 测试SSH连接并保存配置
test_ssh_connection() {
    echo "正在测试SSH连接..."
    if sshpass -p "$password" ssh -p "$port" "$username@localhost" echo "连接成功"; then
        echo "服务器测试成功，配置已保存。"
    else
        echo "连接失败，请检查配置。"
    fi
    main_menu
}

# 一键绕过iCloud激活锁
bypass_icloud_lock() {
    echo "一键绕过iCloud激活锁功能说明："
    echo "此功能仅能绕过iCloud激活锁，设备仍处于未激活状态，无法正常使用iTunes同步及爱思助手等设备安装应用。"
    echo "建议优先使用【一键工厂激活iOS】功能。"
    read -p "是否继续？(y/n): " choice
    if [ "$choice" = "y" ]; then
        if [ -f "$CONFIG_PLIST" ]; then
            port=$($PLIST_BUDDY -c "Print :port" "$CONFIG_PLIST")
            username=$($PLIST_BUDDY -c "Print :username" "$CONFIG_PLIST")
            password=$($PLIST_BUDDY -c "Print :password" "$CONFIG_PLIST")
        else
            echo "请先连接设备并保存配置。"
            main_menu
            return
        fi

        read -p "请输入SSHRamdisk挂载目录（如mnt1、mnt2等）: " mount_dir
        echo "正在尝试绕过iCloud激活锁..."
        sshpass -p "$password" ssh -p "$port" "$username@localhost" "rm -rf /$mount_dir/Applications/Setup.app"
        sleep 2
        sshpass -p "$password" ssh -p "$port" "$username@localhost" "if [ ! -d '/$mount_dir/Applications/Setup.app' ]; then echo 'Setup.app已删除'; else echo 'Setup.app仍然存在'; fi"
        if sshpass -p "$password" ssh -p "$port" "$username@localhost" "test ! -d '/$mount_dir/Applications/Setup.app'"; then
            echo "成功绕过iCloud激活锁。"
            echo "设备仍处于未激活状态，建议进行进一步操作。"
        else
            echo "绕过失败，请检查设备状态或重试。"
        fi
    fi
    main_menu
}

# 一键工厂激活iOS
factory_activate_ios() {
    echo "该激活无法支持SIM卡及通话，是否继续？(y/n)"
    read choice
    if [ "$choice" = "y" ]; then
        echo "请选择iOS版本："
        echo "1. iOS5-iOS6激活"
        echo "2. iOS7-iOS9激活"
        read version
        if [ "$version" = "1" ]; then
            activate_ios5_6
        elif [ "$version" = "2" ]; then
            activate_ios7_9
        else
            echo "无效选择。"
        fi
    fi
    main_menu
}

# iOS5-iOS6激活
activate_ios5_6() {
    # iOS5-iOS6激活逻辑（保持原有代码）
    echo "iOS5-iOS6激活功能尚未实现。"
}

# iOS7-iOS9激活
activate_ios7_9() {
    # iOS7-iOS9激活逻辑（保持原有代码）
    echo "iOS7-iOS9激活功能尚未实现。"
}

# SFTP文件管理器
sftp_manager() {
    echo "请输入用户名: "
    read username
    echo "请输入密码: "
    read -s password
    echo "请输入端口号: "
    read port
    sftp -P "$port" "$username@localhost"
    main_menu
}

# 主程序
main_menu