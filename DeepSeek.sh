#!/bin/bash

# 定义程序目录
PROGRAM_DIR=$(dirname "$0")
DATA_DIR="$PROGRAM_DIR/data"
DEPENDENCIES_DIR="$DATA_DIR/dependencies"
JSON_PARSER="$DEPENDENCIES_DIR/jq"
CONFIG_FILE="$DATA_DIR/config.json"
TEMP_DIR="$DATA_DIR/temp"
LOCKDOWND_FILE="$DATA_DIR/lockdownd"

# 创建数据目录、依赖目录和临时目录
mkdir -p "$DATA_DIR"
mkdir -p "$DEPENDENCIES_DIR"
mkdir -p "$TEMP_DIR"

# 下载jq
download_jq() {
    if ! command -v "$JSON_PARSER" &> /dev/null; then
        echo "下载jq..."
        curl -L "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64" -o "$JSON_PARSER"
        chmod +x "$JSON_PARSER"
    fi
}

# 检查并下载依赖
download_jq

# 主菜单
main_menu() {
    while true; do
        echo "=============================="
        echo " 32位iPhone SSHRamdisk操作工具 "
        echo "=============================="
        echo "1. 连接设备"
        echo "2. 一键工厂激活iOS"
        echo "3. sftp文件管理器"
        echo "4. 退出"
        read -p "请选择操作: " choice

        case $choice in
            1) connect_device ;;
            2) activate_ios ;;
            3) sftp_manager ;;
            4) exit 0 ;;
            *) echo "无效选择，请重新输入。" ;;
        esac
    done
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

    new_config
}

# 加载配置
load_config() {
    echo "加载配置..."
    SERVER_ALIAS=$($JSON_PARSER -r '.alias' "$CONFIG_FILE")
    SERVER_ADDRESS=$($JSON_PARSER -r '.address' "$CONFIG_FILE")
    USERNAME=$($JSON_PARSER -r '.username' "$CONFIG_FILE")
    PASSWORD=$($JSON_PARSER -r '.password' "$CONFIG_FILE")
    PORT=$($JSON_PARSER -r '.port' "$CONFIG_FILE")
    echo "配置加载完成: $SERVER_ALIAS"
}

# 新建配置
new_config() {
    echo "新建服务器配置..."
    read -p "服务器别名: " SERVER_ALIAS
    read -p "服务器地址: " SERVER_ADDRESS
    read -p "用户名: " USERNAME
    read -p "密码: " PASSWORD
    read -p "端口号: " PORT

    echo "测试连接..."
    if ssh -p "$PORT" "$USERNAME@$SERVER_ADDRESS" echo "连接成功"; then
        echo "服务器测试成功，配置已保存。"
        save_config
    else
        echo "连接失败，请检查配置。"
    fi
}

# 保存配置
save_config() {
    echo "保存配置..."
    CONFIG=$(jq -n \
        --arg alias "$SERVER_ALIAS" \
        --arg address "$SERVER_ADDRESS" \
        --arg username "$USERNAME" \
        --arg password "$PASSWORD" \
        --arg port "$PORT" \
        '{alias: $alias, address: $address, username: $username, password: $password, port: $port}')
    echo "$CONFIG" > "$CONFIG_FILE"
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

# iOS5-iOS6激活
activate_ios5_6() {
    if [[ ! -f "$LOCKDOWND_FILE" ]]; then
        echo "错误：未找到lockdownd文件，请将其放置于$DATA_DIR目录中。"
        return
    fi

    read -p "请输入SSHRamdisk挂载目录 (如mnt1, mnt2等): " MOUNT_DIR
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
    read -p "请输入SSHRamdisk挂载目录 (如mnt1, mnt2等): " MOUNT_DIR
    echo "开始iOS7-iOS9激活..."
    scp -P "$PORT" "$USERNAME@$SERVER_ADDRESS:/$MOUNT_DIR/mobile/Library/Caches/com.apple.MobileGestalt.plist" "$TEMP_DIR/"
    $JSON_PARSER -s '{"a6vjPkzcRjrsXmniFsm0dg": true}' "$TEMP_DIR/com.apple.MobileGestalt.plist" > "$TEMP_DIR/com.apple.MobileGestalt_modified.plist"
    scp -P "$PORT" "$TEMP_DIR/com.apple.MobileGestalt_modified.plist" "$USERNAME@$SERVER_ADDRESS:/$MOUNT_DIR/mobile/Library/Caches/com.apple.MobileGestalt.plist"
    if [[ $? -eq 0 ]]; then
        echo "激活成功"
    else
        echo "激活失败，请检查配置和连接。"
    fi
}

# SFTP文件管理器
sftp_manager() {
    echo "SFTP文件管理器"
    sftp -P "$PORT" "$USERNAME@$SERVER_ADDRESS"
}

# 运行主菜单
main_menu