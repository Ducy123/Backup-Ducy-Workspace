import json
import paramiko
import os
import sys

def main():
    with open('vps_config.json', 'r') as f:
        config = json.load(f)
    
    pub_key_path = os.path.expanduser('~/.ssh/id_ed25519.pub')
    if not os.path.exists(pub_key_path):
        print("Error: Public key not found!")
        sys.exit(1)
        
    with open(pub_key_path, 'r') as f:
        pub_key = f.read().strip()

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    connected = False
    for password in config['passwords']:
        try:
            print(f"Trying password: {password}")
            client.connect(hostname=config['host'], port=config['port'], username=config['user'], password=password, timeout=5)
            connected = True
            print("Login successful!")
            break
        except paramiko.AuthenticationException:
            print("Wrong password.")
        except Exception as e:
            print(f"Connection error: {e}")
            
    if not connected:
        print("Could not login with any password.")
        sys.exit(1)

    commands = [
        "mkdir -p ~/.ssh",
        f"echo '{pub_key}' >> ~/.ssh/authorized_keys",
        "chmod 700 ~/.ssh",
        "chmod 600 ~/.ssh/authorized_keys"
    ]
    
    for cmd in commands:
        stdin, stdout, stderr = client.exec_command(cmd)
        err = stderr.read().decode('utf-8')
        if err:
            print(f"Warning on '{cmd}': {err}")

    print("SSH key added successfully!")
    client.close()

if __name__ == '__main__':
    main()
