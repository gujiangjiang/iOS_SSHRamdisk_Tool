#!/bin/bash

set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$BASE_DIR/data/config.json"
DEPENDENCIES_DIR="$BASE_DIR/data/dependencies"
LOCKDOWND_FILE="$BASE_DIR/data/lockdownd"
TEMP_DIR="$BASE_DIR/data/temp"

# 根据架构选择 jq 版本
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    JQ_URL="https://github.com/stedolan/jq/releases/latest/download/jq-macos-amd64"
    JQ_BIN="$DEPENDENCIES_DIR/jq-amd64"
elif [[ "$ARCH" == "arm64" ]]; then
    JQ_URL="https://github.com/stedolan/jq/releases/latest/download/jq-macos-arm64"
    JQ_BIN="$DEPENDENCIES_DIR/jq-arm64"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

# 创建目录结构
mkdir -p "$DEPENDENCIES_DIR"
mkdir -p "$BASE_DIR/data"

# 自动下载依赖
install_dependencies() {
    if [[ ! -f "$JQ_BIN" ]]; then
        echo "缺少依赖 jq，正在下载适用于 $ARCH 的版本..."
        curl -Lo "$JQ_BIN" "$JQ_URL"
        chmod +x "$JQ_BIN"
        echo "jq 已下载并存放在 $JQ_BIN"
    fi
}

# 选择服务器配置
select_server_config() {
    if [[ ! -f "$CONFIG_FILE" || $("$JQ_BIN" length "$CONFIG_FILE") -eq 0 ]]; then
        echo "当前无已保存的服务器配置。"
        return 1
    fi

    echo "请选择要加载的服务器别名："
    "$JQ_BIN" -r '.[].alias' "$CONFIG_FILE" | nl
    read -r choice

    selected_alias=$("$JQ_BIN" -r --argjson idx "$choice" '.[$idx - 1].alias' "$CONFIG_FILE")
    selected_config=$("$JQ_BIN" -r --argjson idx "$choice" '.[$idx - 1]' "$CONFIG_FILE")

    if [[ -z "$selected_alias" ]]; then
        echo "选择无效，请重试。"
        return 1
    fi

    echo "已选择服务器：$selected_alias"
    user=$("$JQ_BIN" -r '.user' <<< "$selected_config")
    server=$("$JQ_BIN" -r '.server' <<< "$selected_config")
    password=$("$JQ_BIN" -r '.password' <<< "$selected_config")
    port=$("$JQ_BIN" -r '.port' <<< "$selected_config")

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

        if [[ -f "$CONFIG_FILE" ]]; then
            config_data=$("$JQ_BIN" ". + [{\"alias\": \"$alias\", \"server\": \"$server\", \"user\": \"$user\", \"password\": \"$password\", \"port\": \"$port\"}]" "$CONFIG_FILE")
        else
            config_data="[ {\"alias\": \"$alias\", \"server\": \"$server\", \"user\": \"$user\", \"password\": \"$password\", \"port\": \"$port\"} ]"
        fi

        echo "$config_data" > "$CONFIG_FILE"
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

    "$JQ_BIN" --arg key "a6vjPkzcRjrsXmniFsm0dg" --argjson value true '.[$key] = $value' "$TEMP_DIR/com.apple.MobileGestalt.plist" > "$TEMP_DIR/com.apple.MobileGestalt_modified.plist"

    scp -P "$port" "$TEMP_DIR/com.apple.MobileGestalt_modified.plist" "$user@$server:/$mnt/mobile/Library/Caches/com.apple.MobileGestalt.plist"

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
    install_dependencies

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
