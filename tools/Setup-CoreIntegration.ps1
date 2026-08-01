[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $DwarfUICoreSource,

    [Parameter(Mandatory)]
    [string] $DwarfUICorePackage,

    [Parameter(Mandatory)]
    [string] $DwarfUIPackage,

    [string] $IntegrationRoot = 'dist/integration'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

### Resolves an existing directory from a caller-supplied path.
function Resolve-InputDirectory {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Label
    )

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $resolved.Path -PathType Container)) {
        throw "$Label must be a directory: $Path"
    }
    return $resolved.Path
}

### Reads one bracketed DFHack mod metadata value.
function Get-ModInfoValue {
    param(
        [Parameter(Mandatory)]
        [string] $InfoPath,

        [Parameter(Mandatory)]
        [string] $Key
    )

    $text = Get-Content -LiteralPath $InfoPath -Raw
    $match = [regex]::Match($text,
        "\[$([regex]::Escape($Key)):(.*?)\]")
    if (-not $match.Success) {
        throw "Missing [${Key}:...] in $InfoPath"
    }
    return $match.Groups[1].Value.Trim()
}

### Requires a package file and returns its absolute path.
function Require-PackageFile {
    param(
        [Parameter(Mandatory)]
        [string] $PackageRoot,

        [Parameter(Mandatory)]
        [string] $RelativePath,

        [Parameter(Mandatory)]
        [string] $Label
    )

    $path = Join-Path $PackageRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$Label is partial; missing $RelativePath"
    }
    return (Resolve-Path -LiteralPath $path).Path
}

### Requires a package directory to match the expected mod identifier.
function Assert-PackageIdentity {
    param(
        [Parameter(Mandatory)]
        [string] $PackageRoot,

        [Parameter(Mandatory)]
        [string] $ExpectedId,

        [Parameter(Mandatory)]
        [string] $Label
    )

    $infoPath = Require-PackageFile -PackageRoot $PackageRoot `
        -RelativePath 'info.txt' -Label $Label
    $actualId = Get-ModInfoValue -InfoPath $infoPath -Key 'ID'
    if ($actualId -ne $ExpectedId) {
        throw "$Label is incompatible; expected mod ID '$ExpectedId', found '$actualId'."
    }
}

### Copies one fully validated package into the isolated integration mods tree.
function Install-Package {
    param(
        [Parameter(Mandatory)]
        [string] $PackageRoot,

        [Parameter(Mandatory)]
        [string] $Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $PackageRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

$coreSource = Resolve-InputDirectory -Path $DwarfUICoreSource `
    -Label 'DwarfUICore source'
$corePackage = Resolve-InputDirectory -Path $DwarfUICorePackage `
    -Label 'DwarfUICore package'
$uiPackage = Resolve-InputDirectory -Path $DwarfUIPackage `
    -Label 'DwarfUI package'

$coreSourceInfo = Require-PackageFile -PackageRoot $coreSource `
    -RelativePath 'src/info.txt' -Label 'DwarfUICore source'
$coreSourceRootScript = Require-PackageFile -PackageRoot $coreSource `
    -RelativePath 'src/scripts_modinstalled/dwarfuicore.lua' `
    -Label 'DwarfUICore source'
Assert-PackageIdentity -PackageRoot $corePackage -ExpectedId 'dwarfuicore' `
    -Label 'DwarfUICore package'
Assert-PackageIdentity -PackageRoot $uiPackage -ExpectedId 'dwarfui' `
    -Label 'DwarfUI package'

$corePackageRootScript = Require-PackageFile -PackageRoot $corePackage `
    -RelativePath 'scripts_modinstalled/dwarfuicore.lua' `
    -Label 'DwarfUICore package'
Require-PackageFile -PackageRoot $corePackage `
    -RelativePath 'scripts_modinstalled/dwarfuicore/module_registry.lua' `
    -Label 'DwarfUICore package' | Out-Null
Require-PackageFile -PackageRoot $corePackage `
    -RelativePath 'scripts_modinstalled/dwarfuicore/tooltip/api.lua' `
    -Label 'DwarfUICore package' | Out-Null
Require-PackageFile -PackageRoot $corePackage `
    -RelativePath 'scripts_modinstalled/dwarfuicore/context_menu/api.lua' `
    -Label 'DwarfUICore package' | Out-Null

$sourceHash = (Get-FileHash -LiteralPath $coreSourceRootScript -Algorithm SHA256).Hash
$packageHash = (Get-FileHash -LiteralPath $corePackageRootScript -Algorithm SHA256).Hash
if ($sourceHash -ne $packageHash) {
    throw 'DwarfUICore package is stale or was built from a different source generation.'
}

$integrationCandidate = if ([IO.Path]::IsPathFullyQualified($IntegrationRoot)) {
    $IntegrationRoot
} else {
    Join-Path $repositoryRoot $IntegrationRoot
}
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot 'dist'))
$integrationPath = [IO.Path]::GetFullPath($integrationCandidate)
if (-not $integrationPath.StartsWith($allowedRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "IntegrationRoot must remain under $allowedRoot"
}
if (Test-Path -LiteralPath $integrationPath) {
    Remove-Item -LiteralPath $integrationPath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $integrationPath | Out-Null

$modsRoot = Join-Path $integrationPath 'mods'
$coreInstall = Join-Path $modsRoot 'DwarfUICore'
$uiInstall = Join-Path $modsRoot 'DwarfUI'
Install-Package -PackageRoot $corePackage -Destination $coreInstall
Install-Package -PackageRoot $uiPackage -Destination $uiInstall

$installedCoreScript = Require-PackageFile -PackageRoot $coreInstall `
    -RelativePath 'scripts_modinstalled/dwarfuicore.lua' `
    -Label 'Installed DwarfUICore package'
Require-PackageFile -PackageRoot $uiInstall `
    -RelativePath 'scripts_modinstalled/dwarfui.lua' `
    -Label 'Installed DwarfUI package' | Out-Null

$coreCandidates = @(Get-ChildItem -LiteralPath $modsRoot -Recurse -File `
    -Filter 'dwarfuicore.lua')
