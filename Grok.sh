#!/bin/bash

# 全局变量定义
DATA_DIR="data"
TEMP_DIR="${DATA_DIR}/temp"
PLISTBUDDY="/usr/libexec/PlistBuddy"

# 辅助函数
setup_directories() {
    mkdir -p "${TEMP_DIR}"
}

check_expect() {
    command -v expect &>/dev/null || {
        echo "未找到 expect。自动登录功能不可用，可手动输入密码使用 sftp。"
        return 1
    }
    return 0
}

check_ssh_config() {
    [ -z "$server_address" ] || [ -z "$username" ] || [ -z "$port" ] && {
        echo "错误：未找到服务器配置。请先连接设备。"
        return 1
    }
    return 0
}

ensure_mount_point() {
    [ -z "$mount_point" ] && read -p "请输入挂载点（例如 /mnt1, /mnt2）： " mount_point
    echo "使用挂载点：$mount_point"
}

init_config() {
    [ -f "${DATA_DIR}/config.plist" ] || echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>configurations</key>
    <array/>
</dict>
</plist>' > "${DATA_DIR}/config.plist"
}

list_aliases() {
    ${PLISTBUDDY} -c "Print configurations:" "${DATA_DIR}/config.plist" 2>/dev/null | awk '/Dict {/{flag=1;next}/}/{flag=0}flag&&/alias/{print $3}'
}

