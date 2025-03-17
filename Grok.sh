#!/bin/bash

# 全局变量
DATA_DIR="data"
TEMP_DIR="${DATA_DIR}/temp"
PLISTBUDDY="/usr/libexec/PlistBuddy"

# 初始化目录和配置
setup() {
    mkdir -p "$TEMP_DIR"
    [ -f "$DATA_DIR/config.plist" ] || echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>configurations</key><array/></dict></plist>' > "$DATA_DIR/config.plist"
}

# 检查 SSH 配置是否完整
check_ssh() {
    [ -z "$server_address" ] || [ -z "$username" ] || [ -z "$port" ] && {
        echo "错误：未找到服务器配置，请先连接设备。"
        return 1
    }
}

# 获取或输入挂载点
get_mount() {
    [ -z "$mount_point" ] && read -p "请输入挂载点（例如 /mnt1, /mnt2）： " mount_point
    echo "使用挂载点：$mount_point"
}

# 执行 SSH 命令
ssh_exec() {
    ssh -o StrictHostKeyChecking=no -p "$port" "$username@$server_address" "$1" &>/dev/null
    return $?
}

# 列出配置别名
list_configs() {
    $PLISTBUDDY -c "Print configurations:" "$DATA_DIR/config.plist" 2>/dev/null | awk '/Dict {/{f=1;next}/}/{f=0}f&&/alias/{print $3}'
}

# 加载指定配置
load_config() {
    local alias="$1" config=$($PLISTBUDDY -c "Print configurations:" "$DATA_DIR/config.plist" 2>/dev/null)
    [ -z "$config" ] && return 1
    local match=$(echo "$config" | awk -v a="$alias" '/Dict {/{f=1;c=""}f{c=c $0 "\n"}/alias =/&&$3==a{print c;exit}/{f=0}')
    [ -z "$match" ] && return 1
    alias=$(echo "$match" | awk '/alias =/{print $3}')
    server_address=$(echo "$match" | awk '/server_address =/{print $3}')
    username=$(echo "$match" | awk '/username =/{print $3}')
    password=$(echo "$match" | awk '/password =/{print $3}')
    port=$(echo "$match" | awk '/port =/{print $3}')
    mount_point=$(echo "$match" | awk '/mount_point =/{print $3}')
}

# 保存新配置
save_config() {
    local count=$($PLISTBUDDY -c "Print configurations:" "$DATA_DIR/config.plist" 2>/dev/null | grep -c "Dict {")
    $PLISTBUDDY -c "Add configurations:$count dict" "$DATA_DIR/config.plist"
    $PLISTBUDDY -c "Add configurations:$count:alias string \"$alias\"" "$DATA_DIR/config.plist"
    $PLISTBUDDY -c "Add configurations:$count:server_address string \"$server_address\"" "$DATA_DIR/config.plist"
    $PLISTBUDDY -c "Add configurations:$count:username string \"$username\"" "$DATA_DIR/config.plist"
    $PLISTBUDDY -c "Add configurations:$count:password string \"$password\"" "$DATA_DIR/config.plist"
    $PLISTBUDDY -c "Add configurations:$count:port string \"$port\"" "$DATA_DIR/config.plist"
    $PLISTBUDDY -c "Add configurations:$count:mount_point string \"$mount_point\"" "$DATA_DIR/config.plist"
}

# 连接设备
connect_device() {
    echo "=== 连接设备 ==="
    local aliases=$(list_configs)
    [ -n "$aliases" ] && {
        echo "可用配置："
        echo "$aliases"
        read -p "请输入要加载的别名（或输入 'new' 新建配置）： " alias
        [ "$alias" != "new" ] && load_config "$alias" && {
            echo "已加载配置：$alias ($server_address)。"
            return
        } || echo "错误：未找到该别名，创建新配置..."
    }

    # 获取用户输入
    read -p "请输入别名： " alias
    read -p "请输入服务器地址： " server_address
    read -p "请输入用户名： " username
    read -p "请输入密码： " password
    read -p "请输入端口号（默认 22）： " port; port=${port:-22}
    read -p "请输入挂载点（例如 /mnt1, /mnt2）： " mount_point

    # 测试并保存
    echo "正在测试连接..."
    ssh_exec "exit" && { echo "连接成功。正在保存配置..."; save_config; } || echo "连接失败，请检查输入信息。配置未保存。"
}

