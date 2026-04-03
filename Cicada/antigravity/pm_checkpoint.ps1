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
$ts = Get-Date -Format "HH:mm:ss"
Write-Host "=== PM Checkpoint @ $ts ===" -ForegroundColor Magenta

Run "Session size & lock" "ls -lh /root/.openclaw/agents/ducy-cto/sessions/*.jsonl 2>/dev/null | tail -4"
Run "Recent file changes" "find $ws -newer /root/.openclaw/workspace-ducy-cto/package-lock.json -type f 2>/dev/null | grep -v node_modules | grep -v .next | grep -v .git | grep -v tmux"
Run "All API routes" "find $ws/app/api -type f 2>/dev/null"
Run "Git log" "cd $ws; git log --oneline -5 2>/dev/null"

# Check TASK 1
$t1 = (Invoke-SSHCommand -SessionId $session.SessionId -Command "test -f $ws/app/api/llm-quota/route.ts && echo DONE || echo PENDING").Output
Write-Host "TASK 1 (LLM Quota):  $t1" -ForegroundColor $(if ($t1 -match "DONE") { "Green" } else { "Red" })

# Check TASK 2
$t2 = (Invoke-SSHCommand -SessionId $session.SessionId -Command "grep -r 'chip\|tag\|skill' $ws/components/ui.tsx 2>/dev/null | grep -i 'shortened\|compact\|short' | wc -l").Output
Write-Host "TASK 2 (Skills UI):  check manually" -ForegroundColor Yellow

# Check TASK 3
$t3 = (Invoke-SSHCommand -SessionId $session.SessionId -Command "test -f $ws/app/api/agent-model/route.ts && echo DONE || echo PENDING").Output
Write-Host "TASK 3 (LLM Switch): $t3" -ForegroundColor $(if ($t3 -match "DONE") { "Green" } else { "Red" })

# Check TASK 4
$t4 = (Invoke-SSHCommand -SessionId $session.SessionId -Command "test -f $ws/app/api/session-log/route.ts && echo DONE || echo PENDING").Output
Write-Host "TASK 4 (Chat Log):   $t4" -ForegroundColor $(if ($t4 -match "DONE") { "Green" } else { "Red" })

Remove-SSHSession -SessionId $session.SessionId
