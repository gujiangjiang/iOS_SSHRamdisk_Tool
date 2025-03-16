import json
import os
import subprocess
import requests
import zipfile

def download_jq():
    """下载 jq 到程序目录"""
    jq_url = "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64"
    try:
        response = requests.get(jq_url)
        response.raise_for_status()  # 检查下载是否成功
        with open("jq", "wb") as f:
            f.write(response.content)
        os.chmod("jq", 0o755)  # 添加执行权限
        print("jq 下载成功！")
    except requests.exceptions.RequestException as e:
        print(f"jq 下载失败：{e}")

def check_dependencies():
    """检查依赖项是否存在，如果不存在则下载"""
    if not os.path.exists("jq"):
        print("检测到 jq 不存在，正在下载...")
        download_jq()

def load_config():
    """加载配置文件"""
    try:
        with open("config.json", "r") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

def save_config(config):
    """保存配置文件"""
    with open("config.json", "w") as f:
        json.dump(config, f, indent=4)

def test_ssh_connection(server_data):
    """测试 SSH 连接"""
    try:
        command = [
            "ssh",
            "-o", "StrictHostKeyChecking=no", #第一次连接时，不弹出提示。
            f"{server_data['username']}@{server_data['address']}",
            "-p", server_data["port"],
            "echo 'SSH 连接测试成功！'",
        ]
        result = subprocess.run(command, capture_output=True, text=True, timeout=5)
        if "SSH 连接测试成功！" in result.stdout:
            return True
        else:
            return False

    except subprocess.TimeoutExpired:
        print("SSH 连接超时！")
        return False
    except subprocess.CalledProcessError as e:
        print(f"SSH 连接失败：{e}")
        return False

def connect_device(config):
    """连接设备"""
    if config:
        print("存在已保存的数据，是否一键引用？ (y/n)")
        if input().lower() == "y":
            server_data = config
        else:
            server_data = {}
    else:
        server_data = {}

    if not server_data:
        server_data["alias"] = input("服务器别名：")
        server_data["address"] = input("服务器地址：")
        server_data["username"] = input("用户名：")
        server_data["password"] = input("密码：")
        server_data["port"] = input("端口号：")

        if test_ssh_connection(server_data):
            print("服务器测试成功，配置已保存！")
            save_config(server_data)
        else:
            print("服务器测试失败！")

def factory_activate_ios(config):
    """一键工厂激活 iOS"""
    if not config:
        print("请先连接设备！")
        return

    print("该激活无法支持 SIM 卡及通话，是否了解？ (y/n)")
    if input().lower() != "y":
        return

    print("请输入 SSHRamdisk 挂载目录 (例如 mnt1)：")
    mnt_dir = input()

    print("选择激活方式：")
    print("1. iOS 5-iOS 6 激活")
    print("2. iOS 7-iOS 9 激活")
    choice = input()

    if choice == "1":
        activate_ios_5_6(config, mnt_dir)
    elif choice == "2":
        activate_ios_7_9(config, mnt_dir)
    else:
        print("无效的选择！")

def activate_ios_5_6(config, mnt_dir):
    """iOS 5-iOS 6 激活"""
    try:
        command = [
            "scp",
            "-P", config["port"],
            "lockdownd",
            f"{config['username']}@{config['address']}:{mnt_dir}/usr/libexec/lockdownd",
        ]
        subprocess.run(command, check=True)
        command = [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            f"{config['username']}@{config['address']}",
            "-p", config["port"],
            f"chmod 0755 {mnt_dir}/usr/libexec/lockdownd",
        ]
        subprocess.run(command, check=True)
        print("激活成功！")
    except subprocess.CalledProcessError as e:
        print(f"激活失败：{e}")

def activate_ios_7_9(config, mnt_dir):
    """iOS 7-iOS 9 激活"""
    try:
        command = [
            "scp",
            "-P", config["port"],
            f"{config['username']}@{config['address']}:{mnt_dir}/mobile/Library/Caches/com.apple.MobileGestalt.plist",
            "temp/com.apple.MobileGestalt.plist",
        ]
        subprocess.run(command, check=True)

        # 修改 plist 文件（这里需要使用第三方库，例如 `plistlib`）
        # ... (修改 plist 文件的代码) ...
        #这里因为macos自带plistlib，所以可以进行plist文件的编辑。
        import plistlib

        with open("temp/com.apple.MobileGestalt.plist", 'rb') as fp:
            pl = plistlib.load(fp)
        pl["a6vjPkzcRjrsXmniFsm0dg"] = True

        with open("temp/com.apple.MobileGestalt.plist", 'wb') as fp:
            plistlib.dump(pl, fp)

        command = [
            "scp",
            "-P", config["port"],
            "temp/com.apple.MobileGestalt.plist",
            f"{config['username']}@{config['address']}:{mnt_dir}/mobile/Library/Caches/com.apple.MobileGestalt.plist",
        ]
        subprocess.run(command, check=True)
        print("激活成功！")
    except subprocess.CalledProcessError as e:
        print(f"激活失败：{e}")

def sftp_file_manager(config):
    """SFTP 文件管理器"""
    if not config:
        print("请先连接设备！")
        return

    command = [
        "sftp",
        "-o", "StrictHostKeyChecking=no",
        "-P", config["port"],
        f"{config['username']}@{config['address']}",
    ]
    subprocess.run(command)

def main():
    """主程序"""
    check_dependencies()
    config = load_config()

    while True:
        print("\n32 位 iPhone SSHRamdisk 操作工具")
        print("1. 连接设备")
        print("2. 一键工厂激活 iOS")
        print("3. SFTP 文件管理器")
        print("4. 退出")

        choice = input("请选择：")

        if choice == "1":
            connect_device(config)
            config = load_config() #重新读取config，保证config数据是最新的。
        elif choice == "2":
            factory_activate_ios(config)
        elif choice == "3":
            sftp_file_manager(config)
        elif choice == "4":
            break
        else:
            print