load_config_by_alias() {
    local selected_alias="$1"
    local config_data=$(${PLISTBUDDY} -c "Print configurations:" "${DATA_DIR}/config.plist" 2>/dev/null)
    [ -z "$config_data" ] && return 1

    local matched_config=$(echo "$config_data" | awk -v alias="$selected_alias" '
        /Dict {/{flag=1; config=""}
        flag{config=config $0 "\n"}
        /alias =/&&$3==alias{print config; exit}
        /}/{flag=0}
    ')
    [ -z "$matched_config" ] && return 1

    alias=$(echo "$matched_config" | awk '/alias =/{print $3}')
    server_address=$(echo "$matched_config" | awk '/server_address =/{print $3}')
    username=$(echo "$matched_config" | awk '/username =/{print $3}')
    password=$(echo "$matched_config" | awk '/password =/{print $3}')
    port=$(echo "$matched_config" | awk '/port =/{print $3}')
    mount_point=$(echo "$matched_config" | awk '/mount_point =/{print $3}')
    return 0
}

save_config() {
    local config_count=$(${PLISTBUDDY} -c "Print configurations:" "${DATA_DIR}/config.plist" 2>/dev/null | grep -c "Dict {")
    ${PLISTBUDDY} -c "Add configurations:$config_count dict" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:alias string \"$alias\"" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:server_address string \"$server_address\"" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:username string \"$username\"" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:password string \"$password\"" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:port string \"$port\"" "${DATA_DIR}/config.plist"
    ${PLISTBUDDY} -c "Add configurations:$config_count:mount_point string \"$mount_point\"" "${DATA_DIR}/config.plist"
}

# SSH 操作函数
execute_ssh_command() {
    local command="$1"
    ssh -o StrictHostKeyChecking=no -p "$port" "$username@$server_address" "$command" &>/dev/null
    return $?
}

test_ssh_connection() {
    execute_ssh_command "exit"
    return $?
}

# 核心功能函数
connect_device() {
    echo "=== 连接设备 ==="
    init_config
    local aliases=$(list_aliases)
    if [ -n "$aliases" ]; then
        echo "可用配置："
        echo "$aliases"
        read -p "请输入要加载的别名（或输入 'new' 新建配置）： " selected_alias
        if [ "$selected_alias" != "new" ]; then
            load_config_by_alias "$selected_alias" && {
                echo "已加载配置：$alias ($server_address)。"
                return
            }
            echo "错误：未找到该别名。创建新配置..."
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
    test_ssh_connection && {
        echo "连接成功。正在保存配置..."
        save_config
    } || {
        echo "连接失败，请检查输入信息。配置未保存。"
        return 1
    }
}

bypass_icloud_activation() {
    echo "=== 一键绕过iCloud激活锁 ==="
    check_ssh_config || return
    ensure_mount_point

    echo "注意：一键绕过iCloud激活锁功能只能绕过激活锁，设备仍处于未激活状态，无法使用iTunes或爱思助手安装应用。"
    read -p "建议使用【一键工厂激活iOS】功能，是否跳转？（y/n）： " choice
    [ "$choice" = "y" ] && { activate_ios_menu; return; }

    echo "正在绕过 iCloud 激活锁..."
    execute_ssh_command "rm -f ${mount_point}/Applications/Setup.app && [ ! -f ${mount_point}/Applications/Setup.app ]" && {
        echo "成功绕过iCloud激活锁。"
    } || {
        echo "绕过iCloud激活锁失败，可能是权限不足或文件未删除成功。"
    }
}

activate_ios5_6() {
    echo "=== iOS5-iOS6 激活 ==="
    check_ssh_config || return
    ensure_mount_point

    [ ! -f "${DATA_DIR}/lockdownd" ] && {
        echo "错误：${DATA_DIR} 目录下未找到 lockdownd 文件。请将 lockdownd 文件放置到 ${DATA_DIR}/。"
        return
    }

    scp -P "$port" "${DATA_DIR}/lockdownd" "$username@$server_address:$mount_point/usr/libexec/lockdownd" &>/dev/null || {
        echo "错误：上传 lockdownd 文件失败。"
        return
    }

    execute_ssh_command "chmod 0755 $mount_point/usr/libexec/lockdownd" || {
        echo "错误：设置 lockdownd 文件权限失败。"
        return
    }

    echo "激活成功。"
}

activate_ios7_9() {
    echo "=== iOS7-iOS9 激活 ==="
    check_ssh_config || return
    ensure_mount_point

    scp -P "$port" "$username@$server_address:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" "${TEMP_DIR}/" &>/dev/null || {
        echo "错误：下载 com.apple.MobileGestalt.plist 文件失败。"
        return
    }

    ${PLISTBUDDY} -c "Add a6vjPkzcRjrsXmniFsm0dg bool true" "${TEMP_DIR}/com.apple.MobileGestalt.plist" &>/dev/null || {
        echo "错误：修改 com.apple.MobileGestalt.plist 文件失败。"
        return
    }

    scp -P "$port" "${TEMP_DIR}/com.apple.MobileGestalt.plist" "$username@$server_address:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" &>/dev/null || {
        echo "错误：上传修改后的 com.apple.MobileGestalt.plist 文件失败。"
        return
    }

    echo "激活成功。"
    rm -rf "${TEMP_DIR}"/*
}

activate_ios_menu() {
    echo "此激活功能不支持 SIM 卡或电话功能。"
    read -p "是否了解？（y/n）： " understand
    [ "$understand" = "y" ] || return
    echo "1. iOS5-iOS6 激活"
    echo "2. iOS7-iOS9 激活"
    read -p "请选择激活类型： " act_choice
    case $act_choice in
        1) activate_ios5_6 ;;
        2) activate_ios7_9 ;;
        *) echo "无效选项。" ;;
    esac
}

sftp_manager() {
    echo "=== SFTP 文件管理 ==="
    check_ssh_config || return

    if check_expect && [ -n "$password" ]; then
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
    else
        [ -z "$password" ] && echo "错误：未找到密码，无法自动登录。请手动输入密码。"
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
        echo "2. 一键绕过iCloud激活锁"
        echo "3. 一键工厂激活iOS"
        echo "4. SFTP 文件管理"
        echo "5. 退出"
        read -p "请选择选项： " choice

        case $choice in
            1) connect_device ;;
            2) bypass_icloud_activation ;;
            3) activate_ios_menu ;;
            4) sftp_manager ;;
            5) echo "正在退出..."; exit 0 ;;
            *) echo "无效选项。" ;;
        esac
        read -p "按回车键继续..."
    done
}

main_menu