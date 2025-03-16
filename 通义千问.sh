#!/bin/bash

# 程序目录
SCRIPT_DIR=$(dirname "$(realpath "$0")")
DATA_DIR="$SCRIPT_DIR/data"
DEPENDENCIES_DIR="$DATA_DIR/dependencies"
CONFIG_FILE="$DATA_DIR/config.json"
LOCKDOWND_FILE="$DATA_DIR/lockdownd"
TEMP_DIR="$DATA_DIR/temp"

# 创建必要的目录
mkdir -p "$DATA_DIR" "$DEPENDENCIES_DIR" "$TEMP_DIR"

# 自动下载依赖
download_dependency() {
    local name=$1
    local url=$2
    local path="$DEPENDENCIES_DIR/$name"

    if [ ! -f "$path" ]; then
        echo "Downloading $name..."
        curl -o "$path" -L "$url"
        chmod +x "$path"
    fi
}

# 下载jq
download_dependency jq "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"

# 主菜单
main_menu() {
    while true; do
        clear
        echo "32位iPhone SSHRamdisk操作工具"
        echo "1. 连接设备"
        echo "2. 一键工厂激活iOS"
        echo "3. sftp文件管理器"
        echo "0. 退出"
        read -p "请选择: " choice

        case $choice in
            1) connect_device ;;
            2) activate_ios ;;
            3) sftp_manager ;;
            0) exit 0 ;;
            *) echo "无效的选择，请重新选择。" ;;
        esac
    done
}

# 保存配置
save_config() {
    local alias=$1
    local username=$2
    local password=$3
    local port=$4
    local mount_point=$5

    if [ -f "$CONFIG_FILE" ]; then
        config=$(cat "$CONFIG_FILE")
        new_config=$(echo "$config" | jq --arg alias "$alias" --arg username "$username" --arg password "$password" --arg port "$port" --arg mount_point "$mount_point" '. + {($alias): {"username": $username, "password": $password, "port": $port, "mount_point": $mount_point}}')
    else
        new_config=$(jq -n --arg alias "$alias" --arg username "$username" --arg password "$password" --arg port "$port" --arg mount_point "$mount_point" '{"$alias": {"username": $username, "password": $password, "port": $port, "mount_point": $mount_point}}')
    fi

    echo "$new_config" > "$CONFIG_FILE"
}

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        echo "{}"
    fi
}

# 测试SSH连接
test_ssh_connection() {
    local username=$1
    local password=$2
    local host=$3
    local port=$4

    sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$username@$host" "echo 'Connection successful'"
}

# 连接设备
connect_device() {
    config=$(load_config)
    aliases=$(echo "$config" | jq -r 'keys[]')

    if [ -n "$aliases" ]; then
        echo "存在已保存的数据，是否一键引用？(y/n)"
        read -p "选择: " use_saved

        if [ "$use_saved" == "y" ]; then
            select_alias
            return
        fi
    fi

    read -p "服务器别名: " alias
    read -p "用户名: " username
    read -p "密码: " password
    read -p "端口号: " port
    read -p "挂载点 (例如 mnt1): " mount_point

    if test_ssh_connection "$username" "$password" "localhost" "$port"; then
        save_config "$alias" "$username" "$password" "$port" "$mount_point"
        echo "服务器测试成功，配置已保存。"
        sleep 2
        main_menu
    else
        echo "连接失败，请检查配置。"
        sleep 2
        connect_device
    fi
}

# 选择别名
select_alias() {
    config=$(load_config)
    aliases=$(echo "$config" | jq -r 'keys[]')

    PS3="请选择别名: "
    select alias in $aliases; do
        if [ -n "$alias" ]; then
            username=$(echo "$config" | jq -r ".\"$alias\".username")
            password=$(echo "$config" | jq -r ".\"$alias\".password")
            port=$(echo "$config" | jq -r ".\"$alias\".port")
            mount_point=$(echo "$config" | jq -r ".\"$alias\".mount_point")

            if test_ssh_connection "$username" "$password" "localhost" "$port"; then
                echo "服务器测试成功，配置已加载。"
                sleep 2
                main_menu
            else
                echo "连接失败，请检查配置。"
                sleep 2
                connect_device
            fi
        else
            echo "无效的选择，请重新选择。"
            sleep 2
            select_alias
        fi
    done
}

# 一键工厂激活iOS
activate_ios() {
    echo "该激活无法支持SIM卡及通话。"
    read -p "了解并继续 (y/n): " confirm

    if [ "$confirm" != "y" ]; then
        return
    fi

    echo "1. iOS5-iOS6激活"
    echo "2. iOS7-iOS9激活"
    read -p "请选择: " choice

    case $choice in
        1) activate_ios5_6 ;;
        2) activate_ios7_9 ;;
        *) echo "无效的选择，请重新选择。" ;;
    esac
}

# 激活iOS5-iOS6
activate_ios5_6() {
    read -p "请输入挂载点 (例如 mnt1): " mount_point

    if scp -P "$port" "$LOCKDOWND_FILE" "$username@localhost:$mount_point/usr/libexec/lockdownd" && \
       ssh -p "$port" "$username@localhost" "chmod 0755 $mount_point/usr/libexec/lockdownd"; then
        echo "激活成功"
    else
        echo "激活失败，请检查错误信息。"
    fi
}

# 激活iOS7-iOS9
activate_ios7_9() {
    read -p "请输入挂载点 (例如 mnt1): " mount_point

    if scp -P "$port" "$username@localhost:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" "$TEMP_DIR/"; then
        /usr/libexec/PlistBuddy -c "Add :a6vjPkzcRjrsXmniFsm0dg bool true" "$TEMP_DIR/com.apple.MobileGestalt.plist"
        if scp -P "$port" "$TEMP_DIR/com.apple.MobileGestalt.plist" "$username@localhost:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist"; then
            echo "激活成功"
        else
            echo "激活失败，请检查错误信息。"
        fi
    else
        echo "激活失败，请检查错误信息。"
    fi
}

# sftp文件管理器
sftp_manager() {
    read -p "请输入用户名: " username
    read -p "请输入密码: " password
    read -p "请输入主机地址: " host
    read -p "请输入端口号: " port

    sshpass -p "$password" sftp -oPort="$port" "$username@$host"
}

# 启动主菜单
main_menu
