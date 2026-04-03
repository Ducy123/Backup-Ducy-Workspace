Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

# Upload the file
Set-SCPFile -SessionId $session.SessionId -LocalFile "D:\code\Cicada\antigravity\rewrite_ui.py" -RemotePath "/tmp/rewrite_ui.py"
Write-Host "File uploaded."

# Run the python script
$r = Invoke-SSHCommand -SessionId $session.SessionId -Command "python3 /tmp/rewrite_ui.py"
$r.Output | ForEach-Object { Write-Host $_ }

# Run npm run mode2:vercel-redeploy
Write-Host "Triggering deployment..."
$npm = "/root/.nvm/versions/node/v22.22.1/bin/npm"
$r2 = Invoke-SSHCommand -SessionId $session.SessionId -Command "cd /root/.openclaw/workspace-ducy-cto; $npm run mode2:vercel-redeploy 2>&1" -TimeOut 300
$r2.Output | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
