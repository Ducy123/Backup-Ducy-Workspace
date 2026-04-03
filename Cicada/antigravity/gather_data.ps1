Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n=== $label ===" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    $r.Output | ForEach-Object { Write-Host $_ }
}

$node = "/root/.nvm/versions/node/v22.22.1/bin/node"
$oc = "/root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs"

# === 1. CHECK JASON BEFORE DELETE ===
Run "Jason agent dir size" "du -sh /root/.openclaw/agents/jason/ /root/.openclaw/workspace-jason/ 2>/dev/null"

# === 2. COUNT MAIN SESSIONS ===
Run "Main session count" "ls /root/.openclaw/agents/main/sessions/ 2>/dev/null | wc -l"
Run "Main sessions list (most recent 10)" "ls -lt /root/.openclaw/agents/main/sessions/ 2>/dev/null | head -15"

# === 3. CHECK SESSION FILE STRUCTURE ===
Run "Sessions dir content" "ls /root/.openclaw/agents/main/sessions/ 2>/dev/null | head -5"
Run "Sample session file" "ls -la /root/.openclaw/agents/main/sessions/*.json 2>/dev/null | head -5"

# === 4. READ SESSIONS INDEX ===  
Run "sessions.json" "cat /root/.openclaw/agents/main/sessions/sessions.json 2>/dev/null | python3 -m json.tool 2>/dev/null | head -60"

# === 5. CHECK LLM QUOTA ENDPOINT IN CLIPROXY ===
Run "cliproxy health/quota" "curl -s -H 'Authorization: Bearer ducy-cli-proxy-internal-key' http://127.0.0.1:8317/health 2>/dev/null | head -20"
Run "cliproxy status" "curl -s -H 'Authorization: Bearer ducy-cli-proxy-internal-key' http://127.0.0.1:8317/status 2>/dev/null | head -40"
Run "cliproxy auth-accounts" "curl -s -H 'Authorization: Bearer ducy-cli-proxy-internal-key' 'http://127.0.0.1:8317/v1/accounts' 2>/dev/null | head -40"

Remove-SSHSession -SessionId $session.SessionId
