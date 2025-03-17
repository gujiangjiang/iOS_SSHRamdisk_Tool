#!/bin/bash

set -e

CONFIG_FILE="config.json"
DEPENDENCIES=("jq")

# 自动下载依赖
install_dependencies() {
    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v $dep &>/dev/null; then
            echo "缺少依赖：$dep，正在下载..."
            curl -LO "https://github.com/stedolan/jq/releases/latest/download/jq-macos"
            mv jq-macos jq
            chmod +x jq
            echo "jq 已下载并可执行。"
        fi
    done
}

# 显示已有服务器配置并选择
select_server_config() {
    if [[ ! -f "$CONFIG_FILE" || $(jq length "$CONFIG_FILE") -eq 0 ]]; then
        echo "当前无已保存的服务器配置。"
        return 1
    fi

    echo "请选择要加载的服务器别名："
    jq -r '.[].alias' "$CONFIG_FILE" | nl
    read -r choice

    selected_alias=$(jq -r --argjson idx "$choice" '.[$idx - 1].alias' "$CONFIG_FILE")
    selected_config=$(jq -r --argjson idx "$choice" '.[$idx - 1]' "$CONFIG_FILE")

    if [[ -z "$selected_alias" ]]; then
        echo "选择无效，请重试。"
        return 1
    fi

    echo "已选择服务器：$selected_alias"
    user=$(jq -r '.user' <<< "$selected_config")
    server=$(jq -r '.server' <<< "$selected_config")
    password=$(jq -r '.password' <<< "$selected_config")
    port=$(jq -r '.port' <<< "$selected_config")

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

        # 读取现有配置并添加新配置
        if [[ -f "$CONFIG_FILE" ]]; then
            config_data=$(jq ". + [{\"alias\": \"$alias\", \"server\": \"$server\", \"user\": \"$user\", \"password\": \"$password\", \"port\": \"$port\"}]" "$CONFIG_FILE")
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
    scp -P "$port" lockdownd "$user@$server:/$mnt/usr/libexec/lockdownd"
    ssh -p "$port" "$user@$server" "chmod 0755 /$mnt/usr/libexec/lockdownd"
    echo "iOS 5-6 激活完成。"
}

# iOS 7-9 激活
activate_ios7_9() {
    select_mnt
    mkdir -p temp
    scp -P "$port" "$user@$server:/$mnt/mobile/Library/Caches/com.apple.MobileGestalt.plist" temp/
    plutil -insert "a6vjPkzcRjrsXmniFsm0dg" -bool true temp/com.apple.MobileGestalt.plist
    scp -P "$port" temp/com.apple.MobileGestalt.plist "$user@$server:/$mnt/mobile/Library/Caches/"
    echo "iOS 7-9 激活完成。"
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
