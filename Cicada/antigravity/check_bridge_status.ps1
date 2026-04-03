Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 60
    $r.Output | ForEach-Object { Write-Host $_ }
}

$ws = "/root/.openclaw/workspace-ducy-cto"

Run "Bridge port 8787 status" "ss -ltnp | grep 8787"
Run "Tunnel status" "pgrep -a cloudflared | head -n 2"
Run "Check latest bridge errors" "tail -n 20 /tmp/bridge.log"
Run "Check llm quota logic in bridge" "grep -n -C 5 '/api/llm-quota' $ws/scripts/bridge-server.mjs"

Remove-SSHSession -SessionId $session.SessionId
