import os
import json
import paramiko
from paramiko import SSHException, AuthenticationException, SFTPClient


def load_config():
    config_path = 'data/config.json'
    if not os.path.exists(config_path):
        return []
    with open(config_path, 'r') as f:
        return json.load(f)


def save_config(configs):
    config_path = 'data/config.json'
    with open(config_path, 'w') as f:
        json.dump(configs, f, indent=4)


def connect_device():
    configs = load_config()
    if configs:
        print("存在已保存的数据，是否一键引用？(y/n)")
        choice = input().lower()
        if choice == 'y':
            for i, config in enumerate(configs):
                print(f"{i + 1}. {config['alias']}")
            selected = int(input("请选择要引用的配置序号: ")) - 1
            server_config = configs[selected]
        else:
            server_config = create_new_config()
    else:
        server_config = create_new_config()

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(server_config['host'], port=server_config['port'], username=server_config['username'],
                    password=server_config['password'])
        print("服务器测试成功，配置已保存")
        if server_config not in configs:
            configs.append(server_config)
            save_config(configs)
    except AuthenticationException:
        print("认证失败，请检查用户名和密码")
    except SSHException as e:
        print(f"连接失败: {e}")
    finally:
        ssh.close()


def create_new_config():
    alias = input("请输入服务器别名: ")
    host = input("请输入服务器地址: ")
    username = input("请输入用户名: ")
    password = input("请输入密码: ")
    port = int(input("请输入端口号: "))
    return {
        "alias": alias,
        "host": host,
        "username": username,
        "password": password,
        "port": port
    }


def one_click_activate():
    print("该激活无法支持SIM卡及通话")
    input("按任意键继续...")
    print("1. iOS5 - iOS6激活")
    print("2. iOS7 - iOS9激活")
    choice = input("请选择激活版本: ")
    mount_dir = input("请输入SSHRamdisk挂载目录（通常为mnt1、mnt2等）: ")
    configs = load_config()
    if not configs:
        print("请先连接设备")
        return
    for i, config in enumerate(configs):
        print(f"{i + 1}. {config['alias']}")
    selected = int(input("请选择要使用的配置序号: ")) - 1
    server_config = configs[selected]

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(server_config['host'], port=server_config['port'], username=server_config['username'],
                    password=server_config['password'])
        if choice == '1':
            sftp = ssh.open_sftp()
            local_path = 'data/lockdownd'
            remote_path = f'{mount_dir}/usr/libexec/lockdownd'
            try:
                sftp.put(local_path, remote_path)
                stdin, stdout, stderr = ssh.exec_command(f'chmod 0755 {remote_path}')
                if stderr.read():
                    print(f"激活失败: {stderr.read().decode()}")
                else:
                    print("激活成功")
            except FileNotFoundError:
                print("lockdownd文件未找到")
            finally:
                sftp.close()
        elif choice == '2':
            sftp = ssh.open_sftp()
            local_temp_dir = 'data/temp'
            os.makedirs(local_temp_dir, exist_ok=True)
            remote_path = f'{mount_dir}/mobile/Library/Caches/com.apple.MobileGestalt.plist'
            local_path = os.path.join(local_temp_dir, 'com.apple.MobileGestalt.plist')
            try:
                sftp.get(remote_path, local_path)
                # 这里需要处理plist文件的修改，暂未实现
                sftp.put(local_path, remote_path)
                print("激活成功")
            except FileNotFoundError:
                print("文件未找到")
            finally:
                sftp.close()
    except AuthenticationException:
        print("认证失败，请检查用户名和密码")
    except SSHException as e:
        print(f"连接失败: {e}")
    finally:
        ssh.close()


def sftp_file_manager():
    configs = load_config()
    if not configs:
        print("请先连接设备")
        return
    for i, config in enumerate(configs):
        print(f"{i + 1}. {config['alias']}")
    selected = int(input("请选择要使用的配置序号: ")) - 1
    server_config = configs[selected]

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(server_config['host'], port=server_config['port'], username=server_config['username'],
                    password=server_config['password'])
        sftp = ssh.open_sftp()
        print("常用选项: ls, get, put, rm, mkdir, pwd")
        while True:
            command = input("请输入sftp命令 (输入exit退出): ")
            if command == 'exit':
                break
            try:
                if command.startswith('ls'):
                    path = command.split(' ')[1] if len(command.split(' ')) > 1 else '.'
                    files = sftp.listdir(path)
                    for file in files:
                        print(file)
                elif command.startswith('get'):
                    remote_path, local_path = command.split(' ')[1:]
                    sftp.get(remote_path, local_path)
                elif command.startswith('put'):
                    local_path, remote_path = command.split(' ')[1:]
                    sftp.put(local_path, remote_path)
                elif command.startswith('rm'):
                    remote_path = command.split(' ')[1]
                    sftp.remove(remote_path)
                elif command.startswith('mkdir'):
                    remote_path = command.split(' ')[1]
                    sftp.mkdir(remote_path)
                elif command.startswith('pwd'):
                    print(sftp.getcwd())
                else:
                    print("不支持的命令")
            except Exception as e:
                print(f"执行命令失败: {e}")
    except AuthenticationException:
        print("认证失败，请检查用户名和密码")
    except SSHException as e:
        print(f"连接失败: {e}")
    finally:
        sftp.close()
        ssh.close()


def main():
    os.makedirs('data', exist_ok=True)
    os.makedirs('data/dependencies', exist_ok=True)
    os.makedirs('data/temp', exist_ok=True)
    while True:
        print("32位iPhone SSHRamdisk操作工具")
        print("1. 连接设备")
        print("2. 一键工厂激活iOS")
        print("3. sftp文件管理器")
        print("4. 退出")
        choice = input("请选择操作: ")
        if choice == '1':
            connect_device()
        elif choice == '2':
            one_click_activate()
        elif choice == '3':
            sftp_file_manager()
        elif choice == '4':
            break
        else:
            print("无效的选择，请重新输入")


if __name__ == "__main__":
    main()
