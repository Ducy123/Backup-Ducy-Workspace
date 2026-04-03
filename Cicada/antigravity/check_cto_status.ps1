Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($cmd) {
    Write-Host "`n=== Run: $cmd ===" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    $r.Output | ForEach-Object { Write-Host $_ }
}

Run "cat /root/.openclaw/workspace-ducy-cto/ops/MODE2_PRIVATE_BRIDGE.md | head -n 40"
Run "cat /root/.openclaw/workspace-ducy-cto/app/page.tsx | head -n 40"
Run "cat /root/.openclaw/workspace-ducy-cto/package.json"

Remove-SSHSession -SessionId $session.SessionId
