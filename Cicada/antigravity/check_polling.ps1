Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 60
    $r.Output | ForEach-Object { Write-Host $_ }
}

$ws = "/root/.openclaw/workspace-ducy-cto"

# Check if useEffect/setInterval is in live-dashboard.tsx
Run "Check useEffect in live-dashboard" "grep -n 'useEffect\|setInterval\|use client\|const pull' $ws/components/live-dashboard.tsx | head -20"
Run "File size lines" "wc -l $ws/components/live-dashboard.tsx"
Run "First 5 lines" "head -5 $ws/components/live-dashboard.tsx"

# Check git log for what's actually deployed
Run "Git log recent" "cd $ws; git log --oneline -8"
Run "Git show live-dashboard in last commit" "cd $ws; git show HEAD --stat | grep live-dashboard"

Remove-SSHSession -SessionId $session.SessionId
