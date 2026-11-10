# Release-publishes the web app and the DbMigrator of each target into publish/<target>/.
#   net11-src     net11 app with the ABP assemblies built from source by build-abp.ps1 (runtime-async off)
#   net11-src-ra  same, ABP and the app compiled with runtime-async=on
# The src targets use the net11 database, so only their web app is published.
param([ValidateSet('net10', 'net11', 'net11-src', 'net11-src-ra')][string[]]$Target = @('net10', 'net11'))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

foreach ($t in $Target) {
    $project = $t -replace '-src(-ra)?$', ''
    $variant = switch ($t) { 'net11-src' { 'off' } 'net11-src-ra' { 'ra' } }
    $parts = if ($variant) { @{ 'Bench.Web' = 'web' } } else { @{ 'Bench.Web' = 'web'; 'Bench.DbMigrator' = 'migrator' } }

    # global.json is resolved from the working directory, so publish from inside the project folder.
    Push-Location "$root/$project"
    try {
        foreach ($p in $parts.GetEnumerator()) {
            $out = "$root/publish/$t/$($p.Value)"
            if (Test-Path $out) { Remove-Item $out -Recurse -Force }
            $publishArgs = @("src/$($p.Key)", '-c', 'Release', '-o', $out, '-v', 'q')
            if ($variant) {
                # Own build folders: a changed runtime-async flag alone would not make MSBuild recompile a shared obj/.
                $publishArgs += @('--artifacts-path', "$root/abp-build/app-$t")
                if ($variant -eq 'ra') { $publishArgs += '-p:Features=runtime-async=on' }
            }
            Write-Host "== $t / $($p.Key) (SDK $(dotnet --version))"
            dotnet publish @publishArgs
            if ($LASTEXITCODE) { throw "publish failed: $t/$($p.Key)" }
        }
    }
    finally { Pop-Location }

    if ($variant) {
        # Replace the NuGet ABP assemblies with the ones built from source; packages not in the ABP repository stay.
        $web = "$root/publish/$t/web"
        $dlls = "$root/abp-build/$variant/dll"
        if (-not (Test-Path $dlls)) { throw "$dlls is missing; run ./scripts/build-abp.ps1 first" }
        $swapped = @(Get-ChildItem $dlls -Filter '*.dll' | Where-Object { Test-Path "$web/$($_.Name)" })
        $swapped | Copy-Item -Destination $web -Force
        $kept = Get-ChildItem $web -Filter 'Volo.Abp.*.dll' | Where-Object { -not (Test-Path "$dlls/$($_.Name)") }
        Write-Host "   swapped $($swapped.Count) ABP assemblies; still from NuGet: $($kept.BaseName -join ', ')"
        & "$PSScriptRoot/check-runtime-async.ps1" -Path $web -Expect $(if ($variant -eq 'ra') { 'on' } else { 'off' })
    }
}
