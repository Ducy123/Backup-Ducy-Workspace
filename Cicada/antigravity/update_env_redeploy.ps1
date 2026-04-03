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
$NEW_BRIDGE = "https://concluded-wool-friendship-judicial.trycloudflare.com/bridge/control-center"

# Update the ephemeral env file with new bridge URL
Run "Update ephemeral env" "sed -i 's|BRIDGE_BASE_URL=.*|BRIDGE_BASE_URL=$NEW_BRIDGE|g' $ws/.vercel.mode2.ephemeral.env; grep BRIDGE_BASE_URL $ws/.vercel.mode2.ephemeral.env"

# Sync the env and redeploy
Run "Sync env to Vercel" "$npm; cd $ws; npm run mode2:vercel-sync 2>&1 | tail -20"

# Commit and redeploy
Run "Git commit" "cd $ws; git add -A; git commit -m 'fix: graceful SSR error handling, updated tunnel URL'"
Run "Redeploy" "$npm; cd $ws; npm run mode2:vercel-redeploy 2>&1"

Remove-SSHSession -SessionId $session.SessionId
