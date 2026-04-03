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

# Write python scripts to VPS files first then execute them
# Script 1: read session
Run "Write session reader script" "cat > /tmp/read_session.py << 'PYEOF'
import sys, json

with open('/root/.openclaw/agents/main/sessions/a340cbca-1947-4060-86a7-717c7f51258e.jsonl') as f:
    lines = f.readlines()

count = 0
for line in lines[-300:]:
    try:
        d = json.loads(line)
        role = d.get('role','')
        if role in ('user','assistant'):
            content = d.get('content','')
            if isinstance(content, list):
                text = ' '.join(c.get('text','') for c in content if isinstance(c,dict) and c.get('type')=='text')
            else:
                text = str(content)
            text = text[:300].replace('\n',' ')
            if text.strip():
                print(f'[{role.upper()}] {text}')
                count += 1
    except:
        pass
print(f'--- TOTAL: {count} messages shown ---')
PYEOF
echo written"

Run "Read main session content" "python3 /tmp/read_session.py"

# Script 2: delete jason
Run "Write jason deletion script" "cat > /tmp/delete_jason.py << 'PYEOF'
import json, shutil

path = '/root/.openclaw/openclaw.json'
shutil.copy(path, path + '.bak-rmjason')

with open(path) as f:
    cfg = json.load(f)

cfg['agents']['list'] = [a for a in cfg['agents']['list'] if a.get('id') != 'jason']
cfg['bindings'] = [b for b in cfg['bindings'] if b.get('agentId') != 'jason']

tg_accounts = cfg.get('channels',{}).get('telegram',{}).get('accounts',{})
if 'jason' in tg_accounts:
    del tg_accounts['jason']

with open(path,'w') as f:
    json.dump(cfg, f, indent=2)

print('SUCCESS: jason removed from openclaw.json')
PYEOF
echo written"

Run "Delete Jason from config" "python3 /tmp/delete_jason.py"
Run "Delete Jason dirs" "rm -rf /root/.openclaw/workspace-jason/ /root/.openclaw/agents/jason/; echo Jason_dirs_deleted"

# Restart gateway
Run "Restart gateway" "cd /root; $node $oc gateway restart 2>&1 | tail -3"

# Verify Jason gone
Run "Verify Jason removed" "ls /root/.openclaw/agents/; cat /root/.openclaw/openclaw.json | python3 -c 'import sys,json; d=json.load(sys.stdin); print([a[\"id\"] for a in d[\"agents\"][\"list\"]])'"

# Check cliproxy auths dir
Run "cliproxy auth dir" "ls -la /root/.cli-proxy-api/ 2>/dev/null; find /root/.cli-proxy-api -type f 2>/dev/null | head -20"

Remove-SSHSession -SessionId $session.SessionId
