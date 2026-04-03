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
$node = "/root/.nvm/versions/node/v22.22.1/bin/node"

# Write lib/dashboard-data additions to a temp file on VPS, then append
Run "Write new lib functions" @"
cat > /tmp/new_lib_functions.ts << 'TSEOF'

// ─── TASK 1: LLM Quota ───────────────────────────────────────────────────────
export function getLlmQuota() {
  const cliProxyAuthDir = '/root/.cli-proxy-api';
  const results: {
    provider: string; account: string; status: string;
    tokenFile: string | null; tokenExpiry: string | null;
    errorCount7d: number; successRate: number;
  }[] = [];

  try {
    const authFiles = fs.existsSync(cliProxyAuthDir)
      ? fs.readdirSync(cliProxyAuthDir).filter((f) => f.endsWith('.json'))
      : [];

    for (const authFile of authFiles) {
      const filePath = path.join(cliProxyAuthDir, authFile);
      let tokenExpiry: string | null = null;
      let account = authFile.replace('.json', '');
      try {
        const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        tokenExpiry = raw.expiry || raw.token_expiry || raw.expires_at || null;
        account = raw.email || raw.account || account;
      } catch { /* ignore */ }

      // Count error logs in last 7 days
      const logsDir = path.join(cliProxyAuthDir, 'logs');
      let errorCount = 0;
      if (fs.existsSync(logsDir)) {
        const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
        errorCount = fs.readdirSync(logsDir)
          .filter((f) => f.startsWith('error-') && f.endsWith('.log'))
          .filter((f) => {
            try { return fs.statSync(path.join(logsDir, f)).mtimeMs > sevenDaysAgo; } catch { return false; }
          }).length;
      }

      const successRate = Math.max(0, Math.min(100, 100 - Math.round(errorCount * 2.5)));
      results.push({
        provider: 'antigravity',
        account,
        status: 'active',
        tokenFile: filePath,
        tokenExpiry,
        errorCount7d: errorCount,
        successRate,
      });
    }

    // Also show openai-codex oauth from openclaw config
    const ocConfigPath = path.join(getConfig().paths.openclawRoot, 'openclaw.json');
    if (fs.existsSync(ocConfigPath)) {
      const ocCfg = safeReadJson<{ auth?: { profiles?: Record<string, unknown> } }>(ocConfigPath, {});
      const profiles = ocCfg?.auth?.profiles ?? {};
      for (const [key] of Object.entries(profiles)) {
        if (!key.includes('google') && !results.some((r) => r.provider === key.split(':')[0])) {
          results.push({
            provider: key.split(':')[0],
            account: key,
            status: 'configured',
            tokenFile: null,
            tokenExpiry: null,
            errorCount7d: 0,
            successRate: 95,
          });
        }
      }
    }
  } catch { /* ignore */ }

  return { providers: results };
}

// ─── TASK 3: Set Agent Model ──────────────────────────────────────────────────
export function setAgentModel(agentId: string, model: string): { ok: boolean; error?: string } {
  if (!agentId || !model) return { ok: false, error: 'agentId and model required' };
  const ocConfigPath = path.join(getConfig().paths.openclawRoot, 'openclaw.json');
  try {
    const cfg = safeReadJson<{
      agents?: { defaults?: { model?: { primary?: string } }; list?: { id: string; model?: string | { primary: string } }[] }
    }>(ocConfigPath, {});

    if (!cfg.agents?.list) return { ok: false, error: 'No agents list in config' };

    const agent = cfg.agents.list.find((a) => a.id === agentId);
    if (!agent) {
      // update default
      if (cfg.agents.defaults?.model) {
        cfg.agents.defaults.model.primary = model;
      }
    } else {
      agent.model = model;
    }

    fs.writeFileSync(ocConfigPath, JSON.stringify(cfg, null, 2));

    // Restart gateway
    shell('systemctl restart openclaw-gateway 2>/dev/null || pkill -f openclaw-gateway || true');
    return { ok: true };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}

// ─── TASK 4: Session Log ─────────────────────────────────────────────────────
export function getSessionLog(agentId: string, sessionId?: string) {
  const { paths } = getConfig();
  const agentDir = path.join(paths.agentsRoot, agentId);
  const sessionsDir = path.join(agentDir, 'sessions');

  if (!fs.existsSync(sessionsDir)) return { sessions: [], messages: [] };

  // List sessions
  const sessionFiles = fs.readdirSync(sessionsDir)
    .filter((f) => f.endsWith('.jsonl') && !f.includes('.reset'))
    .map((f) => {
      const fp = path.join(sessionsDir, f);
      const st = statSafe(fp);
      return { sessionId: f.replace('.jsonl', ''), file: fp, size: st?.size ?? 0, mtime: st?.mtime?.toISOString() ?? null };
    })
    .sort((a, b) => (b.mtime ?? '').localeCompare(a.mtime ?? ''));

  if (!sessionId) return { sessions: sessionFiles, messages: [] };

  // Parse messages from the session file
  const sessionFile = path.join(sessionsDir, `${sessionId}.jsonl`);
  if (!fs.existsSync(sessionFile)) return { sessions: sessionFiles, messages: [] };

  const messages: { role: string; content: string; timestamp: string | null; id: string }[] = [];
  try {
    const lines = fs.readFileSync(sessionFile, 'utf8').split('\n').filter(Boolean);
    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        // Support multiple JSONL formats
        const type = entry.type;
        if (type === 'message' || entry.role) {
          const role = entry.role ?? (type === 'message' ? entry.sender ?? 'unknown' : 'unknown');
          let content = entry.content ?? entry.text ?? '';
          if (Array.isArray(content)) {
            content = content.filter((c: { type?: string; text?: string }) => c.type === 'text').map((c: { text?: string }) => c.text ?? '').join('\n');
          }
          if (content) {
            messages.push({
              role,
              content: content.slice(0, 4000),
              timestamp: entry.timestamp ?? null,
              id: entry.id ?? String(messages.length),
            });
          }
        }
      } catch { /* skip malformed line */ }
    }
  } catch { /* ignore read error */ }

  return { sessions: sessionFiles, messages };
}

// ─── TASK 4b: Summarize Session ───────────────────────────────────────────────
export async function summarizeSession(agentId: string, sessionId: string): Promise<{ ok: boolean; summary?: string; error?: string }> {
  if (!agentId || !sessionId) return { ok: false, error: 'agentId and sessionId required' };
  try {
    const { messages } = getSessionLog(agentId, sessionId);
    if (!messages.length) return { ok: false, error: 'No messages found in session' };

    const excerpt = messages
      .slice(-80)
      .map((m) => `[${m.role.toUpperCase()}]: ${m.content.slice(0, 300)}`)
      .join('\n');

    const ocBin = '/root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs';
    const nodeBin = '/root/.nvm/versions/node/v22.22.1/bin/node';
    const prompt = `Summarize this conversation in Vietnamese. Include: main topics, decisions made, pending tasks and key context.

${excerpt}`;

    const result = shell(`${nodeBin} ${ocBin} agent --agent ${agentId} --message ${JSON.stringify(prompt)} --timeout 120 2>&1`);
    return { ok: true, summary: result || 'No summary returned.' };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}
TSEOF
echo 'lib functions written to /tmp'
"@

Remove-SSHSession -SessionId $session.SessionId
