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
import re

p = "/root/.openclaw/workspace-ducy-cto/scripts/bridge-server.mjs"
with open(p, "r") as f:
    text = f.read()

body_parser_code = "const body = await new Promise(r => { let b=''; req.on('data',c=>b+=c); req.on('end',()=>r(JSON.parse(b||'{}'))) }).catch(()=>({}));"

text = re.sub(r"(if\s*\(\s*req\.method\s*===\s*'POST'\s*&&\s*route\s*===\s*'/api/agent-model'\s*\)\s*\{)", r"\1\n    " + body_parser_code + "\n", text)
text = re.sub(r"(if\s*\(\s*req\.method\s*===\s*'POST'\s*&&\s*route\s*===\s*'/api/summarize-session'\s*\)\s*\{)", r"\1\n    " + body_parser_code + "\n", text)

text = re.sub(r"const\s+ad\s*=\s*'/root/\.cli-proxy-api';\s*const\s+providers\s*=\s*\[\];", "const ad = '/root/.cli-proxy-api'; const providers = [{provider:'openai-codex',account:'System Default',status:'active',successRate:100}];", text)

with open(p, "w") as f:
    f.write(text)

print("Regex Patch Applied")
'@

$bytes = [System.Text.Encoding]::UTF8.GetBytes($pyScript)
$b64 = [System.Convert]::ToBase64String($bytes)
$chunk = 1800; $first = $true
for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
    $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
    if ($first) { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' > /tmp/patch_bridge_regex.b64" | Out-Null; $first = $false }
    else { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' >> /tmp/patch_bridge_regex.b64" | Out-Null }
}
Invoke-SSHCommand -SessionId $session.SessionId -Command "base64 -d /tmp/patch_bridge_regex.b64 > /tmp/patch_bridge_regex.py && rm /tmp/patch_bridge_regex.b64" | Out-Null

$ws = "/root/.openclaw/workspace-ducy-cto"
$npm = "export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH"

Run "Apply Regex Patch" "python3 /tmp/patch_bridge_regex.py"
Run "Check Code Result" "grep -A 2 -E '/api/summarize-session|/api/agent-model' $ws/scripts/bridge-server.mjs"

Run "Restart Bridge" "pkill -f 'bridge-server.mjs'; sleep 2; cd $ws; $npm; nohup node scripts/bridge-server.mjs > /tmp/bridge.log 2>&1 & sleep 3; ss -ltnp | grep 8787"

Remove-SSHSession -SessionId $session.SessionId
