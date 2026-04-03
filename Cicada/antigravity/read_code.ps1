Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    $r.Output | ForEach-Object { Write-Host $_ }
}

$ws = "/root/.openclaw/workspace-ducy-cto"

Run "bridge-server.mjs full" "cat $ws/scripts/bridge-server.mjs"
Run "existing route example" "cat $ws/app/api/overview/route.ts"
Run "lib/bridge.ts" "cat $ws/lib/bridge.ts"
Run "lib/config.ts" "cat $ws/lib/config.ts"
Run "middleware.ts" "cat $ws/middleware.ts"
Run "vercel env" "cat $ws/.vercel.mode2.env | grep -v PASSWORD | grep -v CREDENTIAL"
Run "package.json scripts" "cat $ws/package.json | python3 -m json.tool | grep -A2 'mode2'"

Remove-SSHSession -SessionId $session.SessionId
