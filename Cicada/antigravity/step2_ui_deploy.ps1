Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 300
    $r.Output | ForEach-Object { Write-Host $_ }
}

function Upload([string]$content, [string]$remote) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
    $b64 = [System.Convert]::ToBase64String($bytes)
    $chunk = 1800; $first = $true
    for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
        $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
        if ($first) { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' > ${remote}.b64" | Out-Null; $first = $false }
        else { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' >> ${remote}.b64" | Out-Null }
    }
    Invoke-SSHCommand -SessionId $session.SessionId -Command "base64 -d ${remote}.b64 > $remote && rm ${remote}.b64" | Out-Null
    Write-Host "  Uploaded: $remote" -ForegroundColor Gray
}

$ws = "/root/.openclaw/workspace-ducy-cto"

# Full new live-dashboard.tsx
$dashboard = @'
"use client";
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { Badge, Panel, Shell, StatCard } from '@/components/ui';
import type { OverviewData } from '@/lib/dashboard-data';

function formatTime(v: string | null | undefined) {
  if (!v) return '-';
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? v : d.toLocaleString();
}

function StatusDot({ active }: { active: boolean }) {
  return <span className={`inline-block h-2.5 w-2.5 rounded-full ${active ? 'bg-emerald-400 shadow-[0_0_10px_rgba(16,185,129,0.7)]' : 'bg-slate-600'}`} />;
}

function ProgressBar({ value, color = 'emerald' }: { value: number; color?: string }) {
  const cls = color === 'blue' ? 'bg-blue-400' : value > 80 ? 'bg-emerald-400' : value > 40 ? 'bg-amber-400' : 'bg-red-500';
  return (
    <div className="w-full bg-slate-800 h-2 rounded-full overflow-hidden">
      <div className={`h-2 rounded-full transition-all ${cls}`} style={{ width: `${Math.max(2, value)}%` }} />
    </div>
  );
}

