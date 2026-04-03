Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

$node = "/root/.nvm/versions/node/v22.22.1/bin/node"
$oc = "/root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs"

# Get ducy-cto's current session id to send message to the right session
$r = Invoke-SSHCommand -SessionId $session.SessionId -Command "cat /root/.openclaw/agents/ducy-cto/sessions/sessions.json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); k=list(d.keys()); print(d[k[0]][\"sessionId\"]) if k else print(\"\")'"
$sessionId = ($r.Output | Where-Object { $_ -match "^[a-f0-9-]{36}$" } | Select-Object -First 1).Trim()
Write-Host "ducy-cto session ID: $sessionId" -ForegroundColor Yellow

# Send PM kickoff message
$kickoffCmd = "$node $oc agent --agent ducy-cto --message '[PM] I have sent you the 4 tasks via Telegram. Please start immediately with TASK 1 (LLM Quota Panel). Create bridge endpoint GET /api/llm-quota in the Next.js app. Read /root/.cli-proxy-api/antigravity-*.json for token data and /root/.cli-proxy-api/logs/error-*.log for error rate. Then update the dashboard page to show the quota progress bars. Start NOW.' --timeout 30 2>&1"
Write-Host "`n=== Sending kickoff to ducy-cto ===" -ForegroundColor Green
$r2 = Invoke-SSHCommand -SessionId $session.SessionId -Command "cd /root; $kickoffCmd" -TimeOut 35
$r2.Output | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
