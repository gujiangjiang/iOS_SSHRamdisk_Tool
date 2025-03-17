#!/bin/bash

# 定义全局变量
PLIST_BUDDY="/usr/libexec/PlistBuddy"
DATA_DIR="data"
TEMP_DIR="$DATA_DIR/temp"
CONFIG_FILE="$DATA_DIR/config.plist"
LOCKDOWN_FILE="$DATA_DIR/lockdownd"

# 创建必要目录
mkdir -p "$DATA_DIR" "$TEMP_DIR"

# 获取服务器配置信息
get_server_config() {
    if [ -f "$CONFIG_FILE" ]; then
        config_count=$("$PLIST_BUDDY" -c "Print :configs:count" "$CONFIG_FILE")
        for ((i = 0; i < config_count; i++)); do
            alias=$("$PLIST_BUDDY" -c "Print :configs:$i:alias" "$CONFIG_FILE")
            echo "$((i + 1)). $alias"
        done
        echo "请选择要使用的配置序号"
        read selected
        selected=$((selected - 1))
        host=$("$PLIST_BUDDY" -c "Print :configs:$selected:host" "$CONFIG_FILE")
        port=$("$PLIST_BUDDY" -c "Print :configs:$selected:port" "$CONFIG_FILE")
        username=$("$PLIST_BUDDY" -c "Print :configs:$selected:username" "$CONFIG_FILE")
        password=$("$PLIST_BUDDY" -c "Print :configs:$selected:password" "$CONFIG_FILE")
    else
        echo "请先连接设备"
        exit 1
    fi
    echo "$host $port $username $password"
}

# 创建新的服务器配置
create_new_config() {
    echo "请输入服务器别名"
    read alias
    echo "请输入服务器地址"
    read host
    echo "请输入用户名"
    read username
    echo "请输入密码"
    read -s password
    echo "请输入端口号"
    read port

    if [ -f "$CONFIG_FILE" ]; then
        # 使用PlistBuddy添加新配置
        "$PLIST_BUDDY" -c "Add :configs: -dict" "$CONFIG_FILE"
        "$PLIST_BUDDY" -c "Set :configs:$((("$PLIST_BUDDY" -c "Print :configs:count" "$CONFIG_FILE") - 1)):alias $alias" "$CONFIG_FILE"
        "$PLIST_BUDDY" -c "Set :configs:$((("$PLIST_BUDDY" -c "Print :configs:count" "$CONFIG_FILE") - 1)):host $host" "$CONFIG_FILE"
        "$PLIST_BUDDY" -c "Set :configs:$((("$PLIST_BUDDY" -c "Print :configs:count" "$CONFIG_FILE") - 1)):username $username" "$CONFIG_FILE"
        "$PLIST_BUDDY" -c "Set :configs:$((("$PLIST_BUDDY" -c "Print :configs:count" "$CONFIG_FILE") - 1)):password $password" "$CONFIG_FILE"
        "$PLIST_BUDDY" -c "Set :configs:$((("$PLIST_BUDDY" -c "Print :configs:count" "$CONFIG_FILE") - 1)):port $port" "$CONFIG_FILE"
    else
        # 创建新的plist文件并添加初始配置
        cat << EOF > "$CONFIG_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>configs</key>
    <array>
        <dict>
            <key>alias</key>
            <string>$alias</string>
            <key>host</key>
            <string>$host</string>
            <key>username</key>
            <string>$username</string>
            <key>password</key>
            <string>$password</string>
            <key>port</key>
            <integer>$port</integer>
        </dict>
    </array>
</dict>
</plist>
EOF
    fi
}

# 连接设备功能
connect_device() {
    if [ -f "$CONFIG_FILE" ]; then
        echo "存在已保存的数据，是否一键引用？(y/n)"
        read choice
        if [ "$choice" = "y" ]; then
            server_info=$(get_server_config)
        else
            create_new_config
            server_info=$(get_server_config)
        fi
    else
        create_new_config
        server_info=$(get_server_config)
    fi

    IFS=' ' read -r host port username password <<< "$server_info"
    ssh -o StrictHostKeyChecking=no -p "$port" "$username"@"$host" exit 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "服务器测试成功，配置已保存"
    else
        echo "连接失败，请检查配置"
    fi
}

