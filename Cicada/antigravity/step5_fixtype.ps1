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

# Fix using python3 to replace the bad tone and strip unsupported color prop
Run "Fix Badge and ProgressBar via python" @"
python3 << 'PYEOF'
p = '/root/.openclaw/workspace-ducy-cto/components/live-dashboard.tsx'
with open(p) as f: c = f.read()
c = c.replace('tone="blue"', 'tone="cyan"')
c = c.replace('color="blue"', '')
with open(p, 'w') as f: f.write(c)
print('FIXED')
PYEOF
"@

Run "Git commit fix" "cd $ws; git add components/live-dashboard.tsx; git commit -m 'fix: replace unsupported Badge tone blue with cyan, remove ProgressBar color prop'"
Run "Redeploy" "$npm; cd $ws; npm run mode2:vercel-redeploy 2>&1"

Remove-SSHSession -SessionId $session.SessionId
