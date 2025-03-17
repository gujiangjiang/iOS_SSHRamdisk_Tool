#!/bin/bash

# 定义程序目录
PROGRAM_DIR=$(dirname "$0")
DATA_DIR="$PROGRAM_DIR/data"
CONFIG_FILE="$DATA_DIR/config.plist"
TEMP_DIR="$DATA_DIR/temp"
LOCKDOWND_FILE="$DATA_DIR/lockdownd"

# 创建数据目录和临时目录
mkdir -p "$DATA_DIR"
mkdir -p "$TEMP_DIR"

# 加载配置
load_config() {
    echo "加载配置..."
    SERVER_ALIAS=$(/usr/libexec/PlistBuddy -c "Print alias" "$CONFIG_FILE")
    SERVER_ADDRESS=$(/usr/libexec/PlistBuddy -c "Print address" "$CONFIG_FILE")
    USERNAME=$(/usr/libexec/PlistBuddy -c "Print username" "$CONFIG_FILE")
    PASSWORD=$(/usr/libexec/PlistBuddy -c "Print password" "$CONFIG_FILE")
    PORT=$(/usr/libexec/PlistBuddy -c "Print port" "$CONFIG_FILE")
    echo "配置加载完成: $SERVER_ALIAS"
}

# 保存配置
save_config() {
    echo "保存配置..."
    /usr/libexec/PlistBuddy -c "Add alias string '$SERVER_ALIAS'" "$CONFIG_FILE" > /dev/null
    /usr/libexec/PlistBuddy -c "Add address string '$SERVER_ADDRESS'" "$CONFIG_FILE" > /dev/null
    /usr/libexec/PlistBuddy -c "Add username string '$USERNAME'" "$CONFIG_FILE" > /dev/null
    /usr/libexec/PlistBuddy -c "Add password string '$PASSWORD'" "$CONFIG_FILE" > /dev/null
    /usr/libexec/PlistBuddy -c "Add port string '$PORT'" "$CONFIG_FILE" > /dev/null
}

# 测试 SSH 连接
test_ssh_connection() {
    if ssh -p "$PORT" "$USERNAME@$SERVER_ADDRESS" echo "连接成功"; then
        return 0
    else
        echo "连接失败，请检查配置。"
        return 1
    fi
}

# 输入挂载点
input_mount_point() {
    read -p "请输入SSHRamdisk挂载目录 (如mnt1, mnt2等): " MOUNT_DIR
    echo "$MOUNT_DIR"
}

# 连接设备
connect_device() {
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "存在已保存的数据，是否一键引用？(y/n)"
        read -p "选择: " use_existing
        if [[ "$use_existing" == "y" ]]; then
            load_config
            return
        fi
    fi

    echo "新建服务器配置..."
    read -p "服务器别名: " SERVER_ALIAS
    read -p "服务器地址: " SERVER_ADDRESS
    read -p "用户名: " USERNAME
    read -p "密码: " PASSWORD
    read -p "端口号: " PORT

    if test_ssh_connection; then
        echo "服务器测试成功，配置已保存。"
        save_config
    fi
}

# 一键绕过iCloud激活锁
bypass_icloud_lock() {
    echo "【一键绕过iCloud激活锁】"
    MOUNT_DIR=$(input_mount_point)

    echo "注意：该功能只能绕过iCloud激活锁，设备仍处于未激活状态，无法正常使用iTunes同步及爱思助手等工具安装应用。"
    read -p "是否跳转到【一键工厂激活iOS】功能？(y/n): " jump_to_activate

    if [[ "$jump_to_activate" == "y" ]]; then
        activate_ios
        return
    fi

    echo "开始绕过iCloud激活锁..."
    ssh -p "$PORT" "$USERNAME@$SERVER_ADDRESS" "rm -rf /$MOUNT_DIR/Applications/Setup.app"

    # 验证是否删除成功
    if ssh -p "$PORT" "$USERNAME@$SERVER_ADDRESS" "test ! -e /$MOUNT_DIR/Applications/Setup.app"; then
        echo "成功绕过iCloud激活锁！"
    else
        echo "绕过失败，请检查挂载点和连接状态。"
    fi
}

# iOS5-iOS6激活
activate_ios5_6() {
    if [[ ! -f "$LOCKDOWND_FILE" ]]; then
        echo "错误：未找到lockdownd文件，请将其放置于$DATA_DIR目录中。"
        return
    fi

    MOUNT_DIR=$(input_mount_point)
    echo "开始iOS5-iOS6激活..."
    scp -P "$PORT" "$LOCKDOWND_FILE" "$USERNAME@$SERVER_ADDRESS:/$MOUNT_DIR/usr/libexec/lockdownd"
    ssh -p "$PORT" "$USERNAME@$SERVER_ADDRESS" "chmod 0755 /$MOUNT_DIR/usr/libexec/lockdownd"
    if [[ $? -eq 0 ]]; then
        echo "激活成功"
    else
        echo "激活失败，请检查配置和连接。"
    fi
}

# iOS7-iOS9激活
activate_ios7_9() {
    MOUNT_DIR=$(input_mount_point)
    echo "开始iOS7-iOS9激活..."
    scp -P "$PORT" "$USERNAME@$SERVER_ADDRESS:/$MOUNT_DIR/mobile/Library/Caches/com.apple.MobileGestalt.plist" "$TEMP_DIR/"
    
    # 使用PlistBuddy修改plist文件
    /usr/libexec/PlistBuddy -c "Add a6vjPkzcRjrsXmniFsm0dg bool true" "$TEMP_DIR/com.apple.MobileGestalt.plist"
    
    scp -P "$PORT" "$TEMP_DIR/com.apple.MobileGestalt.plist" "$USERNAME@$SERVER_ADDRESS:/$MOUNT_DIR/mobile/Library/Caches/com.apple.MobileGestalt.plist"
    if [[ $? -eq 0 ]]; then
        echo "激活成功"
        # 删除temp文件夹
        rm -rf "$TEMP_DIR"
        mkdir -p "$TEMP_DIR"
    else
        echo "激活失败，请检查配置和连接。"
    fi
}

# 一键工厂激活iOS
activate_ios() {
    echo "选择激活版本:"
    echo "1. iOS5-iOS6激活"
    echo "2. iOS7-iOS9激活"
    read -p "选择: " version_choice

    case $version_choice in
        1) activate_ios5_6 ;;
        2) activate_ios7_9 ;;
        *) echo "无效选择，返回主菜单。" ;;
    esac
}

# SFTP文件管理器
sftp_manager() {
    echo "SFTP文件管理器"
    sftp -P "$PORT" "$USERNAME@$SERVER_ADDRESS"
}

# 主菜单
main_menu() {
    while true; do
        echo "=============================="
        echo " 32位iPhone SSHRamdisk操作工具 "
        echo "=============================="
        echo "1. 连接设备"
        echo "2. 一键绕过iCloud激活锁"
        echo "3. 一键工厂激活iOS"
        echo "4. sftp文件管理器"
        echo "5. 退出"
        read -p "请选择操作: " choice

        case $choice in
            1) connect_device ;;
            2) bypass_icloud_lock ;;
            3) activate_ios ;;
            4) sftp_manager ;;
            5) exit 0 ;;
            *) echo "无效选择，请重新输入。" ;;
        esac
    done
}

# 运行主菜单
main_menu