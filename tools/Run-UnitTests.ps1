[CmdletBinding()]
param(
    [string] $DwarfUICoreSource = $env:DWARFUICORE_SOURCE,

    [Parameter(ValueFromRemainingArguments)]
    [string[]] $BustedArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$localBustedRunner = Join-Path $projectRoot 'lua_modules\bin\busted.bat'
$bustedConfig = Join-Path $projectRoot '.busted'

$bustedRunner = if (Test-Path -LiteralPath $localBustedRunner -PathType Leaf) {
    $localBustedRunner
} else {
    $globalBusted = Get-Command 'busted' -ErrorAction SilentlyContinue
    if ($globalBusted) { $globalBusted.Source } else { $null }
}

if (-not $bustedRunner) {
    throw "Busted was not found in the project-local LuaRocks tree or on PATH. Provision the pinned test dependencies with LuaRocks before running tests; this entrypoint does not install, update, or repair dependencies."
}

if (-not (Test-Path -LiteralPath $bustedConfig -PathType Leaf)) {
    throw "Repository Busted configuration was not found at '$bustedConfig'."
}

if (-not $DwarfUICoreSource) {
    throw 'DwarfUI feature tests require -DwarfUICoreSource or DWARFUICORE_SOURCE. Pass the intended DwarfUICore repository root explicitly.'
}

$resolvedDwarfUICoreSource = Resolve-Path -LiteralPath $DwarfUICoreSource -ErrorAction Stop
$coreInfo = Join-Path $resolvedDwarfUICoreSource 'src\info.txt'
$coreClass = Join-Path $resolvedDwarfUICoreSource `
    'src\scripts_modinstalled\dwarfuicore\class.lua'
if (-not (Test-Path -LiteralPath $coreInfo -PathType Leaf) -or
        -not (Test-Path -LiteralPath $coreClass -PathType Leaf)) {
    throw "DwarfUICore source must be a repository root containing src\\info.txt and dwarfuicore\\class.lua: $resolvedDwarfUICoreSource"
}

& (Join-Path $PSScriptRoot 'Check-UnitTestNaming.ps1')

Push-Location $projectRoot
try {
    $previousCoreSource = [Environment]::GetEnvironmentVariable(
        'DWARFUICORE_SOURCE', 'Process')
    [Environment]::SetEnvironmentVariable('DWARFUICORE_SOURCE',
        $resolvedDwarfUICoreSource.Path, 'Process')
    & $bustedRunner '--config-file' $bustedConfig @BustedArgs
    $bustedExitCode = $LASTEXITCODE
}
finally {
    [Environment]::SetEnvironmentVariable('DWARFUICORE_SOURCE',
        $previousCoreSource, 'Process')
    Pop-Location
}

exit $bustedExitCode
