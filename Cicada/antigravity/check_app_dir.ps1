Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($cmd) {
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    return $r.Output
}

Write-Host "=== app/ directory ==="
Run "ls -al /root/.openclaw/workspace-ducy-cto/app 2>/dev/null || ls -al /root/.openclaw/workspace-ducy-cto/pages 2>/dev/null" | ForEach-Object { Write-Host $_ }

Write-Host "=== Check openclaw agent CLI ==="
Run "cd /root && /root/.nvm/versions/node/v22.22.1/bin/node /root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs agent --help 2>&1" | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
