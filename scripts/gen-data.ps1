# Generates client/data/*.lua from the pinned upstream vMenu/data/*.cs files.
# Deterministic: source order is preserved, no timestamps. Re-run after
# bumping the upstream pin (docs/UPSTREAM.md), then diff the outputs.
#
# Point this at a local clone of the upstream C# repo (tomgrobbe/vMenu).
# Resolution order:
#   1. -UpstreamPath argument
#   2. $env:VMENU_UPSTREAM
#   3. .upstream/vMenu under the repo root (gitignored; the same location
#      scripts/upstream-diff.ps1 clones into)
#
# Usage: pwsh scripts/gen-data.ps1 [-UpstreamPath <path to vMenu clone>]

param(
    [string]$UpstreamPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $UpstreamPath) {
    $UpstreamPath = if ($env:VMENU_UPSTREAM) { $env:VMENU_UPSTREAM } else { Join-Path $repoRoot '.upstream\vMenu' }
}

$dataDir = Join-Path $UpstreamPath 'vMenu\data'
$outDir = Join-Path $repoRoot 'client\data'
$pin = '49e53065'

if (-not (Test-Path $dataDir)) {
    throw @"
Upstream data dir not found: $dataDir

Clone the upstream C# repo into .upstream/vMenu:
    git clone https://github.com/tomgrobbe/vMenu .upstream/vMenu
or set `$env:VMENU_UPSTREAM / pass -UpstreamPath to point at an existing clone.
"@
}
New-Item -ItemType Directory -Force $outDir | Out-Null

# --- helpers -----------------------------------------------------------------

function ConvertTo-LuaString([string]$s) {
    "'" + ($s -replace '\\', '\\\\' -replace "'", "\'") + "'"
}

# Converts a C# value expression into a Lua expression.
#   GetLabelText("X")          -> L('X')
#   GetLabelText("X") + "."    -> L('X') .. '.'
#   Permission.WPFoo           -> 'WPFoo'
#   Game.GenerateHashASCII("x")-> H('x')
#   "literal" / 123            -> 'literal' / 123
function Convert-Value([string]$expr) {
    $expr = $expr.Trim()
    if ($expr -match '^GetLabelText\("([^"]+)"\)\s*\+\s*"([^"]*)"$') {
        return "L($(ConvertTo-LuaString $Matches[1])) .. $(ConvertTo-LuaString $Matches[2])"
    }
    if ($expr -match '^GetLabelText\("([^"]+)"\)$') {
        return "L($(ConvertTo-LuaString $Matches[1]))"
    }
    if ($expr -match '^Game\.GenerateHashASCII\("([^"]+)"\)$') {
        return "H($(ConvertTo-LuaString $Matches[1]))"
    }
    if ($expr -match '^Permission\.(\w+)$') {
        return ConvertTo-LuaString $Matches[1]
    }
    if ($expr -match '^"(.*)"$') {
        return ConvertTo-LuaString $Matches[1]
    }
    if ($expr -match '^-?\d+$') {
        return $expr
    }
    throw "Convert-Value: unhandled expression: $expr"
}

# Strips // line comments (naive but safe for these data files: no // inside
# string literals) and returns the region lines between the declaration match
# and its closing '};'.
function Get-Region([string[]]$lines, [string]$declPattern) {
    $start = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $declPattern) { $start = $i; break }
    }
    if ($null -eq $start) { throw "Region not found: $declPattern" }
    $body = @()
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*};') { return , $body }
        $line = $lines[$i] -replace '//.*$', ''
        if ($line.Trim() -ne '' -and $line.Trim() -ne '{') { $body += $line.Trim() }
    }
    throw "Region not closed: $declPattern"
}

# { "key", value },  (brace-pair dictionary entries)
function Parse-BracePairDict([string[]]$body) {
    $entries = @()
    foreach ($line in $body) {
        if ($line -match '^\{\s*"([^"]+)"\s*,\s*(.+?)\s*\},?$') {
            $entries += , @($Matches[1], (Convert-Value $Matches[2]))
        }
    }
    return , $entries
}

# ["key"] = value,  (indexer dictionary entries)
function Parse-IndexerDict([string[]]$body) {
    $entries = @()
    foreach ($line in $body) {
        if ($line -match '^\["([^"]+)"\]\s*=\s*(.+?),?$') {
            $entries += , @($Matches[1], (Convert-Value $Matches[2]))
        }
    }
    return , $entries
}

# "string",  (plain string list entries)
function Parse-StringList([string[]]$body) {
    $entries = @()
    foreach ($line in $body) {
        if ($line -match '^"([^"]+)"\s*,?$') { $entries += $Matches[1] }
    }
    return , $entries
}

# Game.GenerateHashASCII("name"),  (hash list entries)
function Parse-HashList([string[]]$body) {
    $entries = @()
    foreach ($line in $body) {
        if ($line -match '^Game\.GenerateHashASCII\("([^"]+)"\)\s*,?$') { $entries += $Matches[1] }
    }
    return , $entries
}

# new VehicleColor(id, "LABEL"),
function Parse-VehicleColors([string[]]$body) {
    $entries = @()
    foreach ($line in $body) {
        if ($line -match '^new VehicleColor\((\d+),\s*"([^"]+)"\)\s*,?$') {
            $entries += , @([int]$Matches[1], $Matches[2])
        }
    }
    return , $entries
}

# { new int[3] { r, g, b } },
function Parse-NeonColors([string[]]$body) {
    $entries = @()
    foreach ($line in $body) {
        if ($line -match 'new int\[3\]\s*\{\s*(\d+),\s*(\d+),\s*(\d+)\s*\}') {
            $entries += , @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
        }
    }
    return , $entries
}

# Emits a Lua dict plus a companion <name>_order array (C# Dictionary
# iteration order is insertion order; Lua pairs() is not, and the menus
# iterate these in order).
function Emit-OrderedDict([System.Text.StringBuilder]$sb, [string]$name, $entries) {
    [void]$sb.AppendLine("M.$name = {")
    foreach ($e in $entries) {
        [void]$sb.AppendLine("    [$(ConvertTo-LuaString $e[0])] = $($e[1]),")
    }
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine("M.${name}_order = {")
    foreach ($e in $entries) {
        [void]$sb.AppendLine("    $(ConvertTo-LuaString $e[0]),")
    }
    [void]$sb.AppendLine('}')
}

function Emit-StringList([System.Text.StringBuilder]$sb, [string]$name, $entries) {
    [void]$sb.AppendLine("M.$name = {")
    foreach ($e in $entries) {
        [void]$sb.AppendLine("    $(ConvertTo-LuaString $e),")
    }
    [void]$sb.AppendLine('}')
}

function New-Output([string]$sourceName) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("-- GENERATED by scripts/gen-data.ps1 from vMenu/data/$sourceName @ $pin — DO NOT EDIT.")
    [void]$sb.AppendLine('-- luacheck: ignore')
    [void]$sb.AppendLine('local L = GetLabelText')
    [void]$sb.AppendLine('local H = GetHashKey')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('local M = {}')
    [void]$sb.AppendLine('')
    return $sb
}

function Save-Output([System.Text.StringBuilder]$sb, [string]$fileName) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('return M')
    $path = Join-Path $outDir $fileName
    # LF endings, UTF-8 no BOM, matching the repo's .gitattributes
    $text = $sb.ToString() -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
    Write-Host "generated $fileName"
}

# --- vehicle_data.lua ---------------------------------------------------------

$lines = Get-Content (Join-Path $dataDir 'VehicleData.cs')
$sb = New-Output 'VehicleData.cs'

# The VehicleColor constructor registers replacement labels for colors the
# game has no text for; port of the AddTextEntry branches, run once at load.
[void]$sb.AppendLine(@'
-- Label fixups from the VehicleColor constructor (runs once at load).
local function apply_label_fixups()
    if L('veh_color_taxi_yellow') == 'NULL' then
        AddTextEntry('veh_color_taxi_yellow', ('Taxi %s'):format(L('IEC_T20_2')))
    end
    if L('veh_color_off_white') == 'NULL' then
        AddTextEntry('veh_color_off_white', 'Off White')
    end
    if L('VERY_DARK_BLUE') == 'NULL' then
        AddTextEntry('VERY_DARK_BLUE', 'Very Dark Blue')
    end
    AddTextEntry('G9_PAINT01', 'Monochrome')
    AddTextEntry('G9_PAINT02', 'Night & Day')
    AddTextEntry('G9_PAINT03', 'The Verlierer')
    AddTextEntry('G9_PAINT04', 'Sprunk Extreme')
    AddTextEntry('G9_PAINT05', 'Vice City')
    AddTextEntry('G9_PAINT06', 'Synthwave Nights')
    AddTextEntry('G9_PAINT07', 'Four Seasons')
    AddTextEntry('G9_PAINT08', 'Maisonette 9 Throwback')
    AddTextEntry('G9_PAINT09', 'Bubblegum')
    AddTextEntry('G9_PAINT10', 'Full Rainbow')
    AddTextEntry('G9_PAINT11', 'Sunset')
    AddTextEntry('G9_PAINT12', 'The Seven')
    AddTextEntry('G9_PAINT13', 'Kamen Rider')
    AddTextEntry('G9_PAINT14', 'Chromatic Aberration')
    AddTextEntry('G9_PAINT15', "It's Christmas!")
    AddTextEntry('G9_PAINT16', 'Temperature')
end
apply_label_fixups()
'@)
[void]$sb.AppendLine('')

$colorLists = 'ClassicColors', 'MatteColors', 'MetalColors', 'UtilColors', 'WornColors', 'ChameleonColors'
foreach ($name in $colorLists) {
    $colors = Parse-VehicleColors (Get-Region $lines "List<VehicleColor>\s+$name\b")
    [void]$sb.AppendLine("M.$name = {")
    foreach ($c in $colors) {
        [void]$sb.AppendLine("    { id = $($c[0]), label = $(ConvertTo-LuaString $c[1]) },")
    }
    [void]$sb.AppendLine('}')
}

$neon = Parse-NeonColors (Get-Region $lines 'List<int\[\]>\s+NeonLightColors\b')
[void]$sb.AppendLine('M.NeonLightColors = {')
foreach ($n in $neon) {
    [void]$sb.AppendLine("    { $($n[0]), $($n[1]), $($n[2]) },")
}
[void]$sb.AppendLine('}')

$vehicleCategories = 'Compacts', 'Sedans', 'SUVs', 'Coupes', 'Muscle', 'SportsClassics', 'Sports', 'Super',
'Motorcycles', 'OffRoad', 'Industrial', 'Utility', 'Vans', 'Cycles', 'Boats', 'Helicopters', 'Planes',
'Service', 'Emergency', 'Military', 'Commercial', 'Trains', 'OpenWheel'
foreach ($name in $vehicleCategories) {
    $vehicles = Parse-StringList (Get-Region $lines "List<string>\s+$name\s+\{ get; \}")
    if ($vehicles.Count -eq 0) { throw "No vehicles parsed for category $name" }
    Emit-StringList $sb $name $vehicles
}

# VehicleClasses: VEH_CLASS_<n> label -> category list (order preserved).
[void]$sb.AppendLine('M.VehicleClasses = {}')
[void]$sb.AppendLine('M.VehicleClasses_order = {}')
for ($i = 0; $i -lt $vehicleCategories.Count; $i++) {
    [void]$sb.AppendLine("M.VehicleClasses[L('VEH_CLASS_$i')] = M.$($vehicleCategories[$i])")
    [void]$sb.AppendLine("M.VehicleClasses_order[$($i + 1)] = L('VEH_CLASS_$i')")
}
[void]$sb.AppendLine(@'

function M.GetAllVehicles()
    local vehicles = {}
    for _, class_label in ipairs(M.VehicleClasses_order) do
        for _, vehicle in ipairs(M.VehicleClasses[class_label]) do
            vehicles[#vehicles + 1] = vehicle
        end
    end
    return vehicles
end
'@)
Save-Output $sb 'vehicle_data.lua'

# --- weapons_data.lua ----------------------------------------------------------

$lines = Get-Content (Join-Path $dataDir 'ValidWeapon.cs')
$sb = New-Output 'ValidWeapon.cs'

Emit-OrderedDict $sb 'weapon_descriptions' (Parse-BracePairDict (Get-Region $lines 'Dictionary<string, string>\s+weaponDescriptions\b'))
Emit-OrderedDict $sb 'weapon_names' (Parse-BracePairDict (Get-Region $lines 'Dictionary<string, string>\s+weaponNames\b'))
Emit-OrderedDict $sb 'weapon_permissions' (Parse-IndexerDict (Get-Region $lines 'Dictionary<string, Permission>\s+weaponPermissions\b'))
Emit-OrderedDict $sb 'weapon_component_names' (Parse-IndexerDict (Get-Region $lines 'Dictionary<string, string>\s+weaponComponentNames\b'))
Emit-OrderedDict $sb 'weapon_tints' (Parse-IndexerDict (Get-Region $lines 'Dictionary<string, int>\s+WeaponTints\b'))
Emit-OrderedDict $sb 'weapon_tints_mk2' (Parse-IndexerDict (Get-Region $lines 'Dictionary<string, int>\s+WeaponTintsMkII\b'))
Save-Output $sb 'weapons_data.lua'

# --- ped_models.lua -------------------------------------------------------------

$lines = Get-Content (Join-Path $dataDir 'PedModels.cs')
$sb = New-Output 'PedModels.cs'
$animals = Parse-HashList (Get-Region $lines 'List<uint>\s+AnimalHashes\b')
Emit-StringList $sb 'animals' $animals
[void]$sb.AppendLine(@'
M.animal_hashes = {}
for i, name in ipairs(M.animals) do
    M.animal_hashes[i] = H(name)
end
'@)
Save-Output $sb 'ped_models.lua'

# --- ped_scenarios.lua -----------------------------------------------------------

$lines = Get-Content (Join-Path $dataDir 'PedScenarios.cs')
$sb = New-Output 'PedScenarios.cs'
Emit-StringList $sb 'position_based_scenarios' (Parse-StringList (Get-Region $lines 'List<string>\s+PositionBasedScenarios\b'))
Emit-OrderedDict $sb 'scenario_names' (Parse-IndexerDict (Get-Region $lines 'Dictionary<string, string>\s+ScenarioNames\b'))
Emit-StringList $sb 'scenarios' (Parse-StringList (Get-Region $lines 'List<string>\s+Scenarios\b'))
Save-Output $sb 'ped_scenarios.lua'

# --- time_cycles.lua --------------------------------------------------------------

$lines = Get-Content (Join-Path $dataDir 'TimeCycles.cs')
$sb = New-Output 'TimeCycles.cs'
Emit-StringList $sb 'timecycles' (Parse-StringList (Get-Region $lines 'List<string>\s+Timecycles\b'))
Save-Output $sb 'time_cycles.lua'

# --- blip_info.lua ----------------------------------------------------------------

$lines = Get-Content (Join-Path $dataDir 'BlipInfo.cs')
$sb = New-Output 'BlipInfo.cs'
$sprites = @()
foreach ($line in $lines) {
    $clean = $line -replace '//.*$', ''
    if ($clean -match '\{\s*Game\.GenerateHashASCII\("([^"]+)"\),\s*(\d+)\s*\},?') {
        $sprites += , @($Matches[1], [int]$Matches[2])
    }
}
if ($sprites.Count -eq 0) { throw 'No blip sprites parsed' }
[void]$sb.AppendLine('M.vehicle_sprites = {')
foreach ($s in $sprites) {
    [void]$sb.AppendLine("    [H($(ConvertTo-LuaString $s[0]))] = $($s[1]),")
}
[void]$sb.AppendLine('}')
[void]$sb.AppendLine(@'

-- BlipInfo.GetBlipSpriteForVehicle.
function M.get_blip_sprite_for_vehicle(vehicle)
    local model = GetEntityModel(vehicle)
    if M.vehicle_sprites[model] ~= nil then
        return M.vehicle_sprites[model]
    elseif IsThisModelABike(model) then
        return 348
    elseif IsThisModelABoat(model) then
        return 427
    elseif IsThisModelAHeli(model) then
        return 422
    elseif IsThisModelAPlane(model) then
        return 423
    end
    return 225
end
'@)
Save-Output $sb 'blip_info.lua'

# --- overlays.json (shipped verbatim) ----------------------------------------------

# Copied verbatim except line endings, normalized to LF per .gitattributes so
# a regen after checkout stays diff-free.
$overlays = (Get-Content (Join-Path $dataDir 'overlays.json') -Raw) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText((Join-Path $outDir 'overlays.json'), $overlays, [System.Text.UTF8Encoding]::new($false))
Write-Host 'copied overlays.json'

Write-Host 'done.'
