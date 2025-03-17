#!/bin/bash

# 检查并下载 jq 依赖
check_and_install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "未找到 jq，正在下载..."
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
        echo "未找到 expect。请安装 expect 以使用 sftp 功能。"
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

# 列出所有配置的别名
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
    echo "=== 连接设备 ==="
    init_config
    local aliases=$(list_aliases)
    if [ -n "$aliases" ]; then
        echo "可用配置："
        echo "$aliases"
        read -p "请输入要加载的别名（或输入 'new' 新建配置）： " selected_alias
        if [ "$selected_alias" != "new" ]; then
            load_config_by_alias "$selected_alias"
            if [ -n "$alias" ]; then
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
        echo "连接失败。请检查输入信息。"
    fi
}

# iOS5-iOS6 激活
activate_ios5_6() {
    echo "=== iOS5-iOS6 激活 ==="
    if [ -z "$mount_point" ]; then
        read -p "请输入挂载点（例如 /mnt1, /mnt2）： " mount_point
    fi
    echo "使用挂载点：$mount_point"

    if [ ! -f lockdownd ]; then
        echo "错误：当前目录未找到 lockdownd 文件。"
        return
    fi

    scp -P "$port" lockdownd "$username@$server_address:$mount_point/usr/libexec/lockdownd" &> /dev/null
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

    mkdir -p temp
    scp -P "$port" "$username@$server_address:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" temp/ &> /dev/null
    if [ $? -ne 0 ]; then
        echo "错误：下载 com.apple.MobileGestalt.plist 文件失败。"
        return
    fi

    /usr/libexec/PlistBuddy -c "Add a6vjPkzcRjrsXmniFsm0dg bool true" temp/com.apple.MobileGestalt.plist &> /dev/null
    if [ $? -ne 0 ]; then
        echo "错误：修改 com.apple.MobileGestalt.plist 文件失败。"
        return
    fi

    scp -P "$port" temp/com.apple.MobileGestalt.plist "$username@$server_address:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "错误：上传修改后的 com.apple.MobileGestalt.plist 文件失败。"
        return
    fi

    echo "激活成功。"
}

# sftp 文件管理
sftp_manager() {
    echo "=== SFTP 文件管理 ==="
    if ! check_expect; then
        return
    fi

    if [ -z "$server_address" ] || [ -z "$username" ] || [ -z "$password" ] || [ -z "$port" ]; then
        echo "错误：未找到服务器配置。请先连接设备。"
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