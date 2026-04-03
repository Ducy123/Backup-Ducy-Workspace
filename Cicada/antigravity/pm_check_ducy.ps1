Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($cmd) {
    Write-Host "`n=== Run: $cmd ===" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 120
    $r.Output | ForEach-Object { Write-Host $_ }
}

$node = "/root/.nvm/versions/node/v22.22.1/bin/node"
$oc = "/root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs"

$cmd = "$node $oc agent --agent ducy-cto --message 'Project Manager checking in. What is the status of the web dashboard? Next.js app is in your workspace. 1. What is the completion %? 2. What Layer 1/2 features are missing? 3. What is the blocker preventing Vercel (Mode 2) deployment? Please report and execute the next steps!' --timeout 120 2>&1"
Run "cd /root && $cmd"

Remove-SSHSession -SessionId $session.SessionId
