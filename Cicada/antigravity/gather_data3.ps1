Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n=== $label ===" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    $r.Output | ForEach-Object { Write-Host $_ }
}

# Write all scripts to VPS first, then execute
Run "Write probe scripts" @"
cat > /tmp/probe_session.py << 'PYEOF'
import json
with open('/root/.openclaw/agents/main/sessions/a340cbca-1947-4060-86a7-717c7f51258e.jsonl') as f:
    lines = f.readlines()
for line in lines[:3]:
    try:
        d = json.loads(line)
        print('KEYS:', list(d.keys()))
        if 'type' in d: print('TYPE:', d['type'])
    except: pass
print('TOTAL_LINES:', len(lines))
PYEOF
cat > /tmp/probe_big_session.py << 'PYEOF'
import json
with open('/root/.openclaw/agents/main/sessions/4f1a7df3-8523-43c4-b58c-a415c6dabfd1.jsonl') as f:
    line = f.readline()
d = json.loads(line)
print('KEYS:', list(d.keys()))
if 'content' in d or 'message' in d:
    print('SAMPLE:', str(d)[:200])
PYEOF
echo scripts_written
"@

Run "Probe session format" "python3 /tmp/probe_session.py 2>/dev/null"
Run "Probe big session" "python3 /tmp/probe_big_session.py 2>/dev/null"
Run "Agents remaining" "ls /root/.openclaw/agents/"
Run "Cliproxy error 403 details" "cat /root/.cli-proxy-api/logs/error-v1-chat-completions-2026-03-30T073957-948ce328.log 2>/dev/null | head -20"

Remove-SSHSession -SessionId $session.SessionId
