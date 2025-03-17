#!/bin/bash

# 创建必要的目录
mkdir -p data/dependencies data/temp

connect_device() {
    if [ -f data/config.json ]; then
        echo "存在已保存的数据，是否一键引用？(y/n)"
        read choice
        if [ "$choice" = "y" ]; then
            cat data/config.json | jq -c '.[]' | while read config; do
                alias=$(echo "$config" | jq -r '.alias')
                echo "$alias"
            done
            echo "请选择要引用的配置序号"
            read selected
            server_config=$(cat data/config.json | jq -c ".[$((selected - 1))]")
        else
            create_new_config
        fi
    else
        create_new_config
    fi

    host=$(echo "$server_config" | jq -r '.host')
    port=$(echo "$server_config" | jq -r '.port')
    username=$(echo "$server_config" | jq -r '.username')
    password=$(echo "$server_config" | jq -r '.password')

    ssh -o StrictHostKeyChecking=no -p "$port" "$username"@"$host" exit 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "服务器测试成功，配置已保存"
        if! grep -q "$server_config" data/config.json; then
            echo "$server_config" | jq -s '.' >> data/config.json
        fi
    else
        echo "连接失败，请检查配置"
    fi
}

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
    server_config="{\"alias\":\"$alias\",\"host\":\"$host\",\"username\":\"$username\",\"password\":\"$password\",\"port\":\"$port\"}"
    if [ -f data/config.json ]; then
        cat data/config.json | jq -s '.' > temp.json
        echo "$server_config" | jq -s '.' >> temp.json
        cat temp.json | jq -s 'add' > data/config.json
        rm temp.json
    else
        echo "$server_config" | jq -s '.' > data/config.json
    fi
}

one_click_activate() {
    if [ -f data/config.json ]; then
        cat data/config.json | jq -c '.[]' | while read config; do
            alias=$(echo "$config" | jq -r '.alias')
            echo "$alias"
        done
        echo "请选择要使用的配置序号"
        read selected
        server_config=$(cat data/config.json | jq -c ".[$((selected - 1))]")
    else
        echo "请先连接设备"
        return
    fi

    host=$(echo "$server_config" | jq -r '.host')
    port=$(echo "$server_config" | jq -r '.port')
    username=$(echo "$server_config" | jq -r '.username')
    password=$(echo "$server_config" | jq -r '.password')

    echo "该激活无法支持SIM卡及通话"
    read -p "按任意键继续..."

    echo "1. iOS5 - iOS6激活"
    echo "2. iOS7 - iOS9激活"
    echo "请选择激活版本"
    read choice

    echo "请输入SSHRamdisk挂载目录（通常为mnt1、mnt2等）"
    read mount_dir

    if [ "$choice" = "1" ]; then
        scp -P "$port" data/lockdownd "$username"@"$host":"$mount_dir"/usr/libexec/lockdownd
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
        mkdir -p data/temp
        scp -P "$port" "$username"@"$host":"$mount_dir"/mobile/Library/Caches/com.apple.MobileGestalt.plist data/temp/
        if [ $? -eq 0 ]; then
            plutil -replace a6vjPkzcRjrsXmniFsm0dg -bool true data/temp/com.apple.MobileGestalt.plist
            scp -P "$port" data/temp/com.apple.MobileGestalt.plist "$username"@"$host":"$mount_dir"/mobile/Library/Caches/com.apple.MobileGestalt.plist
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

sftp_file_manager() {
    if [ -f data/config.json ]; then
        cat data/config.json | jq -c '.[]' | while read config; do
            alias=$(echo "$config" | jq -r '.alias')
            echo "$alias"
        done
        echo "请选择要使用的配置序号"
        read selected
        server_config=$(cat data/config.json | jq -c ".[$((selected - 1))]")
    else
        echo "请先连接设备"
        return
    fi

    host=$(echo "$server_config" | jq -r '.host')
    port=$(echo "$server_config" | jq -r '.port')
    username=$(echo "$server_config" | jq -r '.username')
    password=$(echo "$server_config" | jq -r '.password')

    sftp -P "$port" "$username"@"$host" << EOF
ls
help
exit
EOF
}

main() {
    while true; do
        clear
        echo "32位iPhone SSHRamdisk操作工具"
        echo "1. 连接设备"
        echo "2. 一键工厂激活iOS"
        echo "3. sftp文件管理器"
        echo "4. 退出"
        read -p "请选择操作: " choice

        case $choice in
            1) connect_device ;;
            2) one_click_activate ;;
            3) sftp_file_manager ;;
            4) break ;;
            *) echo "无效的选择，请重新输入" ;;
        esac
        read -p "按任意键继续..."
    done
}

# 检查jq是否存在，若不存在提示安装
if! command -v jq &> /dev/null; then
    echo "jq not found. Please install jq and add it to data/dependencies directory, then add data/dependencies to PATH."
    exit 1
fi

main