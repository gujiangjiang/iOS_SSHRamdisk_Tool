#!/bin/bash

# 定义目录变量
DATA_DIR="data"
TEMP_DIR="${DATA_DIR}/temp"

# 定义 PlistBuddy 路径
PLISTBUDDY="/usr/libexec/PlistBuddy"

# 创建必要的目录结构
setup_directories() {
    mkdir -p "${TEMP_DIR}"
}

# 检查 expect 是否存在
check_expect() {
    if ! command -v expect &> /dev/null; then
        echo "未找到 expect。自动登录功能不可用，但您可以手动输入密码使用 sftp。"
        return 1
    fi
    return 0
}

# 初始化 config.plist（如果不存在）
init_config() {
    if [ ! -f "${DATA_DIR}/config.plist" ]; then
        # 创建空的 plist 文件，包含 configurations 数组
        echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>configurations</key>
    <array/>
</dict>
</plist>' > "${DATA_DIR}/config.plist"
    fi
}

# 列出所有配置的别名
list_aliases() {
    local config_count=$(${PLISTBUDDY} -c "Print configurations:" "${DATA_DIR}/config.plist" | grep -c "Dict {")
    if [ "$config_count" -eq 0 ]; then
        return
    fi
    for ((i=0; i<config_count; i++)); do
        ${PLISTBUDDY} -c "Print configurations:$i:alias" "${DATA_DIR}/config.plist" 2>/dev/null
    done
}

# 根据别名加载配置
load_config_by_alias() {
    local selected_alias="$1"
    local config_count=$(${PLISTBUDDY} -c "Print configurations:" "${DATA_DIR}/config.plist" | grep -c "Dict {")
    if [ "$config_count" -eq 0 ]; then
        return 1
    fi
    for ((i=0; i<config_count; i++)); do
        local alias_value=$(${PLISTBUDDY} -c "Print configurations:$i:alias" "${DATA_DIR}/config.plist" 2>/dev/null)
        if [ "$alias_value" = "$selected_alias" ]; then
            alias=$(${PLISTBUDDY} -c "Print configurations:$i:alias" "${DATA_DIR}/config.plist")
            server_address=$(${PLISTBUDDY} -c "Print configurations:$i:server_address" "${DATA_DIR}/config.plist")
            username=$(${PLISTBUDDY} -c "Print configurations:$i:username" "${DATA_DIR}/config.plist")
            password=$(${PLISTBUDDY} -c "Print configurations:$i:password" "${DATA_DIR}/config.plist")
            port=$(${PLISTBUDDY} -c "Print configurations:$i:port" "${DATA_DIR}/config.plist")
            mount_point=$(${PLISTBUDDY} -c "Print configurations:$i:mount_point" "${DATA_DIR}/config.plist")
            return 0
        fi
    done
    return 1
}

# 保存新配置
save_config() {
    local config_count=$(${PLISTBUDDY} -c "Print configurations:" "${DATA_DIR}/config.plist" | grep -c "Dict {")
    ${PLISTBUDDY} -c "Add configurations:$config_count dict" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:alias string \"$alias\"" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:server_address string \"$server_address\"" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:username string \"$username\"" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:password string \"$password\"" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:port string \"$port\"" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:mount_point string \"$mount_point\"" "${DATA_DIR}/config.plist"
}

# 测试 SSH 连接
test_ssh_connection() {
    ssh -o StrictHostKeyChecking=no -p "$port" "$username@$server_address" "exit" &> /dev/null
    return $?
}

# 连接设备功能
connect_device() {
    echo "=== 连接设备 ==="
    init_config
    local aliases=$(list_aliases)
    if [ -n "$aliases" ]; then
        echo "可用配置："
        echo "$aliases"
        read -p "请输入要加载的别名（或输入 'new' 新建配置）： " selected_alias
        if [ "$selected_alias" != "new" ]; then
            load_config_by_alias "$selected_alias"
            if [ $? -eq 0 ]; then
                echo "已加载配置：$alias ($server_address)。"
                return
            else
                echo "错误：未找到该别名。创建新配置..."
            fi
        fi
    fi

    read -p "请输入别名： " alias
    read -p "请输入服务器地址： " server_address
    read -p "请输入用户名： " username
    read -p "请输入密码： " password
    read -p "请输入端口号（默认 22）： " port
    port=${port:-22}
    read -p "请输入挂载点（例如 /mnt1, /mnt2）： " mount_point

    echo "正在测试连接..."
    if test_ssh_connection; then
        echo "连接成功。正在保存配置..."
        save_config
    else
        echo "连接失败，请检查输入信息。配置未保存。"
        return 1
    fi
}

