#!/bin/bash

# 获取脚本所在的目录
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
# 定义数据目录路径
DATA_DIR="$BASE_DIR/data"
# 定义配置文件路径
CONFIG_FILE="$DATA_DIR/config.plist"
# 定义lockdownd文件路径
LOCKDOWND_PATH="$DATA_DIR/lockdownd"
# 定义临时目录路径
TEMP_DIR="$DATA_DIR/temp"
# 定义PlistBuddy工具路径
PLIST_BUDDY="/usr/libexec/PlistBuddy"

# 确保数据目录和临时目录存在，如果不存在则创建
ensure_directories() {
    if [ ! -d "$DATA_DIR" ]; then mkdir -p "$DATA_DIR"; fi
    if [ ! -d "$TEMP_DIR" ]; then mkdir -p "$TEMP_DIR"; fi
}

# 加载配置文件，如果没有配置文件则创建一个基本的config.plist文件
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Count</key>
    <integer>0</integer>
</dict>
</plist>" > "$CONFIG_FILE"
    fi
    CONFIG_COUNT=$($PLIST_BUDDY -c "Print :Count" "$CONFIG_FILE")
}

# 保存配置文件，更新服务器数量
save_config() {
    $PLIST_BUDDY -c "Set :Count $CONFIG_COUNT" "$CONFIG_FILE"
}

# 添加新的服务器配置
add_server_config() {
    read -p "请输入服务器别名: " alias
    read -p "请输入用户名: " username
    password=$(getpass "请输入密码: ")
    read -p "请输入端口号: " port
    read -p "请输入挂载点 (例如, mnt1): " mount_point

    if test_connection "$alias" "$username" "$password" "$port"; then
        # 增加服务器数量计数器
        CONFIG_COUNT=$((CONFIG_COUNT + 1))
        # 向配置文件中添加新的服务器配置
        $PLIST_BUDDY -c "Add :$CONFIG_COUNT dict" "$CONFIG_FILE"
        $PLIST_BUDDY -c "Add :$CONFIG_COUNT:Alias string $alias" "$CONFIG_FILE"
        $PLIST_BUDDY -c "Add :$CONFIG_COUNT:Username string $username" "$CONFIG_FILE"
        $PLIST_BUDDY -c "Add :$CONFIG_COUNT:Password string $password" "$CONFIG_FILE"
        $PLIST_BUDDY -c "Add :$CONFIG_COUNT:Port integer $port" "$CONFIG_FILE"
        $PLIST_BUDDY -c "Add :$CONFIG_COUNT:MountPoint string $mount_point" "$CONFIG_FILE"
        save_config
        echo "服务器配置已保存。"
    else
        echo "连接失败。配置未保存。"
    fi
}

# 测试SSH连接
test_connection() {
    local alias=$1
    local username=$2
    local password=$3
    local port=$4
    expect <<EOF
log_user 0
spawn ssh -o StrictHostKeyChecking=no -p "$port" "$username"@localhost echo "已连接到 $alias"
expect "password:"
send "$password\r"
expect eof
log_user 1
EOF
    grep -q "已连接到 $alias" /tmp/ssh_output.log
}

# 连接设备，加载或添加新的服务器配置
connect_device() {
    load_config
    if [ "$CONFIG_COUNT" -gt 0 ]; then
        echo "找到现有配置。是否要使用其中一个？ (y/n)"
        read use_existing
        if [ "$use_existing" == "y" ]; then
            for ((i=1; i<=CONFIG_COUNT; i++)); do
                alias=$($PLIST_BUDDY -c "Print :$i:Alias" "$CONFIG_FILE")
                echo "$i: $alias"
            done
            read -p "请选择配置编号: " config_num
            USERNAME=$($PLIST_BUDDY -c "Print :$config_num:Username" "$CONFIG_FILE")
            PASSWORD=$($PLIST_BUDDY -c "Print :$config_num:Password" "$CONFIG_FILE")
            PORT=$($PLIST_BUDDY -c "Print :$config_num:Port" "$CONFIG_FILE")
            MOUNT_POINT=$($PLIST_BUDDY -c "Print :$config_num:MountPoint" "$CONFIG_FILE")
        else
            add_server_config
        fi
    else
        add_server_config
    fi
}

