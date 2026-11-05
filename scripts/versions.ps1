# Writes report/versions.md: machine, tools, runtimes and resolved package versions of both published apps.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$targets = 'net10', 'net11'
$packages = 'Volo.Abp.Core', 'Volo.Abp.AspNetCore.Mvc.UI.Theme.LeptonXLite', 'Volo.Abp.Studio.Client.AspNetCore',
            'Microsoft.EntityFrameworkCore', 'Npgsql.EntityFrameworkCore.PostgreSQL', 'Npgsql', 'OpenIddict.Core'
$installedRuntimes = dotnet --list-runtimes | ForEach-Object { $n, $v, $null = $_ -split ' '; [pscustomobject]@{ Name = $n; Version = [semver]$v } }

# The runtime the host actually picks: default roll-forward = latest installed patch of the requested major.minor,
# and a release version never rolls forward to a prerelease.
function Resolve-Runtime([string]$Name, [semver]$Requested) {
    $installedRuntimes |
        Where-Object { $_.Name -eq $Name -and $_.Version.Major -eq $Requested.Major -and $_.Version.Minor -eq $Requested.Minor -and
                       $_.Version -ge $Requested -and ($Requested.PreReleaseLabel -or -not $_.Version.PreReleaseLabel) } |
        Sort-Object Version | Select-Object -Last 1 -ExpandProperty Version
}

function Get-NpmVersion([string]$Target, [string]$Package) {
    (Get-Content "$root/$Target/src/Bench.Web/node_modules/$Package/package.json" -Raw | ConvertFrom-Json).version
}

$rows = [ordered]@{}
foreach ($t in $targets) {
    $web = "$root/publish/$t/web"
    $rc = (Get-Content "$web/Bench.Web.runtimeconfig.json" -Raw | ConvertFrom-Json).runtimeOptions
    $libs = (Get-Content "$web/Bench.Web.deps.json" -Raw | ConvertFrom-Json).libraries.PSObject.Properties.Name
    $col = [ordered]@{
        'SDK (global.json)'     = (Get-Content "$root/$t/global.json" -Raw | ConvertFrom-Json).sdk.version
        'Hedef framework'       = $rc.tfm
        'Server GC'             = $rc.configProperties.'System.GC.Server'
    }
    foreach ($f in $rc.frameworks) { $col["Runtime: $($f.name)"] = "$(Resolve-Runtime $f.name $f.version) (istenen $($f.version))" }
    foreach ($p in $packages) { $col["NuGet: $p"] = ($libs | Where-Object { $_ -like "$p/*" } | ForEach-Object { $_.Split('/')[1] }) -join ', ' }
    foreach ($p in '@abp/aspnetcore.mvc.ui.theme.leptonxlite', '@abp/aspnetcore.mvc.ui.theme.shared') { $col["npm: $p"] = Get-NpmVersion $t $p }
    $rows[$t] = $col
}

$cpu = Get-CimInstance Win32_Processor
$os = Get-CimInstance Win32_OperatingSystem
$ramGb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$power = (powercfg /getactivescheme) -replace '^.*\((.*)\)\s*$', '$1'
$pgVersion = docker exec bench-postgres psql -U bench -d postgres -tAc 'select version()'
$pgImage = docker inspect bench-postgres --format '{{.Config.Image}}'
$pgDigest = docker image inspect $pgImage --format '{{index .RepoDigests 0}}'

$md = [System.Collections.Generic.List[string]]::new()
$md.Add('# Sürümler ve ortam')
$md.Add('')
$md.Add("Üretim zamanı: $(Get-Date -Format 'yyyy-MM-dd HH:mm') (scripts/versions.ps1)")
$md.Add('')
$md.Add('## Uygulamalar')
$md.Add('')
$md.Add('| | net10 | net11 |')
$md.Add('|---|---|---|')
foreach ($key in $rows['net10'].Keys) { $md.Add("| $key | $($rows['net10'][$key]) | $($rows['net11'][$key]) |") }
$md.Add('')
$md.Add('## Makine ve araçlar')
$md.Add('')
$md.Add('| | |')
$md.Add('|---|---|')
$md.Add("| CPU | $($cpu.Name.Trim()) ($($cpu.NumberOfCores) çekirdek / $($cpu.NumberOfLogicalProcessors) mantıksal) |")
$md.Add("| RAM | $ramGb GB |")
$md.Add("| İşletim sistemi | $($os.Caption) $($os.Version) |")
$md.Add("| Güç planı | $power |")
$md.Add("| PostgreSQL | $pgVersion |")
$md.Add("| PostgreSQL imajı | $pgDigest |")
$md.Add("| Docker | $(docker version --format '{{.Server.Version}}') |")
$md.Add("| k6 | $((k6 version) -split ' ' | Select-Object -Index 1) |")
$md.Add("| dotnet-counters | $(dotnet-counters --version) |")

New-Item -ItemType Directory -Force "$root/report" | Out-Null
$md | Set-Content "$root/report/versions.md" -Encoding utf8
Write-Host "report/versions.md written"
