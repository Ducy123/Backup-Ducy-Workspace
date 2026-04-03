Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 120
    $r.Output | ForEach-Object { Write-Host $_ }
}

$ws = "/root/.openclaw/workspace-ducy-cto"

Run "Append to lib/dashboard-data.ts" "cat /tmp/new_lib_functions.ts >> $ws/lib/dashboard-data.ts"

# Now we need to inject the bridge routes into bridge-server.mjs
# The bridge handles /api/health, /api/overview, etc.
# We will use python to parse and insert the new routes.
Run "Update bridge-server.mjs" @"
python3 -c "
import sys, re

with open('$ws/scripts/bridge-server.mjs', 'r') as f:
    content = f.read()

new_routes = '''
  if (req.method === 'GET' && route === '/api/llm-quota') {
    return sendJson(res, 200, await import('../lib/dashboard-data.ts').then(m => m.getLlmQuota()));
  }

  if (req.method === 'POST' && route === '/api/agent-model') {
    return sendJson(res, 200, await import('../lib/dashboard-data.ts').then(m => m.setAgentModel(body.agentId, body.model)));
  }

  if (req.method === 'GET' && route === '/api/session-log') {
    const agentId = url.searchParams.get('agentId') || '';
    const sessionId = url.searchParams.get('sessionId') || '';
    return sendJson(res, 200, await import('../lib/dashboard-data.ts').then(m => m.getSessionLog(agentId, sessionId)));
  }

  if (req.method === 'POST' && route === '/api/summarize-session') {
    return sendJson(res, 200, await import('../lib/dashboard-data.ts').then(m => m.summarizeSession(body.agentId, body.sessionId)));
  }
'''

if '/api/llm-quota' not in content:
    # Insert before the catch-all 404
    insert_pos = content.rfind('return sendJson(res, 404')
    if insert_pos > 0:
        content = content[:insert_pos] + new_routes + content[insert_pos:]
        with open('$ws/scripts/bridge-server.mjs', 'w') as f:
            f.write(content)
        print('bridge-server.mjs updated')
    else:
        print('FAILED to find insert pos')
else:
    print('bridge-server.mjs already updated')
"
"@

Remove-SSHSession -SessionId $session.SessionId
