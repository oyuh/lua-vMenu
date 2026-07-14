# Regenerates the permission list in shared/permissions.lua and the table in
# docs/contracts/permissions.md from upstream's PermissionsManager.cs.
# Usage: pwsh scripts/gen-permissions.ps1 [-UpstreamRoot <path to vMenu clone>]
param(
    [string]$UpstreamRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) '.upstream')
)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

$source = Get-Content (Join-Path $UpstreamRoot 'SharedClasses\PermissionsManager.cs')

# Pull every identifier out of the `public enum Permission { ... };` block.
$inEnum = $false
$names = @()
foreach ($line in $source) {
    if ($line -match 'public enum Permission') { $inEnum = $true; continue }
    if ($inEnum -and $line -match '^\s*\};') { break }
    if (-not $inEnum) { continue }
    $trimmed = ($line -replace '//.*$', '').Trim()
    if ($trimmed -match '^#' -or $trimmed -eq '' -or $trimmed -eq '{') { continue }
    if ($trimmed -match '^([A-Za-z0-9_]+)\s*,?$') { $names += $Matches[1] }
}
if ($names.Count -lt 100) { throw "Extraction looks wrong: only $($names.Count) permissions found" }

# Same category mapping as GetAceName in PermissionsManager.cs.
$categories = @{
    OP = 'OnlinePlayers'; PO = 'PlayerOptions'; VO = 'VehicleOptions'; VS = 'VehicleSpawner'
    SV = 'SavedVehicles'; PV = 'PersonalVehicle'; PA = 'PlayerAppearance'; TO = 'TimeOptions'
    WO = 'WeatherOptions'; WP = 'WeaponOptions'; WL = 'WeaponLoadouts'; MS = 'MiscSettings'
    VC = 'VoiceChat'
}
function Get-AceName([string]$name) {
    $prefix = $name.Substring(0, 2)
    if ($categories.ContainsKey($prefix)) { return "vMenu.$($categories[$prefix]).$($name.Substring(2))" }
    return "vMenu.$name"
}

# --- shared/permissions.lua: replace the generated block ---
$luaPath = Join-Path $RepoRoot 'shared\permissions.lua'
$luaLines = $names | ForEach-Object { "    '$_'," }
$lua = Get-Content $luaPath -Raw
$block = "-- GEN-BEGIN permission-list (run scripts/gen-permissions.ps1 to update)`nPermissions.list = {`n" +
    ($luaLines -join "`n") + "`n}`n-- GEN-END permission-list"
$lua = [regex]::Replace($lua, '(?s)-- GEN-BEGIN permission-list.*?-- GEN-END permission-list', { $block })
Set-Content $luaPath $lua -NoNewline

# --- docs/contracts/permissions.md: replace the generated table ---
$docPath = Join-Path $RepoRoot 'docs\contracts\permissions.md'
$rows = $names | ForEach-Object { "| ``$_`` | ``$(Get-AceName $_)`` |" }
$table = "<!-- GEN-BEGIN ace-table (run scripts/gen-permissions.ps1 to update) -->`n" +
    "| Permission | Ace name |`n|---|---|`n" + ($rows -join "`n") +
    "`n<!-- GEN-END ace-table -->"
$doc = Get-Content $docPath -Raw
$doc = [regex]::Replace($doc, '(?s)<!-- GEN-BEGIN ace-table.*?<!-- GEN-END ace-table -->', { $table })
Set-Content $docPath $doc -NoNewline

Write-Host "Extracted $($names.Count) permissions from upstream."
Write-Host "Updated: shared/permissions.lua, docs/contracts/permissions.md"
