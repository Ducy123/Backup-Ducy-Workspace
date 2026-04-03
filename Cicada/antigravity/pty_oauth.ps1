Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 60
    $r.Output | ForEach-Object { Write-Host $_ }
}

$pyScript = @'
import os
import pty
import sys

def capture():
    cmd = ["/root/.nvm/versions/node/v22.22.1/bin/node", "/root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs", "models", "auth", "login-github-copilot", "--alias", "account3"]
    env = os.environ.copy()
    env["PATH"] = "/root/.nvm/versions/node/v22.22.1/bin:" + env.get("PATH", "")
    
    # Run the command in a pseudo-terminal
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(cmd[0], cmd, env)
    else:
        out = b""
        import time
        start_time = time.time()
        while time.time() - start_time < 5:
            try:
                import select
                r, _, _ = select.select([fd], [], [], 1.0)
                if fd in r:
                    data = os.read(fd, 1024)
                    if not data:
                        break
                    out += data
            except OSError:
                break
        
        with open("/tmp/oauth.txt", "wb") as f:
            f.write(out)
        
        # Kill the child if still running
        import signal
        try: os.kill(pid, signal.SIGTERM)
        except: pass

capture()
'@

$bytes = [System.Text.Encoding]::UTF8.GetBytes($pyScript)
$b64 = [System.Convert]::ToBase64String($bytes)
$chunk = 1800; $first = $true
for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
    $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
    if ($first) { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' > /tmp/pty.b64" | Out-Null; $first = $false }
    else { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' >> /tmp/pty.b64" | Out-Null }
}
Invoke-SSHCommand -SessionId $session.SessionId -Command "base64 -d /tmp/pty.b64 > /tmp/pty.py && rm /tmp/pty.b64" | Out-Null

Run "Run PTY wrapper" "python3 /tmp/pty.py"
Run "Check PTY output" "cat /tmp/oauth.txt"

Remove-SSHSession -SessionId $session.SessionId
