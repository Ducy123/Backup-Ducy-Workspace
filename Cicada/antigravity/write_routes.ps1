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
$npm = "/root/.nvm/versions/node/v22.22.1/bin/npm"

# ========== TASK 1: LLM Quota - Next.js route ==========
Run "mkdir llm-quota" "mkdir -p $ws/app/api/llm-quota $ws/app/api/agent-model $ws/app/api/session-log $ws/app/api/summarize-session"

Run "Write llm-quota route" @"
cat > $ws/app/api/llm-quota/route.ts << 'TSEOF'
import { NextResponse } from 'next/server';
import { isBridgeMode, bridgeFetchJson } from '@/lib/bridge';
import { getLlmQuota } from '@/lib/dashboard-data';

export async function GET() {
  if (isBridgeMode()) {
    const data = await bridgeFetchJson<unknown>('api/llm-quota').catch((e) => ({ error: String(e) }));
    return NextResponse.json(data, { headers: { 'Cache-Control': 'no-store' } });
  }
  return NextResponse.json(getLlmQuota(), { headers: { 'Cache-Control': 'no-store' } });
}
TSEOF
echo 'llm-quota route written'
"@

# ========== TASK 3: Agent Model Switch - Next.js route ==========
Run "Write agent-model route" @"
cat > $ws/app/api/agent-model/route.ts << 'TSEOF'
import { NextRequest, NextResponse } from 'next/server';
import { isBridgeMode, bridgeFetchJson } from '@/lib/bridge';
import { setAgentModel } from '@/lib/dashboard-data';

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  if (isBridgeMode()) {
    const data = await bridgeFetchJson<unknown>('api/agent-model', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }).catch((e) => ({ error: String(e) }));
    return NextResponse.json(data);
  }
  const result = setAgentModel(body.agentId, body.model);
  return NextResponse.json(result);
}
TSEOF
echo 'agent-model route written'
"@

# ========== TASK 4a: Session Log - Next.js route ==========
Run "Write session-log route" @"
cat > $ws/app/api/session-log/route.ts << 'TSEOF'
import { NextRequest, NextResponse } from 'next/server';
import { isBridgeMode, bridgeFetchJson } from '@/lib/bridge';
import { getSessionLog } from '@/lib/dashboard-data';

export async function GET(req: NextRequest) {
  const agentId = req.nextUrl.searchParams.get('agentId') ?? '';
  const sessionId = req.nextUrl.searchParams.get('sessionId') ?? '';
  if (isBridgeMode()) {
    const data = await bridgeFetchJson<unknown>('api/session-log', {
      search: new URLSearchParams({ agentId, sessionId }),
    }).catch((e) => ({ error: String(e) }));
    return NextResponse.json(data, { headers: { 'Cache-Control': 'no-store' } });
  }
  return NextResponse.json(getSessionLog(agentId, sessionId), { headers: { 'Cache-Control': 'no-store' } });
}
TSEOF
echo 'session-log route written'
"@

# ========== TASK 4b: Summarize Session - Next.js route ==========
Run "Write summarize-session route" @"
cat > $ws/app/api/summarize-session/route.ts << 'TSEOF'
import { NextRequest, NextResponse } from 'next/server';
import { isBridgeMode, bridgeFetchJson } from '@/lib/bridge';
import { summarizeSession } from '@/lib/dashboard-data';

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  if (isBridgeMode()) {
    const data = await bridgeFetchJson<unknown>('api/summarize-session', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }).catch((e) => ({ error: String(e) }));
    return NextResponse.json(data);
  }
  const result = await summarizeSession(body.agentId, body.sessionId);
  return NextResponse.json(result);
}
TSEOF
echo 'summarize-session route written'
"@

Remove-SSHSession -SessionId $session.SessionId
Write-Host "`nRoutes written - now writing lib functions and bridge endpoints" -ForegroundColor Green
