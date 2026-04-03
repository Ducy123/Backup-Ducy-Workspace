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
$npm = "export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH"
$TOKEN = "0e5cc16331948318499f7dc37aceed9d729c83276f563bf3b88f28b4cedd38c4"

# 1. Check current tunnel is alive
Run "Tunnel alive?" "pgrep -a cloudflared | head -2; cat $ws/ops/generated/quick-tunnel/bridge-public-url.txt"
Run "Bridge alive?" "ss -ltnp | grep 8787"

# 2. Test bridge from VPS (local)
Run "Bridge local health" "curl -s -H 'Authorization: Bearer $TOKEN' http://127.0.0.1:8787/bridge/control-center/api/health"

# 3. Test bridge via tunnel (simulating Vercel)
Run "Bridge via tunnel" "curl -s -H 'Authorization: Bearer $TOKEN' https://concluded-wool-friendship-judicial.trycloudflare.com/bridge/control-center/api/health | head -3"

# 4. Check what Vercel env BRIDGE_BASE_URL actually is right now
Run "Vercel env production BRIDGE_BASE_URL" "$npm; cd $ws; npx vercel env ls 2>&1 | grep -A2 BRIDGE_BASE_URL | head -10"

# 5. Force update Vercel production env with new tunnel
Run "Update Vercel BRIDGE_BASE_URL production" "$npm; cd $ws; echo 'https://concluded-wool-friendship-judicial.trycloudflare.com/bridge/control-center' | npx vercel env add BRIDGE_BASE_URL production --force 2>&1 | tail -5"

Remove-SSHSession -SessionId $session.SessionId
