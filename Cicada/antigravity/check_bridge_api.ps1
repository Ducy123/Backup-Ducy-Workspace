Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($cmd) {
    Write-Host "`n=== $cmd ===" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    $r.Output | ForEach-Object { Write-Host $_ }
}

# Check bridge server is running
Run "ss -ltnp | grep 8787"

# What does the bridge expose?
Run "cat /root/.openclaw/workspace-ducy-cto/scripts/bridge-server.mjs | head -150"

# Check /api routes in the Next.js app
Run "find /root/.openclaw/workspace-ducy-cto/app/api -type f"

# Check the lib/data.ts to see what data is fetched
Run "cat /root/.openclaw/workspace-ducy-cto/lib/data.ts"

# Check current env - bridge URL wired up?
Run "cat /root/.openclaw/workspace-ducy-cto/.env.local | grep -v PASSWORD | grep -v CREDENTIAL"
Run "cat /root/.openclaw/workspace-ducy-cto/.vercel.mode2.env | grep -v PASSWORD | grep -v CREDENTIAL"

# Quick test of the bridge API locally
Run "curl -s http://127.0.0.1:8787/bridge/control-center/api/health 2>/dev/null | head -20"
Run "curl -s http://127.0.0.1:8787/bridge/control-center/api/overview 2>/dev/null | head -60"

Remove-SSHSession -SessionId $session.SessionId
