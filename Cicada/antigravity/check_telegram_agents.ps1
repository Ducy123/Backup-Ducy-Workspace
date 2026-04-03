Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($cmd) {
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    return $r.Output
}

Write-Host "=== config_dump ==="
Run "cat /root/.openclaw/openclaw.json" | ForEach-Object { Write-Host $_ }

Write-Host "=== agents_list ==="
Run "ls -la /root/.openclaw/agents/" | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
