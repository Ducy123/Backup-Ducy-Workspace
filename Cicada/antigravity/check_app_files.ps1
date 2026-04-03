Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($cmd) {
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    return $r.Output
}

Write-Host "=== Project Files ==="
$files = Run "cd /root/.openclaw/workspace-ducy-cto && find . -type f -not -path '*/node_modules/*' -not -path '*/.next/*' -not -path '*/.git/*'"
$files | ForEach-Object { Write-Host $_ }

Write-Host "=== Package.json ==="
Run "cat /root/.openclaw/workspace-ducy-cto/package.json 2>/dev/null" | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