# 激活iOS5-iOS6
activate_ios5_6() {
    read -p "请输入挂载点 (例如, mnt1): " mount_point
    scp -P "$PORT" "$LOCKDOWND_PATH" "$USERNAME@localhost:/$mount_point/usr/libexec/lockdownd"
    if [ $? -ne 0 ]; then
        echo "lockdownd文件传输失败。"
        return 1
    fi
    ssh -p "$PORT" "$USERNAME@localhost" "chmod 0755 /$mount_point/usr/libexec/lockdownd"
    if [ $? -ne 0 ]; then
        echo "设置lockdownd文件权限失败。"
        return 1
    fi
    echo "iOS5-iOS6激活成功。"
}

# 修改com.apple.MobileGestalt.plist以激活iOS7-iOS9
modify_plist() {
    plist_file="$TEMP_DIR/com.apple.MobileGestalt.plist"
    scp -P "$PORT" "$USERNAME@localhost:/$MOUNT_POINT/mobile/Library/Caches/com.apple.MobileGestalt.plist" "$plist_file"
    if [ $? -ne 0 ]; then
        echo "com.apple.MobileGestalt.plist文件传输失败。"
        return 1
    fi
    $PLIST_BUDDY -c "Add :a6vjPkzcRjrsXmniFsm0dg bool true" "$plist_file"
    if [ $? -ne 0 ]; then
        echo "修改com.apple.MobileGestalt.plist文件失败。"
        return 1
    fi
    scp -P "$PORT" "$plist_file" "$USERNAME@localhost:/$MOUNT_POINT/mobile/Library/Caches/com.apple.MobileGestalt.plist"
    if [ $? -ne 0 ]; then
        echo "推送修改后的com.apple.MobileGestalt.plist文件失败。"
        return 1
    fi
    rm -rf "$TEMP_DIR"
    echo "iOS7-iOS9激活成功。"
}

# 激活iOS7-iOS9
activate_ios7_9() {
    modify_plist
}

# 绕过iCloud激活锁
one_key_bypass_icloud_lock() {
    read -p "请输入挂载点 (例如, mnt1): " mount_point
    echo "此功能仅绕过iCloud激活锁。设备仍处于未激活状态，无法使用iTunes同步或其他工具（如Aisi Assistant）。建议使用“一键工厂激活iOS”功能。"
    read -p "是否要转而进行工厂激活？ (y/n): " proceed
    if [ "$proceed" == "y" ]; then
        one_key_factory_activation
    else
        ssh -p "$PORT" "$USERNAME@localhost" "rm -rf /$mount_point/Applications/Setup.app"
        if [ $? -ne 0 ]; then
            echo "删除Setup.app失败。"
            return 1
        fi
        setup_app_exists=$(ssh -p "$PORT" "$USERNAME@localhost" "[ -e /$mount_point/Applications/Setup.app ] && echo exists || echo notexists")
        if [ "$setup_app_exists" == "notexists" ]; then
            echo "成功绕过iCloud激活锁。"
        else
            echo "绕过iCloud激活锁失败。"
        fi
    fi
}

# 工厂激活iOS
one_key_factory_activation() {
    echo "此激活不支持SIM卡和通话功能。"
    read -p "按回车继续..."
    echo "选择激活类型:"
    echo "1. iOS5-iOS6激活"
    echo "2. iOS7-iOS9激活"
    read -p "请输入选项编号 (1/2): " choice
    case $choice in
        1) activate_ios5_6 ;;
        2) activate_ios7_9 ;;
        *) echo "无效的选择，请重新输入。" ;;
    esac
}

# SFTP文件管理器
sftp_file_manager() {
    sftp -oPort="$PORT" "$USERNAME@localhost"
}

# 主菜单
main_menu() {
    while true; do
        echo "32位iPhone SSHRamdisk操作工具"
        echo "1. 连接设备"
        echo "2. 一键绕过iCloud激活锁"
        echo "3. 一键工厂激活iOS"
        echo "4. SFTP文件管理器"
        echo "5. 退出"
        read -p "请输入选项编号: " option
        case $option in
            1) connect_device ;;
            2) one_key_bypass_icloud_lock ;;
            3) one_key_factory_activation ;;
            4) sftp_file_manager ;;
            5) exit ;;
            *) echo "无效的选择，请重新输入。" ;;
        esac
    done
}

# 初始化目录并加载配置文件
ensure_directories
load_config
main_menu