# 一键绕过iCloud激活锁功能
one_click_bypass_icloud() {
    server_info=$(get_server_config)
    IFS=' ' read -r host port username password <<< "$server_info"

    echo "请输入SSHRamdisk挂载目录（通常为mnt1、mnt2等）"
    read mount_dir

    echo "一键绕过iCloud激活锁功能只能绕过，设备仍处于未激活状态，无法正常使用iTunes同步及爱思助手等设备安装应用，建议使用【一键工厂激活iOS】功能。是否跳转到【一键工厂激活iOS】？(y/n)"
    read choice
    if [ "$choice" = "y" ]; then
        one_click_activate
        return
    fi

    ssh -p "$port" "$username"@"$host" "rm -rf $mount_dir/Applications/Setup.app"
    if [ $? -eq 0 ]; then
        ssh -p "$port" "$username"@"$host" "[! -d $mount_dir/Applications/Setup.app ]"
        if [ $? -eq 0 ]; then
            echo "成功绕过iCloud激活锁"
        else
            echo "绕过失败，可能是文件删除后又恢复，或者删除操作未成功"
        fi
    else
        echo "绕过失败，删除文件操作失败"
    fi
}

# 一键工厂激活iOS功能
one_click_activate() {
    server_info=$(get_server_config)
    IFS=' ' read -r host port username password <<< "$server_info"

    echo "该激活无法支持SIM卡及通话"
    read -p "按任意键继续..."

    echo "1. iOS5 - iOS6激活"
    echo "2. iOS7 - iOS9激活"
    echo "请选择激活版本"
    read choice

    echo "请输入SSHRamdisk挂载目录（通常为mnt1、mnt2等）"
    read mount_dir

    if [ "$choice" = "1" ]; then
        scp -P "$port" "$LOCKDOWN_FILE" "$username"@"$host":"$mount_dir"/usr/libexec/lockdownd
        if [ $? -eq 0 ]; then
            ssh -p "$port" "$username"@"$host" "chmod 0755 $mount_dir/usr/libexec/lockdownd"
            if [ $? -eq 0 ]; then
                echo "激活成功"
            else
                echo "激活失败，chmod操作失败"
            fi
        else
            echo "激活失败，scp操作失败"
        fi
    elif [ "$choice" = "2" ]; then
        mkdir -p "$TEMP_DIR"
        scp -P "$port" "$username"@"$host":"$mount_dir"/mobile/Library/Caches/com.apple.MobileGestalt.plist "$TEMP_DIR"/
        if [ $? -eq 0 ]; then
            # 使用PlistBuddy修改本地plist文件
            "$PLIST_BUDDY" -c "Add :a6vjPkzcRjrsXmniFsm0dg bool true" "$TEMP_DIR/com.apple.MobileGestalt.plist"
            scp -P "$port" "$TEMP_DIR/com.apple.MobileGestalt.plist" "$username"@"$host":"$mount_dir"/mobile/Library/Caches/com.apple.MobileGestalt.plist
            if [ $? -eq 0 ]; then
                echo "激活成功"
            else
                echo "激活失败，scp推送修改后的文件失败"
            fi
        else
            echo "激活失败，scp拉取文件失败"
        fi
    else
        echo "无效的选择"
    fi
}

# sftp文件管理器功能
sftp_file_manager() {
    server_info=$(get_server_config)
    IFS=' ' read -r host port username password <<< "$server_info"

    sftp -P "$port" "$username"@"$host" << EOF
ls
help
exit
EOF
}

# 主函数，提供操作菜单
main() {
    while true; do
        clear
        echo "32位iPhone SSHRamdisk操作工具"
        echo "1. 连接设备"
        echo "2. 一键绕过iCloud激活锁"
        echo "3. 一键工厂激活iOS"
        echo "4. sftp文件管理器"
        echo "5. 退出"
        read -p "请选择操作: " choice

        case $choice in
            1) connect_device ;;
            2) one_click_bypass_icloud ;;
            3) one_click_activate ;;
            4) sftp_file_manager ;;
            5) break ;;
            *) echo "无效的选择，请重新输入" ;;
        esac
        read -p "按任意键继续..."
    done
}

main