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

# Create systemd service
$svcContent = @"
[Unit]
Description=CLIProxyAPI - Antigravity/Gemini proxy for OpenClaw
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$dir
ExecStart=$dir/bin/cli-proxy-api serve --config $dir/config.yaml
Restart=always
RestartSec=5
StandardOutput=append:/tmp/cliproxy.log
StandardError=append:/tmp/cliproxy.log

[Install]
WantedBy=multi-user.target
"@

Run "Write service file" "cat > /etc/systemd/system/cli-proxy-api.service << 'SVCEOF'
[Unit]
Description=CLIProxyAPI - Antigravity/Gemini proxy for OpenClaw
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/.openclaw/workspace-overseer/CLIProxyAPI
ExecStart=/root/.openclaw/workspace-overseer/CLIProxyAPI/bin/cli-proxy-api serve --config /root/.openclaw/workspace-overseer/CLIProxyAPI/config.yaml
Restart=always
RestartSec=5
StandardOutput=append:/tmp/cliproxy.log
StandardError=append:/tmp/cliproxy.log

[Install]
WantedBy=multi-user.target
SVCEOF
echo 'Service file written'"

Run "Reload systemd" "systemctl daemon-reload"

# Kill the manually started one first, then let systemd manage it
Run "Stop manual process" "pkill -f cli-proxy-api; sleep 2; echo stopped"
Run "Enable and start service" "systemctl enable cli-proxy-api; systemctl start cli-proxy-api; sleep 2; systemctl status cli-proxy-api --no-pager"
Run "Verify port 8317 again" "ss -ltnp | grep 8317"
Run "Confirm models endpoint" "curl -s -H 'Authorization: Bearer ducy-cli-proxy-internal-key' http://127.0.0.1:8317/v1/models | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f\"Models: {len(d[chr(100)+chr(97)+chr(116)+chr(97)]) }\")' 2>/dev/null"

Remove-SSHSession -SessionId $session.SessionId
