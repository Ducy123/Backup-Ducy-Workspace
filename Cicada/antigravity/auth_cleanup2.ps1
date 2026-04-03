Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 300
    $r.Output | ForEach-Object { Write-Host $_ }
}

function Upload([string]$content, [string]$remote) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
    $b64 = [System.Convert]::ToBase64String($bytes)
    $chunk = 1800; $first = $true
    for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
        $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
        if ($first) { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' > ${remote}.b64" | Out-Null; $first = $false }
        else { Invoke-SSHCommand -SessionId $session.SessionId -Command "printf '%s' '$part' >> ${remote}.b64" | Out-Null }
    }
    Invoke-SSHCommand -SessionId $session.SessionId -Command "base64 -d ${remote}.b64 > $remote && rm ${remote}.b64" | Out-Null
    Write-Host "  Uploaded: $remote" -ForegroundColor Gray
}

$pyScript = @'
import json, os
import subprocess

config_path = "/root/.openclaw/openclaw.json"
try:
    with open(config_path, "r") as f:
        data = json.load(f)

    changed = False

    # 1. Remove cliproxy provider
    if "models" in data and "providers" in data["models"]:
        if "cliproxy" in data["models"]["providers"]:
            del data["models"]["providers"]["cliproxy"]
            changed = True

    # 2. Reconfigure agent models to use openai-codex
    if "agents" in data:
        # Defaults
        if "defaults" in data["agents"]:
            if "model" in data["agents"]["defaults"]:
                data["agents"]["defaults"]["model"] = {
                    "primary": "openai-codex/gpt-5.4",
                    "fallbacks": []
                }
                changed = True
            if "models" in data["agents"]["defaults"]:
                if "cliproxy/coding-main" in data["agents"]["defaults"]["models"]:
                    del data["agents"]["defaults"]["models"]["cliproxy/coding-main"]
                    changed = True

        # List
        if "list" in data["agents"]:
            for agent in data["agents"]["list"]:
                agent["model"] = {
                    "primary": "openai-codex/gpt-5.4",
                    "fallbacks": []
                }
                changed = True

    if changed:
        with open(config_path, "w") as f:
            json.dump(data, f, indent=2)
        print("SUCCESS: openclaw.json cleaned up. All agents now use openai-codex/gpt-5.4.")
    else:
        print("No changes needed in openclaw.json")
except Exception as e:
    print("FAILED:", str(e))
'@

Upload $pyScript "/tmp/cleanup.py"
Run "Run config cleanup" "python3 /tmp/cleanup.py"

# Stop cli proxy
Run "Stop cli proxy" "systemctl stop cli-proxy-api; systemctl disable cli-proxy-api; rm -rf /root/.cli-proxy-api /etc/systemd/system/cli-proxy-api.service"

# Check auth list
$oc = "/root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs"
$node = "/root/.nvm/versions/node/v22.22.1/bin/node"

Run "Identify codex accounts" "$node $oc auth list"

# Get OAuth URL logic
Run "Start OAuth flow" "{ $node $oc auth add --provider openai-codex > /tmp/oauth.log 2>&1 & } && sleep 3 && cat /tmp/oauth.log"

Remove-SSHSession -SessionId $session.SessionId
