# Runs the published web app of the target with the shared measurement settings (blocks until stopped).
param([Parameter(Mandatory)][ValidateSet('net10', 'net11')][string]$Target)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot/env.ps1"

Push-Location "$root/publish/$Target/web" # content root: wwwroot, openiddict.pfx, appsettings.json
try { dotnet Bench.Web.dll --urls https://localhost:44377 }
finally { Pop-Location }
