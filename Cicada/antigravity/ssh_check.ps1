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

# Xem models.json cua main agent
Run "main agent models.json" "cat /root/.openclaw/agents/main/agent/models.json"

# FIX 1: Update models.json cua main agent sang google-gemini-cli
Write-Host "`n=== FIX: Updating main agent models.json ===" -ForegroundColor Yellow
$r = Invoke-SSHCommand -SessionId $session.SessionId -Command @'
cat > /root/.openclaw/agents/main/agent/models.json << 'EOF'
{
  "version": 1,
  "primary": "google-gemini-cli/gemini-3.1-pro-preview"
}
EOF
echo "Done - main models.json updated"
cat /root/.openclaw/agents/main/agent/models.json
'@
$r.Output | ForEach-Object { Write-Host $_ -ForegroundColor Green }

# FIX 2: Update openclaw.json - thay the openai-codex/gpt-5.4 trong agents list
Write-Host "`n=== FIX: Updating openclaw.json agents model ===" -ForegroundColor Yellow
$r2 = Invoke-SSHCommand -SessionId $session.SessionId -Command @'
python3 -c "
import json, shutil, os

path = '/root/.openclaw/openclaw.json'
shutil.copy(path, path + '.bak-fix')

with open(path) as f:
    cfg = json.load(f)

changed = []
for agent in cfg.get('agents', {}).get('list', []):
    if agent.get('model') == 'openai-codex/gpt-5.4':
        agent['model'] = 'google-gemini-cli/gemini-3.1-pro-preview'
        changed.append(agent['id'])

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)

print('Updated agents:', changed)
"
'@
$r2.Output | ForEach-Object { Write-Host $_ -ForegroundColor Green }

# Verify
Run "Verify - openclaw.json agents models" "cat /root/.openclaw/openclaw.json | python3 -m json.tool | grep -E 'model|primary' | grep -v '//' | head -20"

# Restart gateway
Write-Host "`n=== Restarting gateway ===" -ForegroundColor Yellow
$r3 = Invoke-SSHCommand -SessionId $session.SessionId -Command "cd /root && $node $oc gateway restart 2>&1 | tail -5"
$r3.Output | ForEach-Object { Write-Host $_ -ForegroundColor Green }

# Final check
Run "Final models status - main" "sleep 3 && cd /root && $node $oc models status --agent main 2>&1 | grep -v 'codex-list\|Doctor\|WARNING\|groupPolicy\|allowFrom\|silently\|sender\|groupAllowFrom'"
Run "Final models status - overseer" "cd /root && $node $oc models status --agent overseer 2>&1 | grep -E 'Default|Provider|ok|expires|error'"

Remove-SSHSession -SessionId $session.SessionId
