Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 300
    $r.Output | ForEach-Object { Write-Host $_ }
}

$ws = "/root/.openclaw/workspace-ducy-cto"
$npm = "export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH"

# Fix all 4 routes to be bridge-only proxies (no local function imports)
Run "Fix llm-quota route" @"
cat > $ws/app/api/llm-quota/route.ts << 'EOF'
import { NextResponse } from 'next/server';
import { bridgeFetchJson } from '@/lib/bridge';
export async function GET() {
  const data = await bridgeFetchJson<unknown>('api/llm-quota').catch((e) => ({ error: String(e) }));
  return NextResponse.json(data, { headers: { 'Cache-Control': 'no-store' } });
}
EOF
echo done
"@

Run "Fix agent-model route" @"
cat > $ws/app/api/agent-model/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server';
import { bridgeFetchJson } from '@/lib/bridge';
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const data = await bridgeFetchJson<unknown>('api/agent-model', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  }).catch((e) => ({ error: String(e) }));
  return NextResponse.json(data);
}
EOF
echo done
"@

Run "Fix session-log route" @"
cat > $ws/app/api/session-log/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server';
import { bridgeFetchJson } from '@/lib/bridge';
export async function GET(req: NextRequest) {
  const agentId = req.nextUrl.searchParams.get('agentId') ?? '';
  const sessionId = req.nextUrl.searchParams.get('sessionId') ?? '';
  const data = await bridgeFetchJson<unknown>('api/session-log', {
    search: new URLSearchParams({ agentId, sessionId }),
  }).catch((e) => ({ error: String(e) }));
  return NextResponse.json(data, { headers: { 'Cache-Control': 'no-store' } });
}
EOF
echo done
"@

Run "Fix summarize-session route" @"
cat > $ws/app/api/summarize-session/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server';
import { bridgeFetchJson } from '@/lib/bridge';
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const data = await bridgeFetchJson<unknown>('api/summarize-session', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  }).catch((e) => ({ error: String(e) }));
  return NextResponse.json(data);
}
EOF
echo done
"@

# Commit and redeploy
Run "Git commit fix" "cd $ws; git add app/api/; git commit -m 'fix: make api routes bridge-only proxies (remove missing local imports)'"
Run "Vercel redeploy" "$npm; cd $ws; npm run mode2:vercel-redeploy 2>&1"

Remove-SSHSession -SessionId $session.SessionId