function skillLabel(file: string) {
  const parts = file.split('/');
  const name = parts[parts.length - 2] || parts[parts.length - 1].replace('.md', '');
  return name.split('-').map((w: string) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}

type LlmProvider = { provider: string; account: string; status: string; tokenExpiry: string | null; errorCount7d: number; successRate: number };
type SessionMsg = { role: string; content: string; timestamp: string | null; id: string };

export function LiveDashboard({ initialOverview }: { initialOverview: OverviewData }) {
  const [overview, setOverview] = useState(initialOverview);
  const [health, setHealth] = useState<any>(null);
  const [llmQuota, setLlmQuota] = useState<{ providers: LlmProvider[] } | null>(null);
  const [lastUpdated, setLastUpdated] = useState(new Date().toISOString());
  const [sessionModal, setSessionModal] = useState<{ agentId: string; sessionId: string; messages: SessionMsg[] } | null>(null);
  const [summarizing, setSummarizing] = useState(false);
  const [summary, setSummary] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const pull = async () => {
      try {
        const [ovRes, hRes, qRes] = await Promise.all([
          fetch('/api/overview', { cache: 'no-store' }),
          fetch('/api/health', { cache: 'no-store' }),
          fetch('/api/llm-quota', { cache: 'no-store' }),
        ]);
        const [ov, h, q] = await Promise.all([ovRes.json(), hRes.json().catch(() => null), qRes.json().catch(() => null)]);
        if (!cancelled) { setOverview(ov); setHealth(h); if (q?.providers) setLlmQuota(q); setLastUpdated(new Date().toISOString()); }
      } catch { /* keep last state */ }
    };
    pull();
    const id = setInterval(pull, 10_000);
    return () => { cancelled = true; clearInterval(id); };
  }, []);

  const activeAgents = useMemo(() => overview.agents.filter(a => a.heartbeatActive).length, [overview.agents]);
  const latestRun = useMemo(() => overview.cronJobs.map((j: any) => j.lastRunAt).filter(Boolean).sort().reverse()[0] ?? null, [overview.cronJobs]);

  const openChat = async (agentId: string, e: React.MouseEvent) => {
    e.preventDefault();
    const d = await fetch(`/api/session-log?agentId=${agentId}`).then(r => r.json()).catch(() => null);
    if (!d?.sessions?.length) { alert('No sessions for ' + agentId); return; }
    const sid = d.sessions[0].sessionId;
    const d2 = await fetch(`/api/session-log?agentId=${agentId}&sessionId=${sid}`).then(r => r.json()).catch(() => null);
    setSessionModal({ agentId, sessionId: sid, messages: d2?.messages ?? [] });
    setSummary(null);
  };

  const handleSummarize = async () => {
    if (!sessionModal) return;
    setSummarizing(true);
    const d = await fetch('/api/summarize-session', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ agentId: sessionModal.agentId, sessionId: sessionModal.sessionId }) }).then(r => r.json()).catch(e => ({ error: String(e) }));
    setSummarizing(false);
    setSummary(d.summary ?? d.error ?? 'No result.');
  };

  const switchModel = async (agentId: string, model: string) => {
    const r = await fetch('/api/agent-model', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ agentId, model }) }).then(r => r.json()).catch(e => ({ error: String(e) }));
    if (r.ok) alert(`✓ ${agentId} switched to ${model}`);
    else alert('Error: ' + (r.error ?? 'unknown'));
  };

  return (
    <Shell title="OpenClaw Control Center">
      {/* Stats */}
      <div id="overview" className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Agents" value={overview.agents.length} hint={`${activeAgents} active`} />
        <StatCard label="Cron Jobs" value={overview.cronJobs.length} hint={latestRun ? `Last: ${formatTime(latestRun)}` : 'No runs'} />
        <StatCard label="Models" value={overview.models.available.length || 1} hint={`Primary: ${overview.models.primary}`} />
        <StatCard label="Refreshed" value={new Date(lastUpdated).toLocaleTimeString()} hint="Every 10s" />
      </div>

      {/* Agents + Health */}
      <div className="mt-6 grid gap-6 xl:grid-cols-[1.4fr_0.6fr]">
        <Panel title="Agents" actions={<Badge tone="green">live</Badge>}>
          <div className="grid gap-4 md:grid-cols-2">
            {overview.agents.map(agent => (
              <Link key={agent.id} href={`/agents/${agent.id}`} className="flex flex-col rounded-3xl border border-white/10 bg-[#111b33] p-4 transition hover:border-emerald-400/30 hover:bg-[#17223f]">
                <div className="flex items-start justify-between gap-2">
                  <div className="flex-1 min-w-0">
                    <div className="text-base font-semibold text-white truncate">{agent.id}</div>
                    {/* Task 3: LLM switcher */}
                    <div onClick={e => e.preventDefault()} className="mt-1.5">
                      <select
                        defaultValue={agent.model}
                        onChange={e => { void switchModel(agent.id, e.target.value); }}
                        className="w-full bg-[#0d1526] border border-white/10 text-blue-300 text-xs rounded-lg px-2 py-1 outline-none cursor-pointer"
                      >
                        <option value={agent.model}>{agent.model} ★</option>
                        {overview.models.available.filter((m: string) => m !== agent.model).map((m: string) => (
                          <option key={m} value={m}>{m}</option>
                        ))}
                      </select>
                    </div>
                  </div>
                  <div className="flex flex-col items-end gap-1 text-xs text-slate-400">
                    <StatusDot active={agent.heartbeatActive} />
                    <span>{agent.heartbeatActive ? 'active' : 'stale'}</span>
                  </div>
                </div>
                <div className="mt-3 grid grid-cols-2 gap-2 text-xs text-slate-300">
                  <div className="rounded-xl bg-black/20 p-2">💬 {agent.sessionCount} sessions</div>
                  <div className="rounded-xl bg-black/20 p-2">🔧 {agent.skills.length} skills</div>
                  <div className="rounded-xl bg-black/20 p-2 col-span-2 truncate">⏱ {formatTime(agent.heartbeatMtime)}</div>
                </div>
                {/* Task 4: Chat Log button */}
                <button onClick={e => { void openChat(agent.id, e); }} className="mt-3 rounded-xl bg-violet-900/30 hover:bg-violet-800/50 border border-violet-500/20 py-1.5 text-center text-xs text-violet-300 transition">
                  💬 View Chat Log
                </button>
              </Link>
            ))}
          </div>
        </Panel>

        <Panel title="System Health" actions={<Badge tone={health?.ok ? 'green' : 'amber'}>{health?.ok ? 'healthy' : 'checking'}</Badge>}>
          <div className="space-y-2 text-sm text-slate-300">
            <div className="rounded-2xl border border-white/10 p-3">Mode: <span className="text-white">{overview.config.CONTROL_CENTER_MODE}</span></div>
            <div className="rounded-2xl border border-white/10 p-3 break-all text-xs">Bridge: <span className="text-blue-300">{overview.config.BRIDGE_BASE_URL || '-'}</span></div>
            <div className="rounded-2xl border border-white/10 p-3">Checks: <span className="text-white">{overview.readiness.counts.ok}✓ {overview.readiness.counts.warn}⚠ {overview.readiness.counts.error}✗</span></div>
            <div className="rounded-2xl border border-white/10 p-3">Host: <span className="text-white">{overview.machine.hostname}</span></div>
          </div>
        </Panel>
      </div>

      {/* Task 1: LLM Quota Panel */}
      {llmQuota?.providers && llmQuota.providers.length > 0 && (
        <div className="mt-6">
          <Panel title="LLM Quota & Validity" actions={<Badge tone="blue">live</Badge>}>
            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
              {llmQuota.providers.map((p, i) => (
                <div key={i} className="rounded-2xl border border-white/10 bg-[#111b33] p-4">
                  <div className="flex items-center justify-between mb-3">
                    <span className="text-white font-semibold text-sm truncate">{p.account.split('@')[0]}</span>
                    <div className="flex items-center gap-1.5"><StatusDot active={p.status === 'active'} /><span className="text-xs text-slate-400">{p.provider}</span></div>
                  </div>
                  <div className="space-y-3">
                    <div>
                      <div className="flex justify-between text-xs text-slate-400 mb-1"><span>Success rate (7d)</span><span className="text-white font-medium">{p.successRate}%</span></div>
                      <ProgressBar value={p.successRate} />
                    </div>
                    <div>
                      <div className="flex justify-between text-xs text-slate-400 mb-1"><span>Token validity</span><span className="text-white">{p.tokenExpiry ? 'Active ✓' : 'Unknown'}</span></div>
                      <ProgressBar value={p.tokenExpiry ? 100 : 50} color="blue" />
                    </div>
                    {p.errorCount7d > 0 && <div className="text-xs text-red-400">⚠ {p.errorCount7d} errors last 7d</div>}
                  </div>
                </div>
              ))}
            </div>
          </Panel>
        </div>
      )}

      {/* Cron + Skills (Task 2: compact tags) + Models */}
      <div className="mt-6 grid gap-6 xl:grid-cols-3">
        <Panel title="Cron & Runtime">
          <div className="space-y-2 text-sm" id="cron-runtime">
            {overview.cronJobs.slice(0, 8).map((job: any) => (
              <div key={job.id || job.name} className="rounded-2xl border border-white/10 p-3">
                <div className="text-slate-100">{job.name || job.id}</div>
                <div className="mt-1 text-xs text-slate-500">last: {formatTime(job.lastRunAt)}</div>
              </div>
            ))}
          </div>
        </Panel>

        <Panel title="Skills" actions={<Badge tone="cyan">{overview.skillCatalog.length}</Badge>}>
          <div id="skills" className="flex flex-wrap gap-2">
            {overview.skillCatalog.map(skill => (
              <span key={skill.file} className="rounded-full bg-violet-900/30 border border-violet-500/30 px-3 py-1.5 text-xs text-violet-200 hover:bg-violet-800/40 transition cursor-default">
                {skillLabel(skill.file)}
              </span>
            ))}
          </div>
        </Panel>

        <Panel title="Models" actions={<Badge tone="violet">routing</Badge>}>
          <div className="space-y-3 text-sm text-slate-300" id="models">
            <div><div className="mb-1 text-xs uppercase tracking-widest text-slate-500">Primary</div><Badge tone="cyan">{overview.models.primary}</Badge></div>
            <div><div className="mb-1 text-xs uppercase tracking-widest text-slate-500">Available</div><div className="flex flex-wrap gap-1.5 mt-1">{overview.models.available.map((m: string) => <Badge key={m} tone="green">{m}</Badge>)}</div></div>
            {overview.models.fallbacks.length > 0 && <div><div className="mb-1 text-xs uppercase tracking-widest text-slate-500">Fallbacks</div><div className="flex flex-wrap gap-1.5">{overview.models.fallbacks.map((m: string) => <Badge key={m} tone="amber">{m}</Badge>)}</div></div>}
          </div>
        </Panel>
      </div>

      {/* Health detail + Live feed */}
      <div className="mt-6 grid gap-6 xl:grid-cols-2">
        <Panel title="Health Detail">
          <div id="system-health" className="space-y-2 text-sm text-slate-300">
            {overview.readiness.checks.map(check => (
              <div key={check.id} className="rounded-2xl border border-white/10 p-3">
                <div className="flex items-center justify-between"><span className="text-slate-100">{check.label}</span><Badge tone={check.level === 'ok' ? 'green' : check.level === 'warn' ? 'amber' : 'red'}>{check.level}</Badge></div>
                <div className="mt-1 text-xs text-slate-500">{check.detail}</div>
              </div>
            ))}
          </div>
        </Panel>
        <Panel title="Live Feed" actions={<Badge tone="green">tail</Badge>}>
          <div id="live-feed" className="space-y-2">
            {overview.recentLogs.map(e => (
              <div key={e.id} className="rounded-xl border border-white/10 bg-black/20 p-2 font-mono text-xs text-emerald-100">{e.line}</div>
            ))}
          </div>
        </Panel>
      </div>

      {/* Task 4: Chat Log Modal */}
      {sessionModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4" onClick={() => setSessionModal(null)}>
          <div className="w-full max-w-4xl max-h-[88vh] flex flex-col rounded-3xl border border-white/10 bg-[#0f172a] shadow-2xl" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between border-b border-white/10 p-4">
              <div>
                <h3 className="text-lg font-semibold text-white">Chat Log — {sessionModal.agentId}</h3>
                <p className="text-xs text-slate-500 mt-0.5">{sessionModal.messages.length} messages · session {sessionModal.sessionId.slice(0, 8)}…</p>
              </div>
              <div className="flex gap-2">
                <button onClick={handleSummarize} disabled={summarizing} className="px-4 py-1.5 rounded-full bg-violet-600 hover:bg-violet-500 disabled:opacity-50 text-white text-sm transition">
                  {summarizing ? '⏳ Summarizing…' : '🧠 Summarize Memory'}
                </button>
                <button onClick={() => { setSessionModal(null); setSummary(null); }} className="px-4 py-1.5 rounded-full bg-white/10 hover:bg-white/20 text-white text-sm transition">✕</button>
              </div>
            </div>
            {summary && (
              <div className="border-b border-violet-500/30 bg-violet-900/20 p-4">
                <div className="text-xs text-violet-400 font-semibold mb-2">🧠 SUMMARY</div>
                <div className="text-sm text-violet-100 whitespace-pre-wrap">{summary}</div>
              </div>
            )}
            <div className="flex-1 overflow-auto p-4 space-y-3">
              {sessionModal.messages.map((m, i) => (
                <div key={i} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                  <div className={`max-w-[80%] rounded-2xl p-3 text-sm ${m.role === 'user' ? 'bg-blue-600 text-white' : 'bg-[#1e293b] text-slate-200 border border-white/5 whitespace-pre-wrap'}`}>
                    <div className="text-xs opacity-40 mb-1">{m.role.toUpperCase()}{m.timestamp ? ` · ${new Date(m.timestamp).toLocaleTimeString()}` : ''}</div>
                    {m.content}
                  </div>
                </div>
              ))}
              {!sessionModal.messages.length && <div className="text-center text-slate-500 py-16">No messages parsed in this session.</div>}
            </div>
          </div>
        </div>
      )}
    </Shell>
  );
}
'@

Upload $dashboard "$ws/components/live-dashboard.tsx"
Run "Verify UI file size" "wc -l $ws/components/live-dashboard.tsx"

# Restart bridge with new routes
Run "Restart bridge" "pkill -f 'node.*bridge-server' 2>/dev/null; sleep 1; export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH; cd $ws; nohup node scripts/bridge-server.mjs > /tmp/bridge.log 2>&1 & sleep 2; echo 'Bridge PID:' `$!"

# Git commit
Run "Git commit" "cd $ws; git add -A; git commit -m 'feat: LLM quota panel, model switcher, skill tags, chat log viewer with summarize'"

# Deploy to Vercel
Run "Vercel redeploy" "export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH; cd $ws; npm run mode2:vercel-redeploy 2>&1"

Remove-SSHSession -SessionId $session.SessionId
