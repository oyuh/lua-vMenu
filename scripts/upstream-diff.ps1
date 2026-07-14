# Shows what changed in upstream vMenu since our pinned commit, so diffs can be ported.
# Usage: pwsh scripts/upstream-diff.ps1
$ErrorActionPreference = 'Stop'

$UpstreamRepo = 'https://github.com/tomgrobbe/vMenu'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$CacheDir = Join-Path $RepoRoot '.upstream'

# Read the pinned SHA out of docs/UPSTREAM.md so there's a single source of truth.
$upstreamDoc = Get-Content (Join-Path $RepoRoot 'docs\UPSTREAM.md') -Raw
if ($upstreamDoc -notmatch '`([0-9a-f]{40})`') { throw 'Could not find pinned SHA in docs/UPSTREAM.md' }
$Pinned = $Matches[1]

if (-not (Test-Path (Join-Path $CacheDir '.git'))) {
    git clone $UpstreamRepo $CacheDir
} else {
    git -C $CacheDir fetch origin
}
$head = (git -C $CacheDir rev-parse origin/master).Trim()

Write-Host "Pinned:   $Pinned"
Write-Host "Upstream: $head"
if ($head -eq $Pinned) {
    Write-Host 'Up to date with upstream. Nothing to port.' -ForegroundColor Green
    exit 0
}

Write-Host "`n=== Commits since pin ===" -ForegroundColor Cyan
git -C $CacheDir log --oneline "$Pinned..$head"

Write-Host "`n=== Changed files ===" -ForegroundColor Cyan
git -C $CacheDir diff --stat $Pinned $head

Write-Host "`nMap changed files to Lua modules via docs/UPSTREAM.md, port the diffs, then update the pin."
Write-Host "Full diff: git -C .upstream diff $Pinned $head -- <file>"
