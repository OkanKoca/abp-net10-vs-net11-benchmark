# seed : runs the target's DbMigrator on an empty "Bench" database and keeps the result as template "Bench_seed_<target>".
# reset: recreates "Bench" from that template, so every run starts from the same data set.
param(
    [Parameter(Mandatory)][ValidateSet('net10', 'net11')][string]$Target,
    [Parameter(Mandatory)][ValidateSet('seed', 'reset')][string]$Action
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$seedDb = "Bench_seed_$Target"

function Invoke-Sql([string]$Sql) {
    # SQL goes through stdin to avoid quoting issues in native arguments.
    $Sql | docker exec -i bench-postgres psql -U bench -d postgres -v ON_ERROR_STOP=1 -q
    if ($LASTEXITCODE) { throw "psql failed: $Sql" }
}

for ($i = 0; $i -lt 30; $i++) {
    docker exec bench-postgres pg_isready -U bench -q
    if (-not $LASTEXITCODE) { break }
    Start-Sleep -Seconds 1
}
if ($LASTEXITCODE) { throw 'PostgreSQL is not ready (docker compose up -d?)' }

if ($Action -eq 'seed') {
    Invoke-Sql 'DROP DATABASE IF EXISTS "Bench" WITH (FORCE);'
    . "$PSScriptRoot/env.ps1"
    Push-Location "$root/publish/$Target/migrator" # appsettings.json is read from the working directory
    try {
        dotnet Bench.DbMigrator.dll
        if ($LASTEXITCODE) { throw 'DbMigrator failed' }
    }
    finally { Pop-Location }
    Invoke-Sql "DROP DATABASE IF EXISTS `"$seedDb`";"
    Invoke-Sql "CREATE DATABASE `"$seedDb`" TEMPLATE `"Bench`";"
}

Invoke-Sql 'DROP DATABASE IF EXISTS "Bench" WITH (FORCE);'
Invoke-Sql "CREATE DATABASE `"Bench`" TEMPLATE `"$seedDb`";"
Write-Host "Bench database is ready ($Target)"
