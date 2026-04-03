Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 120
    $r.Output | ForEach-Object { Write-Host $_ }
}

$ws = "/root/.openclaw/workspace-ducy-cto"

Run "Fetch live-dashboard.tsx" "python3 -c \"
with open('$ws/components/live-dashboard.tsx', 'r') as f:
    print(f.read())
\""

Run "Fetch ui.tsx snippet" "python3 -c \"
with open('$ws/components/ui.tsx', 'r') as f:
    print(f.read()[:2000])
\""

Remove-SSHSession -SessionId $session.SessionId
