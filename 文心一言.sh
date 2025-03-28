#!/bin/bash

# 程序目录
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$BASE_DIR/data"
TEMP_DIR="$BASE_DIR/data/temp"
LOCKDOWND_FILE="$BASE_DIR/data/lockdownd"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
CONFIG_FILE="$CONFIG_DIR/device_config.plist"

# 确保目录存在
mkdir -p "$CONFIG_DIR" "$TEMP_DIR"

# 函数：显示主菜单
main_menu() {
    while true; do
        clear
        echo "32位iPhone SSHRamdisk操作工具"
        echo "1. 连接设备"
        echo "2. 一键绕过iCloud激活锁"
        echo "3. 一键工厂激活iOS"
        echo "4. sftp文件管理器"
        echo "5. 退出"
        read -p "请选择选项: " choice

        case $choice in
            1) connect_device ;;
            2) bypass_icloud_activation_lock ;;
            3) activate_ios ;;
            4) sftp_manager ;;
            5) exit ;;
            *) echo "无效选项，请重试" ;;
        esac
    done
}

# 函数：连接设备
connect_device() {
    if [ -f "$CONFIG_FILE" ]; then
        read -p "存在已保存的数据，是否一键引用? (y/n): " use_saved
        if [[ "$use_saved" == "y" ]]; then
            eval "$($PLIST_BUDDY -c "Print :" "$CONFIG_FILE")"
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

    if test_connection "$username" "$password" "$port" "$server"; then
        save_config "$alias" "$username" "$password" "$port" "$server"
    else
        echo "连接失败，请检查输入信息"
    fi
}

# 函数：测试SSH连接
test_connection() {
    local username=$1
    local password=$2
    local port=$3
    local server=$4
    sshpass -p "$password" ssh -p "$port" "$username@$server" "echo 'Connection successful'" >/dev/null 2>&1
    return $?
}

# 函数：保存设备配置
save_config() {
    local alias=$1
    local username=$2
    local password=$3
    local port=$4
    local server=$5
    echo "服务器测试成功，配置已保存"
    $PLIST_BUDDY -c "Add :alias string '$alias'" "$CONFIG_FILE" 2>/dev/null
    $PLIST_BUDDY -c "Set :username '$username'" "$CONFIG_FILE"
    $PLIST_BUDDY -c "Set :password '$password'" "$CONFIG_FILE"
    $PLIST_BUDDY -c "Set :port $port" "$CONFIG_FILE"
    $PLIST_BUDDY -c "Set :server '$server'" "$CONFIG_FILE"
}

# 函数：一键绕过iCloud激活锁
bypass_icloud_activation_lock() {
    read -p "请确认挂载点（如：mnt1, mnt2）：" mount_point
    echo "注意：一键绕过iCloud激活锁功能只能绕过激活锁，设备仍无法正常使用iTunes同步及爱思助手等功能。"
    echo "建议使用【一键工厂激活iOS】功能进行完整激活。"
    
    read -p "是否继续绕过iCloud激活锁？(y/n): " confirm
    if [[ $confirm == "y" ]]; then
        echo "跳转到【一键工厂激活iOS】功能..."
        activate_ios
        return
    else
        remove_setup_app "$mount_point"
    fi
}

# 函数：删除Setup.app
remove_setup_app() {
    local mount_point=$1
    sshpass -p "$password" ssh -p "$port" "$username@$server" "rm -rf /$mount_point/Applications/Setup.app"
    if [ $? -eq 0 ]; then
        echo "验证删除结果..."
        if sshpass -p "$password" ssh -p "$port" "$username@$server" "[ -d /$mount_point/Applications/Setup.app ] && echo \"Exists\" || echo \"Not Exists\"" | grep -q "Not Exists"; then
            echo "成功绕过iCloud激活锁"
        else
            echo "绕过iCloud激活锁失败，请检查SSH连接或挂载点路径。"
        fi
    else
        echo "删除Setup.app失败，请检查SSH连接或权限。"
    fi
}

# 函数：一键工厂激活iOS
activate_ios() {
    read -p "该激活无法支持SIM卡及通话，是否了解? (y/n): " understand
    if [[ "$understand" != "y" ]]; then
        echo "请先了解相关提示"
        return
    fi

    read -p "选择激活版本 (1. iOS5-iOS6, 2. iOS7-iOS9): " version
    read -p "输入SSHRamdisk挂载目录 (如mnt1): " mnt_dir

    if [[ "$version" == "1" ]]; then
        activate_old_version "$mnt_dir"
    elif [[ "$version" == "2" ]]; then
        activate_new_version "$mnt_dir"
    else
        echo "无效选项"
    fi
}

# 函数：激活旧版本iOS
activate_old_version() {
    local mnt_dir=$1
    scp -P "$port" "$LOCKDOWND_FILE" "$username@$server:/mnt$mnt_dir/usr/libexec/lockdownd"
    sshpass -p "$password" ssh -p "$port" "$username@$server" "chmod 0755 /mnt$mnt_dir/usr/libexec/lockdownd"
    if [ $? -eq 0 ]; then
        echo "激活成功"
    else
        echo "激活失败"
    fi
}

# 函数：激活新版本iOS
activate_new_version() {
    local mnt_dir=$1
    scp -P "$port" "$username@$server:/mnt$mnt_dir/mobile/Library/Caches/com.apple.MobileGestalt.plist" "$TEMP_DIR"
    plist_file="$TEMP_DIR/com.apple.MobileGestalt.plist"
    $PLIST_BUDDY -c "Add :a6vjPkzcRjrsXmniFsm0dg bool true" "$plist_file"
    scp -P "$port" "$plist_file" "$username@$server:/mnt$mnt_dir/mobile/Library/Caches/com.apple.MobileGestalt.plist"
    if [ $? -eq 0 ]; then
        echo "激活成功"
    else
        echo "激活失败"
    fi
}

# 函数：sftp文件管理器
sftp_manager() {
    sshpass -p "$password" sftp -P "$port" "$username@$server"
}

# 启动程序
main_menu