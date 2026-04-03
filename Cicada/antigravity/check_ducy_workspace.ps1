Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($cmd) {
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    return $r.Output
}

Write-Host "=== ducy-cto workspace contents ==="
Run "ls -la /root/.openclaw/workspace-ducy-cto/" | ForEach-Object { Write-Host $_ }

Write-Host "=== Find any source code folders in workspace ==="
Run "find /root/.openclaw/workspace-ducy-cto/ -maxdepth 2 -type d" | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
