Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 300
    $r.Output | ForEach-Object { Write-Host $_ }
}

$pyScript = @'
import json, os

config_path = "/root/.openclaw/openclaw.json"
try:
    with open(config_path, "r") as f:
        data = json.load(f)

    # 1. Remove cliproxy provider
    if "models" in data and "providers" in data["models"]:
        if "cliproxy" in data["models"]["providers"]:
            del data["models"]["providers"]["cliproxy"]

    # 2. Reconfigure agent models to use openai-codex
    if "agents" in data:
        # Defaults
        if "defaults" in data["agents"]:
            if "model" in data["agents"]["defaults"]:
                data["agents"]["defaults"]["model"] = {
                    "primary": "openai-codex/gpt-5.4",
                    "fallbacks": []
                }
            if "models" in data["agents"]["defaults"]:
                if "cliproxy/coding-main" in data["agents"]["defaults"]["models"]:
                    del data["agents"]["defaults"]["models"]["cliproxy/coding-main"]

        # List
        if "list" in data["agents"]:
            for agent in data["agents"]["list"]:
                agent["model"] = {
                    "primary": "openai-codex/gpt-5.4",
                    "fallbacks": []
                }

    with open(config_path, "w") as f:
        json.dump(data, f, indent=2)

    print("SUCCESS: openclaw.json cleaned up. All agents now use openai-codex/gpt-5.4.")
except Exception as e:
    print("FAILED:", str(e))
'@

Run "Clean config" "python3 -c `"$pyScript`""

# Kill cli-proxy-api and disable it
Run "Stop cli proxy" "systemctl stop cli-proxy-api && systemctl disable cli-proxy-api && rm -rf /root/.cli-proxy-api"

# Get OAuth URL
$cmd = "export PATH=/root/.nvm/versions/node/v22.22.1/bin:`$PATH; node /root/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs auth add openai-codex & sleep 5"
Run "Get OAuth link" $cmd

# Restart openclaw gateway to apply new openclaw.json
Run "Restart gateway" "systemctl restart openclaw-gateway"

Remove-SSHSession -SessionId $session.SessionId
