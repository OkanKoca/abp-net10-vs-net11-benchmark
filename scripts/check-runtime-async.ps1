# Counts, per assembly, the methods compiled as runtime-async (MethodImplAttributes.Async = 0x2000) and the
# compiler-generated <Method>d__N types (async state machines, but iterators share the naming).
# -Expect on|off fails if the Volo.Abp.* and Bench.* assemblies in -Path do not match, so a flag that silently
# did not apply cannot pass as "no difference".
#   ./scripts/check-runtime-async.ps1 -Path publish/net11-src-ra/web -Expect on
param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateSet('on', 'off')][string]$Expect
)
$ErrorActionPreference = 'Stop'

$rows = foreach ($file in Get-ChildItem $Path -Filter '*.dll' | Where-Object Name -Match '^(Volo\.Abp|Bench)\.') {
    $stream = [IO.File]::OpenRead($file.FullName)
    try {
        $pe = [Reflection.PortableExecutable.PEReader]::new($stream)
        if (-not $pe.HasMetadata) { continue }
        $md = [Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($pe)
        $stateMachines = @($md.TypeDefinitions | Where-Object { $md.GetString($md.GetTypeDefinition($_).Name) -match '^<.+>d__\d+' }).Count
        $runtimeAsync = @($md.MethodDefinitions | Where-Object { [int]$md.GetMethodDefinition($_).ImplAttributes -band 0x2000 }).Count
        [pscustomobject]@{ Assembly = $file.BaseName; StateMachines = $stateMachines; RuntimeAsync = $runtimeAsync }
    }
    finally { $stream.Dispose() }
}
$rows | Sort-Object Assembly | Format-Table -AutoSize | Out-Host

$abp = ($rows | Where-Object Assembly -Like 'Volo.Abp.*' | Measure-Object RuntimeAsync -Sum).Sum
$bench = ($rows | Where-Object Assembly -Like 'Bench.*' | Measure-Object RuntimeAsync -Sum).Sum
Write-Host "runtime-async methods: Volo.Abp.* $abp, Bench.* $bench"
if ($Expect -eq 'on' -and ($abp -eq 0 -or $bench -eq 0)) { throw "expected runtime-async in $Path, found Volo.Abp.* $abp, Bench.* $bench" }
if ($Expect -eq 'off' -and ($abp + $bench) -gt 0) { throw "expected no runtime-async in $Path, found Volo.Abp.* $abp, Bench.* $bench" }
