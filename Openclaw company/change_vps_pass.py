import time
import json
import paramiko
import sys
import os

def main():
    old_pass = "Levcloud2024@@"
    new_pass = "OpenClaw@2026!"
    host = "103.173.227.155"
    port = 28601
    user = "root"

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    print("Connecting to VPS to handle password expiry...")
    client.connect(hostname=host, port=port, username=user, password=old_pass, timeout=10)
    
    channel = client.invoke_shell()
    time.sleep(2)
    output = channel.recv(9999).decode('utf-8')
    print("Initial output:", output)

    if "current" in output.lower() or "unix password" in output.lower():
        print("Sending old password...")
        channel.send(old_pass + "\n")
        time.sleep(2)
        output = channel.recv(9999).decode('utf-8')
        print("After old pass:", output)

    if "new password:" in output.lower():
        print("Sending new password...")
        channel.send(new_pass + "\n")
        time.sleep(2)
        output = channel.recv(9999).decode('utf-8')
        print("After new pass:", output)

        if "retype new password:" in output.lower() or "retype" in output.lower():
            print("Retyping new password...")
            channel.send(new_pass + "\n")
            time.sleep(3)
            output = channel.recv(9999).decode('utf-8')
            print("After retype pass:", output)
            
            if "successfully" in output.lower() or "updated" in output.lower():
                print("Password changed successfully!")

    client.close()
    
    # Update config
    with open('vps_config.json', 'w') as f:
        json.dump({
            "host": host,
            "port": port,
            "user": user,
            "passwords": [new_pass]
        }, f, indent=2)
    print("vps_config.json updated.")

    # Now deploy ssh key
    print("Re-connecting with new password to deploy SSH key...")
    client2 = paramiko.SSHClient()
    client2.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client2.connect(hostname=host, port=port, username=user, password=new_pass, timeout=10)
    
    pub_key_path = os.path.expanduser('~/.ssh/id_ed25519.pub')
    with open(pub_key_path, 'r') as f:
        pub_key = f.read().strip()
        
    commands = [
        "mkdir -p ~/.ssh",
        f"echo '{pub_key}' >> ~/.ssh/authorized_keys",
        "chmod 700 ~/.ssh",
        "chmod 600 ~/.ssh/authorized_keys"
    ]
    for cmd in commands:
        stdin, stdout, stderr = client2.exec_command(cmd)
        err = stderr.read().decode('utf-8')
        if err:
            print(f"Warning on '{cmd}': {err}")
    print("SSH key deployed successfully using new password.")
    client2.close()

if __name__ == '__main__':
    main()
