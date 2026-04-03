Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

$node = "/root/.nvm/versions/node/v22.22.1/bin/node"
$oc = "/root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs"

# Send nudge via openclaw agent CLI (non-blocking - just check it fired)  
Write-Host "Sending PM nudge to ducy-cto..." -ForegroundColor Yellow

$r = Invoke-SSHCommand -SessionId $session.SessionId -Command "cd /root; $node $oc agent --agent ducy-cto --message '[PM FOLLOW-UP] Good work on the live polling! The real-time 10s refresh + green status dots are confirmed. Now please implement the 3 remaining tasks in ONE COMMIT: TASK 1 add GET /api/llm-quota to bridge-server.mjs (read /root/.cli-proxy-api/antigravity-*.json + count error logs), TASK 3 add POST /api/agent-model to bridge that edits openclaw.json and restarts gateway, TASK 4 add GET /api/session-log?agentId=X to bridge that reads the .jsonl file. Also add the session summarize endpoint POST /api/summarize-session. Then redeploy to Vercel. Do all 3 tasks now.' --timeout 20 2>&1" -TimeOut 25
$r.Output | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $session.SessionId
