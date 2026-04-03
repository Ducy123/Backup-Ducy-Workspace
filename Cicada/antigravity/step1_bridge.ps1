Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 180
    $r.Output | ForEach-Object { Write-Host $_ }
}

function Upload([string]$content, [string]$remote) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
    $b64 = [System.Convert]::ToBase64String($bytes)
    $chunk = 1800
    $first = $true
    for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
        $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
        if ($first) { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' > ${remote}.b64" | Out-Null; $first = $false }
        else { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' >> ${remote}.b64" | Out-Null }
    }
    Invoke-SSHCommand -SessionId $session.SessionId -Command "base64 -d ${remote}.b64 > $remote && rm ${remote}.b64" | Out-Null
    Write-Host "  Uploaded: $remote" -ForegroundColor Gray
}

$ws = "/root/.openclaw/workspace-ducy-cto"

# ------ BRIDGE UPDATE SCRIPT ------
$bridgePy = @'
import sys
WS = '/root/.openclaw/workspace-ducy-cto'
bp = WS + '/scripts/bridge-server.mjs'
with open(bp) as f: c = f.read()
if '/api/llm-quota' in c:
    print('ALREADY DONE'); sys.exit(0)

new_routes = """
  if (req.method === 'GET' && route === '/api/llm-quota') {
    const fs = await import('node:fs'); const fp2 = await import('node:path');
    const ad = '/root/.cli-proxy-api'; const providers = [];
    try {
      for (const af of (fs.existsSync(ad) ? fs.readdirSync(ad).filter(f=>f.endsWith('.json')) : [])) {
        const fp = fp2.join(ad,af); let acc=af.replace('.json',''),exp=null;
        try { const r=JSON.parse(fs.readFileSync(fp,'utf8')); exp=r.expiry||r.expires_at||null; acc=r.email||acc; } catch(e2){}
        const ld=fp2.join(ad,'logs'); let ec=0;
        if(fs.existsSync(ld)){ const a7=Date.now()-7*24*60*60*1000; ec=fs.readdirSync(ld).filter(f=>f.startsWith('error-')&&f.endsWith('.log')).filter(f=>{try{return fs.statSync(fp2.join(ld,f)).mtimeMs>a7;}catch{return false;}}).length; }
        providers.push({provider:'antigravity',account:acc,status:'active',tokenExpiry:exp,errorCount7d:ec,successRate:Math.max(0,100-Math.round(ec*2.5))});
      }
    } catch(e){}
    return sendJson(res,200,{providers});
  }

  if (req.method === 'POST' && route === '/api/agent-model') {
    const fs = await import('node:fs');
    const {agentId,model} = body;
    if (!agentId||!model) return sendJson(res,400,{error:'agentId and model required'});
    const cp = config.OPENCLAW_ROOT+'/openclaw.json';
    try {
      const cfg=JSON.parse(fs.readFileSync(cp,'utf8'));
      const ag=(cfg.agents&&cfg.agents.list||[]).find(a=>a.id===agentId);
      if(ag){ag.model=model;}else if(cfg.agents&&cfg.agents.defaults&&cfg.agents.defaults.model){cfg.agents.defaults.model.primary=model;}
      fs.writeFileSync(cp,JSON.stringify(cfg,null,2));
      try{const {execSync}=await import('node:child_process');execSync('systemctl restart openclaw-gateway 2>/dev/null||true',{timeout:5000});}catch(e2){}
      return sendJson(res,200,{ok:true});
    } catch(e){return sendJson(res,500,{ok:false,error:String(e)});}
  }

  if (req.method === 'GET' && route === '/api/session-log') {
    const fs = await import('node:fs'); const fp2 = await import('node:path');
    const agentId=url.searchParams.get('agentId')||''; const sessionId=url.searchParams.get('sessionId')||'';
    const sd=fp2.join(config.OPENCLAW_ROOT,'agents',agentId,'sessions');
    if(!agentId||!fs.existsSync(sd)) return sendJson(res,200,{sessions:[],messages:[]});
    const sfiles=fs.readdirSync(sd).filter(f=>f.endsWith('.jsonl')&&!f.includes('.reset')).map(f=>{
      const fp=fp2.join(sd,f);const st=fs.statSync(fp);return{sessionId:f.replace('.jsonl',''),size:st.size,mtime:st.mtime.toISOString()};
    }).sort((a,b)=>b.mtime.localeCompare(a.mtime));
    if(!sessionId) return sendJson(res,200,{sessions:sfiles,messages:[]});
    const sf=fp2.join(sd,sessionId+'.jsonl');
    if(!fs.existsSync(sf)) return sendJson(res,200,{sessions:sfiles,messages:[]});
    const msgs=[];
    for(const line of fs.readFileSync(sf,'utf8').split('\\n').filter(Boolean)){
      try{
        const e=JSON.parse(line); const role=e.role||(e.type==='message'?e.sender:null);
        if(!role) continue; const nr=role==='human'?'user':role==='ai'?'assistant':role;
        if(!['user','assistant'].includes(nr)) continue;
        let ct=e.content||e.text||'';
        if(Array.isArray(ct)) ct=ct.filter(c=>c.type==='text').map(c=>c.text||'').join('\\n');
        if(ct&&typeof ct==='string') msgs.push({role:nr,content:ct.slice(0,4000),timestamp:e.timestamp||null,id:e.id||String(msgs.length)});
      } catch(ex){}
    }
    return sendJson(res,200,{sessions:sfiles,messages:msgs});
  }

  if (req.method === 'POST' && route === '/api/summarize-session') {
    const fs=await import('node:fs'); const fp2=await import('node:path');
    const {agentId,sessionId}=body;
    if(!agentId||!sessionId) return sendJson(res,400,{error:'Missing agentId or sessionId'});
    const sf=fp2.join(config.OPENCLAW_ROOT,'agents',agentId,'sessions',sessionId+'.jsonl');
    if(!fs.existsSync(sf)) return sendJson(res,404,{error:'session not found'});
    const lines=fs.readFileSync(sf,'utf8').split('\\n').filter(Boolean);
    const parts=[];
    for(const line of lines.slice(-100)){
      try{
        const e=JSON.parse(line); const role=e.role||(e.type==='message'?e.sender:null);
        if(!role) continue; const nr=role==='human'?'USER':role==='ai'?'ASSISTANT':role.toUpperCase();
        if(!['USER','ASSISTANT'].includes(nr)) continue;
        let ct=e.content||e.text||''; if(Array.isArray(ct)) ct=ct.filter(c=>c.type==='text').map(c=>c.text||'').join(' ');
        if(ct) parts.push('['+nr+'] '+String(ct).slice(0,300));
      } catch(ex){}
    }
    if(!parts.length) return sendJson(res,200,{ok:true,summary:'No messages found to summarize.'});
    const prompt='Summarize this conversation in Vietnamese. Include main topics, decisions, pending tasks and key context:\\n\\n'+parts.slice(-50).join('\\n');
    try{
      const {execSync}=await import('node:child_process');
      const nb='/root/.nvm/versions/node/v22.22.1/bin/node';
      const ob='/root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs';
      const result=execSync(nb+' '+ob+' agent --agent '+agentId+' --message '+JSON.stringify(prompt)+' --timeout 120',{timeout:130000,encoding:'utf8'});
      return sendJson(res,200,{ok:true,summary:result});
    } catch(e){return sendJson(res,500,{ok:false,error:String(e).slice(0,500)});}
  }
"""

pos = c.rfind('return sendJson(res, 404')
if pos < 0: print('ERROR: no 404 marker'); sys.exit(1)
c = c[:pos] + new_routes + c[pos:]
with open(bp,'w') as f: f.write(c)
print('SUCCESS bridge updated')
'@

Upload $bridgePy "/tmp/update_bridge.py"
Run "Run bridge update" "python3 /tmp/update_bridge.py"
Run "Verify bridge" "grep -c 'llm-quota\|agent-model\|session-log\|summarize-session' $ws/scripts/bridge-server.mjs"

Remove-SSHSession -SessionId $session.SessionId
