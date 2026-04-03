Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

# Read local file and encode to base64
$bytes = [System.IO.File]::ReadAllBytes("D:\code\Cicada\antigravity\rewrite_ui.py")
$b64 = [System.Convert]::ToBase64String($bytes)

# Decode on remote
Invoke-SSHCommand -SessionId $session.SessionId -Command "echo '$b64' | base64 -d > /tmp/rewrite_ui.py"
Write-Host "File uploaded via Base64."

# Run the python script
Write-Host "`nRunning UI rewrite script..." -ForegroundColor Yellow
$r = Invoke-SSHCommand -SessionId $session.SessionId -Command "python3 /tmp/rewrite_ui.py"
$r.Output | ForEach-Object { Write-Host $_ }

# Run npm run mode2:vercel-redeploy with correct PATH
Write-Host "`nTriggering Vercel deployment..." -ForegroundColor Magenta
$r2 = Invoke-SSHCommand -SessionId $session.SessionId -Command "cd /root/.openclaw/workspace-ducy-cto && export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH && npm run mode2:vercel-redeploy 2>&1" -TimeOut 300
$r2.Output | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
