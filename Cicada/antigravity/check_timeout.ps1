Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n=== $label ===" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    $r.Output | ForEach-Object { Write-Host $_ }
}

$dir = "/root/.openclaw/workspace-overseer/CLIProxyAPI"

# Start with correct binary
Run "Start cli-proxy-api" "cd $dir; nohup ./bin/cli-proxy-api serve --config config.yaml > /tmp/cliproxy.log 2>&1 &"
Run "Sleep 3" "sleep 3; echo done"
Run "Check port 8317" "ss -ltnp | grep 8317; echo check_done"
Run "Cliproxy log" "tail -30 /tmp/cliproxy.log"
Run "Test API" "curl -s -H 'Authorization: Bearer ducy-cli-proxy-internal-key' http://127.0.0.1:8317/v1/models | head -20"

Remove-SSHSession -SessionId $session.SessionId
