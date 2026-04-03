Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

$node = "/root/.nvm/versions/node/v22.22.1/bin/node"
$oc = "/root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs"
$ws = "/root/.openclaw/workspace-ducy-cto"

# First check what live-dashboard.tsx contains - this is the new file
Write-Host "`n=== NEW FILE: live-dashboard.tsx ===" -ForegroundColor Cyan
$r = Invoke-SSHCommand -SessionId $session.SessionId -Command "cat $ws/components/live-dashboard.tsx 2>/dev/null | head -60"
$r.Output | ForEach-Object { Write-Host $_ }

# Check what changed in bridge-server.mjs
Write-Host "`n=== BRIDGE: new endpoints ===" -ForegroundColor Cyan
$r2 = Invoke-SSHCommand -SessionId $session.SessionId -Command "grep -E 'router\.|app\.(get|post)|/api/' $ws/scripts/bridge-server.mjs 2>/dev/null | head -30"
$r2.Output | ForEach-Object { Write-Host $_ }

# check tunnel URL
Write-Host "`n=== Tunnel URL ===" -ForegroundColor Cyan
$r3 = Invoke-SSHCommand -SessionId $session.SessionId -Command "cat $ws/ops/generated/quick-tunnel/bridge-public-url.txt 2>/dev/null"
$r3.Output | ForEach-Object { Write-Host $_ }

# Check what vercel URL is now  
Write-Host "`n=== Vercel env ===" -ForegroundColor Cyan
$r4 = Invoke-SSHCommand -SessionId $session.SessionId -Command "cat $ws/.vercel.mode2.env 2>/dev/null | grep -v PASSWORD | grep -v CREDENTIAL | head -10"
$r4.Output | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
