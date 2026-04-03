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
$npm = "export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH"

Run "Kill listening process" "fuser -k 8787/tcp || kill -9 `$(lsof -t -i:8787) || true"
Run "Clear log and Start Bridge" "cd $ws; $npm; node scripts/bridge-server.mjs > /tmp/bridge.log 2>&1 & sleep 3"
Run "Verify listening" "ss -ltnp | grep 8787"
Run "Tail new log" "cat /tmp/bridge.log"

Remove-SSHSession -SessionId $session.SessionId