# 绕过 iCloud 激活锁
bypass_icloud() {
    echo "=== 一键绕过iCloud激活锁 ==="
    check_ssh || return
    get_mount

    echo "注意：此功能仅绕过激活锁，设备仍未激活，无法使用iTunes或爱思助手。"
    read -p "建议使用【一键工厂激活iOS】，是否跳转？（y/n）： " choice
    [ "$choice" = "y" ] && { activate_ios; return; }

    # 删除并验证 Setup.app
    echo "正在绕过 iCloud 激活锁..."
    ssh_exec "rm -f $mount_point/Applications/Setup.app && [ ! -f $mount_point/Applications/Setup.app ]" && echo "成功绕过iCloud激活锁。" || echo "绕过失败，可能是权限不足或文件未删除。"
}

# iOS5-iOS6 激活
activate_ios5_6() {
    echo "=== iOS5-iOS6 激活 ==="
    check_ssh || return
    get_mount

    # 检查 lockdownd 文件
    [ ! -f "$DATA_DIR/lockdownd" ] && { echo "错误：未找到 $DATA_DIR/lockdownd 文件，请手动放置。"; return; }

    # 上传并设置权限
    scp -P "$port" "$DATA_DIR/lockdownd" "$username@$server_address:$mount_point/usr/libexec/lockdownd" &>/dev/null || {
        echo "错误：上传 lockdownd 文件失败。"
        return
    }
    ssh_exec "chmod 0755 $mount_point/usr/libexec/lockdownd" && echo "激活成功。" || echo "错误：设置权限失败。"
}

# iOS7-iOS9 激活
activate_ios7_9() {
    echo "=== iOS7-iOS9 激活 ==="
    check_ssh || return
    get_mount

    # 下载、修改并上传 plist 文件
    scp -P "$port" "$username@$server_address:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" "$TEMP_DIR/" &>/dev/null || {
        echo "错误：下载 com.apple.MobileGestalt.plist 失败。"
        return
    }
    $PLISTBUDDY -c "Add a6vjPkzcRjrsXmniFsm0dg bool true" "$TEMP_DIR/com.apple.MobileGestalt.plist" &>/dev/null || {
        echo "错误：修改 plist 文件失败。"
        return
    }
    scp -P "$port" "$TEMP_DIR/com.apple.MobileGestalt.plist" "$username@$server_address:$mount_point/mobile/Library/Caches/com.apple.MobileGestalt.plist" &>/dev/null || {
        echo "错误：上传修改后的 plist 文件失败。"
        return
    }

    echo "激活成功。"
    rm -rf "$TEMP_DIR"/*
}

# 工厂激活菜单
activate_ios() {
    echo "此激活功能不支持 SIM 卡或电话功能。"
    read -p "是否了解？（y/n）： " understand
    [ "$understand" != "y" ] && return
    echo "1. iOS5-iOS6 激活"
    echo "2. iOS7-iOS9 激活"
    read -p "请选择激活类型： " choice
    case $choice in
        1) activate_ios5_6 ;;
        2) activate_ios7_9 ;;
        *) echo "无效选项。" ;;
    esac
}

# SFTP 文件管理
sftp_manager() {
    echo "=== SFTP 文件管理 ==="
    check_ssh || return

    # 使用 expect 自动登录或手动输入密码
    command -v expect &>/dev/null && [ -n "$password" ] && {
        echo '#!/usr/bin/expect -f
set username [lindex $argv 0]
set server [lindex $argv 1]
set port [lindex $argv 2]
set password [lindex $argv 3]
spawn sftp -P $port $username@$server
expect "password:"
send "$password\r"
interact' > "$TEMP_DIR/sftp.sh"
        chmod +x "$TEMP_DIR/sftp.sh"
        "$TEMP_DIR/sftp.sh" "$username" "$server_address" "$port" "$password"
        rm -f "$TEMP_DIR/sftp.sh"
    } || {
        [ -z "$password" ] && echo "错误：未找到密码，无法自动登录。"
        echo "请手动输入密码："
        sftp -P "$port" "$username@$server_address"
    }
}

# 主菜单
main() {
    setup
    while true; do
        clear
        echo "=== 32位 iPhone SSH Ramdisk 操作工具 ==="
        echo "  1. 连接设备"
        echo "  2. 一键绕过iCloud激活锁"
        echo "  3. 一键工厂激活iOS"
        echo "  4. SFTP 文件管理"
        echo "  5. 退出"
        read -p "请选择选项： " choice

        case $choice in
            1) connect_device ;;
            2) bypass_icloud ;;
            3) activate_ios ;;
            4) sftp_manager ;;
            5) echo "正在退出..."; exit 0 ;;
            *) echo "无效选项。" ;;
        esac
        read -p "按回车键继续..."
    done
}

main
