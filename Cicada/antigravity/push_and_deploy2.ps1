Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

# Upload the file
Set-SCPItem -SessionId $session.SessionId -Path "D:\code\Cicada\antigravity\rewrite_ui.py" -Destination "/tmp/rewrite_ui.py" -Force
Write-Host "File uploaded."

# Run the python script
$r = Invoke-SSHCommand -SessionId $session.SessionId -Command "python3 /tmp/rewrite_ui.py"
$r.Output | ForEach-Object { Write-Host $_ }

# Run npm run mode2:vercel-redeploy with correct PATH
Write-Host "`nTriggering Vercel deployment..." -ForegroundColor Magenta
$r2 = Invoke-SSHCommand -SessionId $session.SessionId -Command "cd /root/.openclaw/workspace-ducy-cto && export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH && npm run mode2:vercel-redeploy 2>&1" -TimeOut 300
$r2.Output | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
