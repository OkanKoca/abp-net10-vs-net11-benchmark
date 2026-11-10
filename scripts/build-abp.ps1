# Builds the ABP framework and modules used by net11 from the 11.0.0-rc.1 tag, once per variant:
#   off -> classic compiler state machines (net11-src)    ra -> runtime-async=on (net11-src-ra)
# Output: abp-build/<variant>/dll/Volo.Abp.*.dll, swapped into the published app by publish.ps1.
# ConfigureAwait.Fody is disabled in both variants: it rewrites compiler state machines, which runtime-async does not emit,
# so both builds differ from the NuGet packages only by that weaving and from each other only by the runtime-async flag.
param(
    [ValidateSet('off', 'ra')][string[]]$Variant = @('off', 'ra'),
    [string]$Tag = '11.0.0-rc.1',
    [string]$AbpRepo = "$(Split-Path $PSScriptRoot -Parent)/../abp"   # local clone of abpframework/abp
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$src = "$root/abp-src"

if (-not (Test-Path $src)) {
    # Shallow local clone: reads the tag from the local repository, no network and no change to that repository.
    git clone --quiet --depth 1 --branch $Tag "file:///$((Resolve-Path $AbpRepo) -replace '\\', '/')" $src
    if ($LASTEXITCODE) { throw "git clone of $Tag from $AbpRepo failed" }
}

# Every ABP package the net11 web app restores, transitive ones included (the csproj alone misses some).
$assets = "$root/net11/src/Bench.Web/obj/project.assets.json"
if (-not (Test-Path $assets)) { throw "$assets is missing; run ./scripts/publish.ps1 -Target net11 first" }
$names = (Get-Content $assets -Raw | ConvertFrom-Json -AsHashtable).libraries.Keys |
    Where-Object { $_ -like 'Volo.Abp.*' } | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique
$index = Get-ChildItem "$src/framework/src", "$src/modules/*/src" -Recurse -Depth 1 -Filter 'Volo.Abp.*.csproj' |
    Group-Object BaseName -AsHashTable
$projects = foreach ($n in $names) {
    if ($index[$n]) { [IO.Path]::GetRelativePath($src, $index[$n][0].FullName) -replace '\\', '/' }
    else { Write-Host "not in repo, stays NuGet: $n" }
}

# The solution lives in the clone so its global.json selects the SDK and project paths stay relative.
$sln = "$src/bench-abp.slnx"
$lines = $projects | ForEach-Object { '  <Project Path="{0}" />' -f $_ }
@('<Solution>') + $lines + @('</Solution>') | Set-Content $sln

foreach ($v in $Variant) {
    $out = "$root/abp-build/$v"
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    # Separate artifacts per variant: a changed property alone would not make MSBuild recompile.
    $buildArgs = @('build', $sln, '-c', 'Release', '-v', 'q', '--artifacts-path', "$out/artifacts",
        '-p:TargetFrameworks=net11.0', '-p:DisableFody=true')
    if ($v -eq 'ra') { $buildArgs += '-p:Features=runtime-async=on' }

    Push-Location $src
    try {
        Write-Host "== ABP $Tag / $v (SDK $(dotnet --version))"
        dotnet @buildArgs
        if ($LASTEXITCODE) { throw "ABP build failed: $v" }
    }
    finally { Pop-Location }

    # Each project's own output folder holds its assembly; dependencies copied next to it are skipped.
    New-Item -ItemType Directory -Force "$out/dll" | Out-Null
    Get-ChildItem "$out/artifacts/bin" -Directory -Filter 'Volo.Abp.*' | ForEach-Object {
        Get-ChildItem $_.FullName -Recurse -Filter "$($_.Name).dll" | Select-Object -First 1 | Copy-Item -Destination "$out/dll"
    }
    Write-Host "   $((Get-ChildItem "$out/dll").Count) assemblies -> $out/dll"
}
