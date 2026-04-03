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

# === STEP 1: Restart bridge server ===
Run "Start bridge server" "$npm; cd $ws; nohup node scripts/bridge-server.mjs > /tmp/bridge.log 2>&1 & sleep 2; ss -ltnp | grep '8787'"
Run "Bridge log" "tail -5 /tmp/bridge.log"

# === STEP 2: Start cloudflare quick-tunnel ===
Run "Kill old cloudflared" "pkill -f cloudflared 2>/dev/null; sleep 1; echo killed"
Run "Start new tunnel" "$npm; cd $ws; nohup bash scripts/mode2-quick-tunnel.sh > /tmp/tunnel.log 2>&1 & sleep 8; echo done"
Run "Tunnel log" "cat /tmp/tunnel.log | grep -E 'trycloudflare|INF|ERR' | tail -10"
Run "New tunnel URL" "cat $ws/ops/generated/quick-tunnel/bridge-public-url.txt 2>/dev/null"

Remove-SSHSession -SessionId $session.SessionId
