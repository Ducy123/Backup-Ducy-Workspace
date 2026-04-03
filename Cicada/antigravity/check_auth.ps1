Import-Module Posh-SSH

$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($cmd) {
    Write-Host "`n=== Run: $cmd ===" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd
    $r.Output | ForEach-Object { Write-Host $_ }
}

Run "cd /root/.openclaw/workspace-ducy-cto && cat .vercel.mode2.env .vercel.mode2.ephemeral.env .env .env.local ops/generated/mode2-cutover-bundle.env 2>/dev/null | grep -iE 'PASS|AUTH|USER|BASIC|CREDENTIAL'"

Remove-SSHSession -SessionId $session.SessionId
