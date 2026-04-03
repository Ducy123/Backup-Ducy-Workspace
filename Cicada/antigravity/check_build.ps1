Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($cmd) {
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    return $r.Output
}

Write-Host "=== Check Build Status ==="
Run "cd /root/.openclaw/workspace-ducy-cto && /root/.nvm/versions/node/v22.22.1/bin/npm run build 2>&1" | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
