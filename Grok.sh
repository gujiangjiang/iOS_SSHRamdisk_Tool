#!/bin/bash

# 检查并下载 jq 依赖
check_and_install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "jq not found, downloading..."
        arch=$(uname -m)
        if [ "$arch" = "arm64" ]; then
            curl -L -o jq https://github.com/stedolan/jq/releases/download/jq-1.7/jq-osx-arm64
        else
            curl -L -o jq https://github.com/stedolan/jq/releases/download/jq-1.7/jq-osx-amd64
        fi
        chmod +x jq
        export PATH=$PATH:$(pwd)
    fi
}

# 检查 expect 是否存在
check_expect() {
    if ! command -v expect &> /dev/null; then
        echo "expect not found. Please install expect to use sftp feature."
        return 1
    fi
    return 0
}

# 初始化 config.json（如果不存在）
init_config() {
    if [ ! -f config.json ]; then
        echo "[]" > config.json
    fi
}

# 加载所有配置的别名
list_aliases() {
    jq -r '.[].alias' config.json
}

# 根据别名加载配置
load_config_by_alias() {
    local selected_alias="$1"
    alias=$(jq -r ".[] | select(.alias == \"$selected_alias\") | .alias" config.json)
    server_address=$(jq -r ".[] | select(.alias == \"$selected_alias\") | .server_address" config.json)
    username=$(jq -r ".[] | select(.alias == \"$selected_alias\") | .username" config.json)
    password=$(jq -r ".[] | select(.alias == \"$selected_alias\") | .password" config.json)
    port=$(jq -r ".[] | select(.alias == \"$selected_alias\") | .port" config.json)
    mount_point=$(jq -r ".[] | select(.alias == \"$selected_alias\") | .mount_point" config.json)
}

# 保存新配置
save_config() {
    local temp_config=$(mktemp)
    jq ". += [{\"alias\": \"$alias\", \"server_address\": \"$server_address\", \"username\": \"$username\", \"password\": \"$password\", \"port\": \"$port\", \"mount_point\": \"$mount_point\"}]" config.json > "$temp_config"
    mv "$temp_config" config.json
}

# 测试 SSH 连接
test_ssh_connection() {
    ssh -o StrictHostKeyChecking=no -p "$port" "$username@$server_address" "exit" &> /dev/null
    return $?
}

# 连接设备功能
connect_device() {
    echo "=== Connect Device ==="
    init_config
    local aliases=$(list_aliases)
    if [ -n "$aliases" ]; then
        echo "Available configurations:"
        echo "$aliases"
        read -p "Enter alias to load (or type 'new' to create a new config): " selected_alias
        if [ "$selected_alias" != "new" ]; then
            load_config_by_alias "$selected_alias"
            if [ -n "$alias" ]; then
                echo "Loaded config for $alias ($server_address)."
                return
            else
                echo "Error: Alias not found. Creating new config..."
            fi
        fi
    fi

    read -p "Enter alias: " alias
    read -p "Enter server address: " server_address
    read -p "Enter username: " username
    read -p "Enter password: " password
    read -p "Enter port (default 22): " port
    port=${port:-22}
    read -p "Enter mount point (e.g., /mnt1, /mnt2): " mount_point

    echo "Testing connection..."
    if test_ssh_connection; then
        echo "Connection successful. Saving config..."
        save_config
    else
        echo "Connection failed. Please check your inputs."
    fi
}

# iOS5-iOS6 激活
activate_ios5_6() {
    echo "=== iOS5-iOS6 Activation ==="
    if [ -z "$mount_point" ]; then
        read -p "Enter mount point (e.g., /mnt1, /mnt2): " mount_point
    fi
    echo "Using mount point: $mount_point"

    if [ ! -f lockdownd ]; then
        echo "Error: lockdownd file not found in current directory."
        return
    fi

    scp -P "$port" lockdownd "$username@$server_address:$mount_point/usr/libexec/lockdownd" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to upload lockdownd file."
        return
    fi

    ssh -p "$port" "$username@$server_address" "chmod 0755 $mount_point/usr/libexec/lockdownd" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set permissions for lockdownd."
        return
    fi

    echo "Activation successful."
}

# iOS7-iOS9 激活
activate_ios7_9() {
    echo "=== iOS7-iOS9 Activation ==="
    if [ -z "$mount_point" ]; then
        read -p "Enter mount point (e.g., /mnt1, /mnt2): " mount_point
    fi
    echo "Using mount point: $mount_point"

    mkdir -p temp
    scp -P "$port" "$username@$server_address:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" temp/ &> /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download com.apple.MobileGestalt.plist."
        return
    fi

    /usr/libexec/PlistBuddy -c "Add a6vjPkzcRjrsXmniFsm0dg bool true" temp/com.apple.MobileGestalt.plist &> /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to modify com.apple.MobileGestalt.plist."
        return
    fi

    scp -P "$port" temp/com.apple.MobileGestalt.plist "$username@$server_address:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to upload modified com.apple.MobileGestalt.plist."
        return
    fi

    echo "Activation successful."
}

# sftp 文件管理
sftp_manager() {
    echo "=== SFTP File Manager ==="
    if ! check_expect; then
        return
    fi

    if [ -z "$server_address" ] || [ -z "$username" ] || [ -z "$password" ] || [ -z "$port" ]; then
        echo "Error: No server config found. Please connect device first."
        return
    fi

    cat <<EOF > sftp_expect.sh
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
    chmod +x sftp_expect.sh

    ./sftp_expect.sh "$username" "$server_address" "$port" "$password"
    rm -f sftp_expect.sh
}

# 主菜单
main_menu() {
    check_and_install_jq
    init_config

    while true; do
        clear
        echo "=== 32-bit iPhone SSH Ramdisk Tool ==="
        echo "1. Connect Device"
        echo "2. One-Click iOS Activation"
        echo "3. SFTP File Manager"
        echo "4. Exit"
        read -p "Select an option: " choice

        case $choice in
            1)
                connect_device
                ;;
            2)
                echo "This activation does not support SIM card or phone calls."
                read -p "Understand? (y/n): " understand
                if [ "$understand" = "y" ]; then
                    echo "1. iOS5-iOS6 Activation"
                    echo "2. iOS7-iOS9 Activation"
                    read -p "Select activation type: " act_choice
                    case $act_choice in
                        1) activate_ios5_6 ;;
                        2) activate_ios7_9 ;;
                        *) echo "Invalid choice." ;;
                    esac
                fi
                ;;
            3)
                sftp_manager
                ;;
            4)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid choice."
                ;;
        esac
        read -p "Press Enter to continue..."
    done
}

main_menu