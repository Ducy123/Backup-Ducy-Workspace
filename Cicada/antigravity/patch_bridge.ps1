Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 60
    $r.Output | ForEach-Object { Write-Host $_ }
}

$pyScript = @'
import os

p = "/root/.openclaw/workspace-ducy-cto/scripts/bridge-server.mjs"
with open(p, "r") as f:
    text = f.read()

body_parser_code = "const body = await new Promise(r => { let b=''; req.on('data',c=>b+=c); req.on('end',()=>r(JSON.parse(b||'{}'))) }).catch(()=>({}));"

# Fix /api/agent-model
target1 = "if (req.method === 'POST' && route === '/api/agent-model') {"
if target1 in text and body_parser_code not in text:
    text = text.replace(
        target1,
        target1 + "\n    " + body_parser_code
    )

# Fix /api/summarize-session
target2 = "if (req.method === 'POST' && route === '/api/summarize-session') {"
if target2 in text and body_parser_code not in text:
    text = text.replace(
        target2,
        target2 + "\n    " + body_parser_code
    )

# Fix API llm-quota logic to return default instead of breaking when folder missing
target3 = "Math.max(0,100-Math.round(ec*2.5))});"
if target3 in text:
    text = text.replace(
        "const ad = '/root/.cli-proxy-api'; const providers = [];",
        "const ad = '/root/.cli-proxy-api'; const providers = [{provider:'openai-codex',account:'System Default',status:'active',successRate:100}];"
    )

with open(p, "w") as f:
    f.write(text)

print("Patched bridge-server.mjs")
'@

$bytes = [System.Text.Encoding]::UTF8.GetBytes($pyScript)
$b64 = [System.Convert]::ToBase64String($bytes)
$chunk = 1800; $first = $true
for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
    $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
    if ($first) { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' > /tmp/patch_bridge.b64" | Out-Null; $first = $false }
    else { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' >> /tmp/patch_bridge.b64" | Out-Null }
}
Invoke-SSHCommand -SessionId $session.SessionId -Command "base64 -d /tmp/patch_bridge.b64 > /tmp/patch_bridge.py && rm /tmp/patch_bridge.b64" | Out-Null

$ws = "/root/.openclaw/workspace-ducy-cto"
$npm = "export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH"

Run "Apply Patch" "python3 /tmp/patch_bridge.py"

# Restart bridge and tunnel
Run "Restart Bridge" "pkill -f 'node scripts/bridge-server.mjs'; sleep 2; cd $ws; $npm; nohup node scripts/bridge-server.mjs > /tmp/bridge.log 2>&1 &"
Run "Check Bridge" "sleep 3; ss -ltnp | grep 8787"

Remove-SSHSession -SessionId $session.SessionId
