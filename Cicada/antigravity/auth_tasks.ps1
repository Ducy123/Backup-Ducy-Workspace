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

# 1. List auth profiles
Run "Auth List" "$node $oc auth list"

# 2. Get auth link to add a new openai-codex
Run "Generate new OpenAI Codex OAuth URL" "$node $oc auth add --provider openai-codex"

Remove-SSHSession -SessionId $session.SessionId
