# Requires: PowerShell 7+
$ErrorActionPreference = 'Stop'

# Resolve repo root (script is in src/, manifest is at repo root)
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
$manifestPath = Join-Path $repoRoot 'manifest.json'

if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Error "manifest.json not found at: $manifestPath"
    exit 1
}

# Load manifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

# Header
if ($manifest.metadata) {
    Write-Host "Manifest: $($manifest.metadata.title) v$($manifest.metadata.version) ($($manifest.metadata.lastUpdated))" -ForegroundColor Cyan
}

# Enumerate policies only
$policies = @()
if ($manifest.policies) {
    $policies = $manifest.policies | Where-Object { $_.type -eq 'Policy' }
}

Write-Host "Found $($policies.Count) policies:`n" -ForegroundColor Cyan

foreach ($p in $policies) {
    $policyPath = Join-Path $repoRoot $p.filePath
    $exists = Test-Path -LiteralPath $policyPath
    $status = if ($exists) { 'OK' } else { 'MISSING' }

    $desc = $p.description
    if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0, 137) + '...' }

    Write-Host "• $($p.name)" -ForegroundColor Yellow
    Write-Host "  - Category: $($p.category); Platform: $($p.platform); Settings: $($p.settingCount)"
    Write-Host "  - Path: $($p.filePath) [$status]"
    if ($desc) { Write-Host "  - Desc: $desc" }
    Write-Host ""
}

# Enumerate packages/apps
$packages = @()
if ($manifest.policies) {
    $packages = $manifest.policies | Where-Object { $_.type -in @('Package','App') }
}

Write-Host "Found $($packages.Count) packages/apps:`n" -ForegroundColor Cyan

foreach ($a in $packages) {
    $assetPath = Join-Path $repoRoot $a.filePath
    $exists = Test-Path -LiteralPath $assetPath
    $status = if ($exists) { 'OK' } else { 'MISSING' }

    $desc = $a.description
    if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0, 137) + '...' }

    Write-Host "• $($a.name)" -ForegroundColor Yellow
    Write-Host "  - Category: $($a.category); Platform: $($a.platform)"
    Write-Host "  - Path: $($a.filePath) [$status]"
    if ($desc) { Write-Host "  - Desc: $desc" }
    Write-Host ""
}

# Enumerate scripts
$scripts = @()
if ($manifest.policies) {
    $scripts = $manifest.policies | Where-Object { $_.type -eq 'Script' }
}

Write-Host "Found $($scripts.Count) scripts:`n" -ForegroundColor Cyan

foreach ($s in $scripts) {
    $scriptPath = Join-Path $repoRoot $s.filePath
    $exists = Test-Path -LiteralPath $scriptPath
    $status = if ($exists) { 'OK' } else { 'MISSING' }

    $desc = $s.description
    if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0, 137) + '...' }

    Write-Host "• $($s.name)" -ForegroundColor Yellow
    Write-Host "  - Platform: $($s.platform); RequiresElevation: $($s.requiresElevation)"
    Write-Host "  - Intune: RunAsSignedInUser=$($s.runAsSignedInUser); HideNotifications=$($s.hideNotifications); Frequency='$($s.frequency)'; MaxRetries=$($s.maxRetries)"
    Write-Host "  - Path: $($s.filePath) [$status]"
    if ($desc) { Write-Host "  - Desc: $desc" }
    Write-Host ""
}