if ($coreCandidates.Count -ne 1 -or
        $coreCandidates[0].FullName -ne $installedCoreScript) {
    throw 'Duplicate DwarfUICore root scripts were found in the integration mods tree.'
}

$uiCoreRoot = Join-Path $uiInstall 'scripts_modinstalled/dwarfuicore.lua'
if (Test-Path -LiteralPath $uiCoreRoot -PathType Leaf) {
    throw 'DwarfUI package incorrectly contains a duplicate dwarfuicore.lua.'
}
$minecartScript = Require-PackageFile -PackageRoot $uiInstall `
    -RelativePath 'scripts_modinstalled/dwarfui-minecart-route-markers.lua' `
    -Label 'Installed DwarfUI package'
if (-not (Get-Content -LiteralPath $minecartScript -Raw).Contains(
        "reqscript('dwarfuicore/tooltip/api')")) {
    throw 'Installed DwarfUI package does not import the intended DwarfUICore tooltip API.'
}

$coreVersion = Get-ModInfoValue -InfoPath $coreSourceInfo `
    -Key 'DISPLAYED_VERSION'
$installedCoreVersion = Get-ModInfoValue -InfoPath (Join-Path $coreInstall 'info.txt') `
    -Key 'DISPLAYED_VERSION'
if ($coreVersion -ne $installedCoreVersion) {
    throw "Installed DwarfUICore package is incompatible; expected version $coreVersion, found $installedCoreVersion."
}

$coreCommitOutput = @(& git -c "safe.directory=$coreSource" -C $coreSource `
    rev-parse HEAD 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not determine DwarfUICore source identity.'
}
$coreCommit = ($coreCommitOutput | Select-Object -First 1).ToString().Trim()
$evidence = [ordered]@{
    dwarfuicore_source=$coreSource
    dwarfuicore_source_commit=$coreCommit
    dwarfuicore_version=$coreVersion
    dwarfuicore_package=$corePackage
    dwarfuicore_package_root_hash=$packageHash
    dwarfuicore_resolved_script=$installedCoreScript
    dwarfui_package=$uiPackage
    dwarfui_installed_root=$uiInstall
    install_order=@('DwarfUICore', 'DwarfUI')
}
$evidencePath = Join-Path $integrationPath 'resolution-evidence.json'
$evidence | ConvertTo-Json | Set-Content -LiteralPath $evidencePath -Encoding utf8
Write-Host "DwarfUI integration setup passed. Evidence: $evidencePath"
