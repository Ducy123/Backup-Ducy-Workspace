Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 300
    $r.Output | ForEach-Object { Write-Host $_ }
}

$ws = "/root/.openclaw/workspace-ducy-cto"
$npm = "export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH"

# Fix: replace tone="blue" with tone="cyan"
Run "Fix Badge tone" "sed -i 's/tone=\"blue\"/tone=\"cyan\"/g' $ws/components/live-dashboard.tsx && echo fixed"
Run "Verify fix" "grep 'tone' $ws/components/live-dashboard.tsx | grep -v '//' | sort -u"

# Quick fix to remove ProgressBar 'color' prop issue too (use inline approach)
Run "Check ProgressBar type error" "grep -n 'ProgressBar' $ws/components/live-dashboard.tsx | head -5"

Run "Git commit" "cd $ws; git add components/; git commit -m 'fix: Badge tone, remove unsupported blue tone'"
Run "Redeploy" "$npm; cd $ws; npm run mode2:vercel-redeploy 2>&1"

Remove-SSHSession -SessionId $session.SessionId
