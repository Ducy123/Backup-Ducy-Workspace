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

Run "Update React UI" @"
python3 -c "
import sys, re

with open('$ws/components/live-dashboard.tsx', 'r') as f:
    text = f.read()

# 1. Add LLM Quota state
if 'llmQuota' not in text:
    text = text.replace('const [overview, setOverview] = useState(initialOverview);', 
        'const [overview, setOverview] = useState(initialOverview);\n  const [llmQuota, setLlmQuota] = useState<any>(null);\n  const [sessionLog, setSessionLog] = useState<{messages: any[], sessionId: string}|null>(null);')

# 2. Add Quota fetch
if 'fetch(\'/api/llm-quota\'' not in text:
    text = text.replace('fetch(\'/api/health\', { cache: \'no-store\' }),', 
        'fetch(\'/api/health\', { cache: \'no-store\' }),\n          fetch(\'/api/llm-quota\', { cache: \'no-store\' }),')
    
    # Process responses
    text = text.replace('const healthJson = await healthRes.json().catch(() => null);',
        'const healthJson = await healthRes.json().catch(() => null);\n        const quotaRes = overviewRes.clone(); // dirty hack for array destructuring\n        const quotaJson = await fetch(\'/api/llm-quota\').then(r=>r.json()).catch(()=>null);')
    
    text = text.replace('setHealth(healthJson);', 'setHealth(healthJson);\n          if (quotaJson) setLlmQuota(quotaJson);')

# 3. Add Model Switch in agent map
if 'onChange={async (e)' not in text:
    agent_card_old = '''<div className="mt-1 text-sm text-slate-400">{agent.model}</div>'''
    agent_card_new = '''<div className="mt-1 text-sm text-slate-400" onClick={(e) => e.preventDefault()}>
                      <select 
                        defaultValue={agent.model} 
                        onChange={async (e) => {
                          const newModel = e.target.value;
                          await fetch('/api/agent-model', { method: 'POST', body: JSON.stringify({ agentId: agent.id, model: newModel }) });
                          alert('Model updated to ' + newModel);
                        }}
                        className="bg-[#111b33] border border-white/10 text-white rounded p-1 text-xs"
                      >
                        {overview.models.available.map((m: string) => <option key={m} value={m}>{m}</option>)}
                      </select>
                    </div>'''
    text = text.replace(agent_card_old, agent_card_new)

# 4. Add Chat Log fetcher logic inside the component
if 'const showChat =' not in text:
    fetcher_logic = '''
  const showChat = async (agentId: string, e: React.MouseEvent) => {
    e.preventDefault();
    const res = await fetch(`/api/session-log?agentId=\${agentId}`);
    const data = await res.json();
    if (data.sessions && data.sessions.length > 0) {
      const latestSessionId = data.sessions[0].sessionId;
      const res2 = await fetch(`/api/session-log?agentId=\${agentId}&sessionId=\${latestSessionId}`);
      const data2 = await res2.json();
      setSessionLog({ messages: data2.messages || [], sessionId: latestSessionId, agentId } as any);
    } else {
      alert('No sessions found');
    }
  };
  
  const handleSummarize = async () => {
    if (!sessionLog) return;
    alert('Summarizing... this may take a minute');
    const res = await fetch(`/api/summarize-session`, { method: 'POST', body: JSON.stringify({ agentId: (sessionLog as any).agentId, sessionId: sessionLog.sessionId }) });
    const data = await res.json();
    alert(data.summary || data.error || 'Done');
  };
'''
    text = text.replace('const activeAgents = useMemo', fetcher_logic + '\n  const activeAgents = useMemo')

