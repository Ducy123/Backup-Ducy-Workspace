Import-Module Posh-SSH
$pass = ConvertTo-SecureString "duc123" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $pass)
$session = New-SSHSession -ComputerName "157.10.53.238" -Port 27301 -Credential $cred -AcceptKey -Force

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 60
    $r.Output | ForEach-Object { Write-Host $_ }
}

$pyScript = @'
const https = require("https");
const data = JSON.stringify({ client_id: "01ab8ac9400c4e429b23", scope: "user:email" });
const options = {
    hostname: "github.com",
    port: 443,
    path: "/login/device/code",
    method: "POST",
    headers: { "Accept": "application/json", "Content-Type": "application/json", "Content-Length": data.length }
};
const req = https.request(options, (res) => {
    let raw = "";
    res.on("data", (c) => raw += c);
    res.on("end", () => console.log(raw));
});
req.write(data);
req.end();
'@

$bytes = [System.Text.Encoding]::UTF8.GetBytes($pyScript)
$b64 = [System.Convert]::ToBase64String($bytes)

Invoke-SSHCommand -SessionId $session.SessionId -Command "echo '$b64' | base64 -d > /tmp/gh.js" | Out-Null
Run "Generate GH Device Code" "node /tmp/gh.js"

Remove-SSHSession -SessionId $session.SessionId
