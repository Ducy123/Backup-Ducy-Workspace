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
import re
p = "/root/.openclaw/workspace-ducy-cto/scripts/bridge-server.mjs"
with open(p, "r") as f:
    text = f.read()

line = "const body = await new Promise(r => { let b=''; req.on('data',c=>b+=c); req.on('end',()=>r(JSON.parse(b||'{}'))) }).catch(()=>({}));"
text = text.replace(line + "\n\n    " + line, line)

with open(p, "w") as f:
    f.write(text)

print("Duplicates removed from bridge-server.mjs")
'@

$bytes = [System.Text.Encoding]::UTF8.GetBytes($pyScript)
$b64 = [System.Convert]::ToBase64String($bytes)
$chunk = 1800; $first = $true
for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
    $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
    if ($first) { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' > /tmp/patch_dup.b64" | Out-Null; $first = $false }
    else { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' >> /tmp/patch_dup.b64" | Out-Null }
}
Invoke-SSHCommand -SessionId $session.SessionId -Command "base64 -d /tmp/patch_dup.b64 > /tmp/patch_dup.py && rm /tmp/patch_dup.b64" | Out-Null

$ws = "/root/.openclaw/workspace-ducy-cto"
$npm = "export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH"

Run "Fix duplicate declaration" "python3 /tmp/patch_dup.py"
Run "Check Code Result" "grep -A 2 -C 2 -E 'req.method ===.*api/agent-model' $ws/scripts/bridge-server.mjs"

Run "Restart Bridge" "pkill -f 'bridge-server.mjs'; sleep 2; cd $ws; $npm; nohup node scripts/bridge-server.mjs > /tmp/bridge.log 2>&1 & sleep 3; ss -ltnp | grep 8787"

Remove-SSHSession -SessionId $session.SessionId
