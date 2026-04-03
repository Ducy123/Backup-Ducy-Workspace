Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 60
    $r.Output | ForEach-Object { Write-Host $_ }
}

$oc = "/root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs"
$node = "/root/.nvm/versions/node/v22.22.1/bin/node"

Run "Check current auth profiles" "cat /root/.openclaw/openclaw.json | grep -A 10 'profiles'"

# Start tmux session for login
Run "Kill old tmux" "tmux kill-server 2>/dev/null; echo 'cleared'"
Run "Start login flow" "tmux new-session -d -s login 'export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH; $node $oc models auth login-github-copilot --alias third'"
Run "Wait for prompt" "sleep 3"
Run "Capture tmux" "tmux capture-pane -t login -p"

Remove-SSHSession -SessionId $session.SessionId