# 5. Add Quota panel to JSX
if 'LLM Quota' not in text:
    quota_panel = '''
      {llmQuota?.providers && (
        <div className="mt-6">
          <Panel title="LLM Quota & Validity" actions={<Badge tone="blue">quota</Badge>}>
            <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
              {llmQuota.providers.map((p: any, i: number) => (
                <div key={i} className="rounded-2xl border border-white/10 bg-[#111b33] p-4 text-sm text-slate-300">
                  <div className="flex justify-between text-white font-semibold mb-2"><span>{p.account.split('@')[0]}</span><StatusDot active={p.status==='active'} /></div>
                  <div className="mb-1 text-xs flex justify-between"><span>Success rate:</span><span>{p.successRate}%</span></div>
                  <div className="w-full bg-slate-700 h-1.5 rounded-full mb-3"><div className={`h-1.5 rounded-full ${p.successRate > 80 ? 'bg-emerald-400' : 'bg-red-400'}`} style={{width: `${p.successRate}%`}}></div></div>
                  <div className="mb-1 text-xs flex justify-between"><span>Validity:</span><span>{p.tokenExpiry ? 'Active' : 'Unknown'}</span></div>
                  <div className="w-full bg-slate-700 h-1.5 rounded-full"><div className="bg-blue-400 h-1.5 rounded-full" style={{width: p.tokenExpiry ? '100%' : '50%'}}></div></div>
                </div>
              ))}
            </div>
          </Panel>
        </div>
      )}
'''
    text = text.replace('</Shell>', quota_panel + '\n    </Shell>')

# 6. Add Chat Log Modal
if 'Chat Log / Memory' not in text:
    chat_modal = '''
      {sessionLog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-6">
          <div className="w-full max-w-4xl max-h-[85vh] flex flex-col rounded-3xl border border-white/10 bg-[#0f172a] shadow-2xl">
            <div className="flex justify-between border-b border-white/10 p-4">
              <h3 className="text-lg font-semibold text-white">Chat Log / Memory</h3>
              <div className="flex gap-2">
                <button onClick={handleSummarize} className="px-4 py-1.5 rounded-full bg-violet-600 hover:bg-violet-500 text-white text-sm">Summarize</button>
                <button onClick={() => setSessionLog(null)} className="px-4 py-1.5 rounded-full bg-white/10 hover:bg-white/20 text-white text-sm">Close</button>
              </div>
            </div>
            <div className="flex-1 overflow-auto p-4 space-y-4">
              {sessionLog.messages.map((m: any, i: number) => (
                <div key={i} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                  <div className={`max-w-[80%] rounded-2xl p-4 text-sm ${m.role === 'user' ? 'bg-blue-600 text-white' : 'bg-[#1e293b] text-slate-200 border border-white/5 whitespace-pre-wrap'}`}>
                    <div className="text-xs opacity-50 mb-1">{m.role.toUpperCase()}</div>
                    {m.content}
                  </div>
                </div>
              ))}
              {sessionLog.messages.length === 0 && <div className="text-center text-slate-500 my-10">No messages in this session.</div>}
            </div>
          </div>
        </div>
      )}
'''
    text = text.replace('</Shell>', chat_modal + '\n    </Shell>')

# 7. Modify Skills short names
text = text.replace('{skill.file}', '{skill.file.split(\"/\").pop().replace(\".md\", \"\").replace(\"-\", \" \")}')
text = text.replace('<div id="skills" className="space-y-2 text-sm">', '<div id="skills" className="flex flex-wrap gap-2 text-sm">')
text = text.replace('className="rounded-2xl border border-white/10 p-3 text-slate-300 break-all"', 'className="rounded-full bg-violet-900/30 border border-violet-500/30 px-3 py-1.5 text-violet-200 capitalize"')

# 8. Add View Log button to Agent card
if 'View Log' not in text:
    btn = '''<button onClick={(e) => showChat(agent.id, e)} className="mt-4 w-full rounded-2xl bg-white/5 py-2 text-center text-xs text-white hover:bg-white/10">View Chat Log</button>'''
    text = text.replace('</div>\n              </Link>', '</div>\n                ' + btn + '\n              </Link>')

with open('$ws/components/live-dashboard.tsx', 'w') as f:
    f.write(text)

print('live-dashboard.tsx rewritten')
"
"@

Run "Run redeploy script" "cd $ws; npm run mode2:vercel-redeploy"

Remove-SSHSession -SessionId $session.SessionId
