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

# 1. Check tunnel status
Run "Tunnel status" "cat $ws/ops/generated/quick-tunnel/bridge-public-url.txt 2>/dev/null"
Run "Check cloudflared running" "pgrep -a cloudflared 2>/dev/null | head -5; echo '---'"

# 2. Check bridge process
Run "Bridge running" "pgrep -a 'node.*bridge-server' 2>/dev/null | head -5; echo '---'"
Run "Bridge port" "ss -ltnp | grep 8787; echo '---port check---'"

# 3. Curl the bridge health
Run "Curl bridge health" "curl -s -w 'HTTP:%{http_code}' http://127.0.0.1:8787/bridge/control-center/api/health 2>/dev/null | head -20"

# 4. Check vercel env for bridge URL
Run "Vercel BRIDGE_BASE_URL" "cat $ws/.vercel.mode2.ephemeral.env 2>/dev/null | grep BRIDGE_BASE_URL"

# 5. Check page.tsx to understand how initial data is loaded
Run "app/page.tsx SSR logic" "head -40 $ws/app/page.tsx"

Remove-SSHSession -SessionId $session.SessionId
