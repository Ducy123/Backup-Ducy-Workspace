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
$npm = "export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH"

# Wait for tunnel
Run "Wait for tunnel" "sleep 10; cat $ws/ops/generated/quick-tunnel/bridge-public-url.txt 2>/dev/null"
Run "Check cloudflared PID" "pgrep -a cloudflared 2>/dev/null | head -3"
Run "Tunnel log check" "tail -15 /tmp/tunnel.log 2>/dev/null; cat $ws/ops/generated/quick-tunnel/cloudflared.log 2>/dev/null | tail -10"

# Check ephemeral env to see if its updated
Run "Check BRIDGE_BASE_URL" "cat $ws/.vercel.mode2.ephemeral.env 2>/dev/null | grep BRIDGE_BASE_URL"

# Fix page.tsx: wrap getOverviewData in try/catch with empty fallback
Run "Fix page.tsx with try/catch" @"
python3 << 'PYEOF'
p = '/root/.openclaw/workspace-ducy-cto/app/page.tsx'
with open(p) as f: c = f.read()

new_content = '''import { LiveDashboard } from '@/components/live-dashboard';
import { getOverviewData } from '@/lib/dashboard-data';
import type { OverviewData } from '@/lib/dashboard-data';

const EMPTY_OVERVIEW: OverviewData = {
  agents: [], cronJobs: [], skillCatalog: [], recentLogs: [],
  models: { primary: '-', fallbacks: [], available: [] },
  machine: { hostname: 'bridge offline', platform: '-', arch: '-', uptime: 0, loadAvg: [0,0,0], totalMem: 0, freeMem: 0 },
  readiness: { ok: false, counts: { ok: 0, warn: 0, error: 1 }, checks: [{ id: 'bridge', label: 'Bridge connection', level: 'error', detail: 'Cannot reach bridge server. Check VPS tunnel.' }] },
  config: { CONTROL_CENTER_MODE: 'bridge', BRIDGE_BASE_URL: '', BRIDGE_BEARER_TOKEN: '', CONTROL_CENTER_NAME: 'OpenClaw Control Center' },
};

export default async function DashboardPage() {
  let overview: OverviewData;
  try {
    overview = await getOverviewData();
  } catch {
    overview = EMPTY_OVERVIEW;
  }
  return <LiveDashboard initialOverview={overview} />;
}
'''
with open(p, 'w') as f: f.write(new_content)
print('page.tsx fixed with graceful error fallback')
PYEOF
"@

Remove-SSHSession -SessionId $session.SessionId