# iOS5-iOS6 激活
activate_ios5_6() {
    echo "=== iOS5-iOS6 激活 ==="
    if [ -z "$mount_point" ]; then
        read -p "请输入挂载点（例如 /mnt1, /mnt2）： " mount_point
    fi
    echo "使用挂载点：$mount_point"

    if [ ! -f "${DATA_DIR}/lockdownd" ]; then
        echo "错误：${DATA_DIR} 目录下未找到 lockdownd 文件。请将 lockdownd 文件放置到 ${DATA_DIR}/ 目录。"
        return
    fi

    scp -P "$port" "${DATA_DIR}/lockdownd" "$username@$server_address:$mount_point/usr/libexec/lockdownd" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "错误：上传 lockdownd 文件失败。"
        return
    fi

    ssh -p "$port" "$username@$server_address" "chmod 0755 $mount_point/usr/libexec/lockdownd" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "错误：设置 lockdownd 文件权限失败。"
        return
    fi

    echo "激活成功。"
}

# iOS7-iOS9 激活
activate_ios7_9() {
    echo "=== iOS7-iOS9 激活 ==="
    if [ -z "$mount_point" ]; then
        read -p "请输入挂载点（例如 /mnt1, /mnt2）： " mount_point
    fi
    echo "使用挂载点：$mount_point"

    scp -P "$port" "$username@$server_address:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" "${TEMP_DIR}/" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "错误：下载 com.apple.MobileGestalt.plist 文件失败。"
        return
    fi

    ${PLISTBUDDY} -c "Add a6vjPkzcRjrsXmniFsm0dg bool true" "${TEMP_DIR}/com.apple.MobileGestalt.plist" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "错误：修改 com.apple.MobileGestalt.plist 文件失败。"
        return
    fi

    scp -P "$port" "${TEMP_DIR}/com.apple.MobileGestalt.plist" "$username@$server_address:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "错误：上传修改后的 com.apple.MobileGestalt.plist 文件失败。"
        return
    fi

    echo "激活成功。"
    # 激活成功后清理临时文件夹
    rm -rf "${TEMP_DIR}"/*
}

# sftp 文件管理
sftp_manager() {
    echo "=== SFTP 文件管理 ==="
    if [ -z "$server_address" ] || [ -z "$username" ] || [ -z "$port" ]; then
        echo "错误：未找到服务器配置。请先连接设备。"
        return
    fi

    if check_expect; then
        # 使用 expect 自动登录
        if [ -z "$password" ]; then
            echo "错误：未找到密码，无法使用自动登录。请手动输入密码。"
            sftp -P "$port" "$username@$server_address"
        else
            cat <<EOF > "${TEMP_DIR}/sftp_expect.sh"
#!/usr/bin/expect -f
set username [lindex \$argv 0]
set server [lindex \$argv 1]
set port [lindex \$argv 2]
set password [lindex \$argv 3]
spawn sftp -P \$port \$username@\$server
expect "password:"
send "\$password\r"
interact
EOF
            chmod +x "${TEMP_DIR}/sftp_expect.sh"
            "${TEMP_DIR}/sftp_expect.sh" "$username" "$server_address" "$port" "$password"
            rm -f "${TEMP_DIR}/sftp_expect.sh"
        fi
    else
        # 缺少 expect，提示手动输入密码
        echo "提示：您可以手动输入密码继续使用 sftp。"
        sftp -P "$port" "$username@$server_address"
    fi
}

# 主菜单
main_menu() {
    setup_directories
    init_config

    while true; do
        clear
        echo "=== 32位 iPhone SSH Ramdisk 操作工具 ==="
        echo "1. 连接设备"
        echo "2. 一键激活 iOS"
        echo "3. SFTP 文件管理"
        echo "4. 退出"
        read -p "请选择选项： " choice

        case $choice in
            1)
                connect_device
                ;;
            2)
                echo "此激活功能不支持 SIM 卡或电话功能。"
                read -p "是否了解？（y/n）： " understand
                if [ "$understand" = "y" ]; then
                    echo "1. iOS5-iOS6 激活"
                    echo "2. iOS7-iOS9 激活"
                    read -p "请选择激活类型： " act_choice
                    case $act_choice in
                        1) activate_ios5_6 ;;
                        2) activate_ios7_9 ;;
                        *) echo "无效选项。" ;;
                    esac
                fi
                ;;
            3)
                sftp_manager
                ;;
            4)
                echo "正在退出..."
                exit 0
                ;;
            *)
                echo "无效选项。"
                ;;
        esac
        read -p "按回车键继续..."
    done
}

main_menu