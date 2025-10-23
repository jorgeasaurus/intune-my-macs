#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Finds duplicate payload settings across Intune configuration files.

.DESCRIPTION
    This script analyzes Settings Catalog JSON files, mobileconfig plist files, and compliance policies
    to identify duplicate or overlapping settings across different configurations. This helps identify
    potential conflicts or redundant configurations in your Intune deployment.

.PARAMETER Path
    The root path to search for configuration files. Defaults to the repository root.

.PARAMETER OutputFormat
    Output format: 'Console' (default), 'CSV', or 'JSON'

.PARAMETER OutputFile
    Path to save the output file when using CSV or JSON format.

.EXAMPLE
    ./Find-DuplicatePayloadSettings.ps1
    
.EXAMPLE
    ./Find-DuplicatePayloadSettings.ps1 -OutputFormat CSV -OutputFile duplicate-settings.csv

.EXAMPLE
    ./Find-DuplicatePayloadSettings.ps1 -OutputFormat JSON -OutputFile duplicate-settings.json

.NOTES
    Author: Microsoft
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = $PSScriptRoot,

    [Parameter()]
    [ValidateSet('Console', 'CSV', 'JSON')]
    [string]$OutputFormat = 'Console',

    [Parameter()]
    [string]$OutputFile
)

# Move to parent directory if running from tools folder
if ((Split-Path -Leaf $Path) -eq 'tools') {
    $Path = Split-Path -Parent $Path
}

Write-Host "🔍 Analyzing configuration files in: $Path" -ForegroundColor Cyan
Write-Host ""

# Define file patterns to search
$patterns = @(
    "configurations/intune/*.json",
    "configurations/entra/*.json",
    "mde/*.json"
)

# Storage for all settings
$allSettings = @()
$settingIndex = @{}

#region Helper Functions

function Get-SettingsFromJson {
    param([string]$FilePath)
    
    $settings = @()
    
    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        
        # Check if it's a Settings Catalog policy (has 'settings' array with 'settingInstance' objects)
        if ($content.PSObject.Properties.Name -contains 'settings') {
            # Settings Catalog files have settings[].settingInstance structure
            foreach ($settingWrapper in $content.settings) {
                if ($settingWrapper.PSObject.Properties.Name -contains 'settingInstance') {
                    $settings += Get-SettingInstancesRecursive -Settings @($settingWrapper.settingInstance) -ParentPath ""
                }
                else {
                    # Fallback for older format
                    $settings += Get-SettingInstancesRecursive -Settings @($settingWrapper) -ParentPath ""
                }
            }
        }
        # Check if it's a compliance policy
        elseif ($content.PSObject.Properties.Name -contains 'scheduledActionsForRule') {
            foreach ($prop in $content.PSObject.Properties) {
                if ($prop.Name -notin @('@odata.type', 'id', 'createdDateTime', 'lastModifiedDateTime', 
                                        'displayName', 'description', 'version', 'scheduledActionsForRule')) {
                    $settings += [PSCustomObject]@{
                        SettingId = $prop.Name
                        Value = $prop.Value
                        Path = $prop.Name
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to parse JSON file: $FilePath - $($_.Exception.Message)"
    }
    
    return $settings
}

function Get-SettingInstancesRecursive {
    param(
        [object]$Settings,
        [string]$ParentPath
    )
    
    $results = @()
    
    foreach ($setting in $Settings) {
        if ($null -eq $setting) { continue }
        
        # Extract settingDefinitionId
        $settingId = $null
        if ($setting.PSObject.Properties.Name -contains 'settingDefinitionId') {
            $settingId = $setting.settingDefinitionId
        }
        
        # Extract value
        $value = $null
        $valueProperties = @('simpleSettingValue', 'choiceSettingValue', 'value', 'stringValue', 'intValue', 'boolValue')
        foreach ($prop in $valueProperties) {
            if ($setting.PSObject.Properties.Name -contains $prop) {
                $value = $setting.$prop
                if ($value -is [PSCustomObject]) {
                    if ($value.PSObject.Properties.Name -contains 'value') {
                        $value = $value.value
                    }
                }
                break
            }
        }
        
        # Check if this is a collection container (has groupSettingCollectionValue or children but no value)
        $isCollectionContainer = ($setting.PSObject.Properties.Name -contains 'groupSettingCollectionValue' -or 
                                  $setting.PSObject.Properties.Name -contains 'children') -and 
                                 ($null -eq $value)
        
        # Only add settings that have actual values (leaf nodes), not collection containers
        if ($settingId -and -not $isCollectionContainer) {
            $results += [PSCustomObject]@{
                SettingId = $settingId
                Value = $value
                Path = if ($ParentPath) { "$ParentPath > $settingId" } else { $settingId }
            }
        }
        
        # Recursively process children
        if ($setting.PSObject.Properties.Name -contains 'children') {
            $childPath = if ($settingId) { 
                if ($ParentPath) { "$ParentPath > $settingId" } else { $settingId }
            } else { 
                $ParentPath 
            }
            $results += Get-SettingInstancesRecursive -Settings $setting.children -ParentPath $childPath
        }
        
        # Process groupSettingCollectionValue
        if ($setting.PSObject.Properties.Name -contains 'groupSettingCollectionValue') {
            foreach ($group in $setting.groupSettingCollectionValue) {
                if ($group.PSObject.Properties.Name -contains 'children') {
                    $groupPath = if ($settingId) { 
                        if ($ParentPath) { "$ParentPath > $settingId" } else { $settingId }
                    } else { 
                        $ParentPath 
                    }
                    $results += Get-SettingInstancesRecursive -Settings $group.children -ParentPath $groupPath
                }
            }
        }
        
        # Process simpleSettingCollectionValue (arrays)
        if ($setting.PSObject.Properties.Name -contains 'simpleSettingCollectionValue') {
            $index = 0
            foreach ($item in $setting.simpleSettingCollectionValue) {
                if ($item.PSObject.Properties.Name -contains 'value') {
                    $results += [PSCustomObject]@{
                        SettingId = "$settingId[$index]"
                        Value = $item.value
                        Path = if ($ParentPath) { "$ParentPath > $settingId[$index]" } else { "$settingId[$index]" }
                    }
                    $index++
                }
            }
        }
    }
    
    return $results
}

function Get-SettingsFromMobileConfig {
    param([string]$FilePath)
    
    $settings = @()
    
    try {
        # Convert plist to JSON using plutil (macOS built-in)
        $jsonContent = & plutil -convert json -o - "$FilePath" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $plist = $jsonContent | ConvertFrom-Json
            
            if ($plist.PSObject.Properties.Name -contains 'PayloadContent') {
                foreach ($payload in $plist.PayloadContent) {
                    $payloadType = $payload.PayloadType
                    
                    foreach ($prop in $payload.PSObject.Properties) {
                        if ($prop.Name -notin @('PayloadType', 'PayloadVersion', 'PayloadIdentifier', 
                                                 'PayloadUUID', 'PayloadDisplayName', 'PayloadDescription', 
                                                 'PayloadOrganization', 'PayloadEnabled')) {
                            $settingId = if ($payloadType) { "$payloadType.$($prop.Name)" } else { $prop.Name }
                            $settings += [PSCustomObject]@{
                                SettingId = $settingId
                                Value = $prop.Value
                                Path = $settingId
                            }
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to parse mobileconfig file: $FilePath - $($_.Exception.Message)"
    }
    
    return $settings
}

function Get-ManifestMetadata {
    param([string]$SourceFile)
    
    # Find corresponding XML manifest
    $xmlFile = $SourceFile -replace '\.(json|mobileconfig)$', '.xml'
    
    if (Test-Path $xmlFile) {
        try {
            [xml]$manifest = Get-Content -Path $xmlFile -Raw
            return [PSCustomObject]@{
                ReferenceId = $manifest.MacIntuneManifest.ReferenceId
                Name = $manifest.MacIntuneManifest.Name
                Type = $manifest.MacIntuneManifest.Type
            }
        }
        catch {
            Write-Verbose "Failed to parse manifest: $xmlFile"
        }
    }
    
    # Fallback to filename-based metadata
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile)
    return [PSCustomObject]@{
        ReferenceId = $fileName
        Name = $fileName
        Type = 'Unknown'
    }
}

#endregion

#region Main Processing

Write-Host "📂 Collecting configuration files..." -ForegroundColor Yellow

# Collect all configuration files
$configFiles = @()
foreach ($pattern in $patterns) {
    $fullPath = Join-Path $Path $pattern
    $files = Get-ChildItem -Path $fullPath -File -ErrorAction SilentlyContinue
    if ($files) {
        $configFiles += $files
    }
}

# Also search for .mobileconfig files
$mobileConfigFiles = Get-ChildItem -Path (Join-Path $Path "configurations") -Filter "*.mobileconfig" -Recurse -File -ErrorAction SilentlyContinue
if ($mobileConfigFiles) {
    $configFiles += $mobileConfigFiles
}

Write-Host "   Found $($configFiles.Count) configuration files" -ForegroundColor Green
Write-Host ""

# Process each file
$fileCount = 0
foreach ($file in $configFiles) {
    $fileCount++
    Write-Progress -Activity "Analyzing configurations" -Status "Processing $($file.Name)" -PercentComplete (($fileCount / $configFiles.Count) * 100)
    
    $metadata = Get-ManifestMetadata -SourceFile $file.FullName
    $relativePath = $file.FullName.Replace($Path, '').TrimStart('\', '/')
    
    Write-Host "📄 Processing: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($metadata.ReferenceId)" -NoNewline -ForegroundColor Cyan
    Write-Host " - $($file.Name)" -ForegroundColor DarkGray
    
    # Extract settings based on file type
    $settings = @()
    if ($file.Extension -eq '.json') {
        $settings = Get-SettingsFromJson -FilePath $file.FullName
    }
    elseif ($file.Extension -eq '.mobileconfig') {
        $settings = Get-SettingsFromMobileConfig -FilePath $file.FullName
    }
    
    Write-Host "   Found $($settings.Count) settings:" -ForegroundColor DarkGray
    
    # Add to global collection
    foreach ($setting in $settings) {
        Write-Host "      • " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($setting.SettingId)" -NoNewline -ForegroundColor White
        
        # Show value if available
        if ($null -ne $setting.Value) {
            $displayValue = if ($setting.Value -is [bool]) { 
                $setting.Value.ToString().ToLower() 
            } 
            elseif ($setting.Value.ToString().Length -gt 50) {
                $setting.Value.ToString().Substring(0, 47) + "..."
            }
            else { 
                $setting.Value 
            }
            Write-Host " = " -NoNewline -ForegroundColor DarkGray
            Write-Host "$displayValue" -ForegroundColor Magenta
        }
        else {
            Write-Host "" # Just newline
        }
        
        $record = [PSCustomObject]@{
            SettingId = $setting.SettingId
            Value = $setting.Value
            Path = $setting.Path
            SourceFile = $relativePath
            ReferenceId = $metadata.ReferenceId
            ConfigName = $metadata.Name
            ConfigType = $metadata.Type
        }
        
        $allSettings += $record
        
        # Build index for duplicate detection
        if (-not $settingIndex.ContainsKey($setting.SettingId)) {
            $settingIndex[$setting.SettingId] = @()
        }
        $settingIndex[$setting.SettingId] += $record
    }
    
    Write-Host "" # Blank line between files
}

Write-Progress -Activity "Analyzing configurations" -Completed

#endregion

#region Find Duplicates

Write-Host "🔎 Finding duplicate settings..." -ForegroundColor Yellow
Write-Host ""

$duplicates = @()
foreach ($settingId in $settingIndex.Keys) {
    $occurrences = $settingIndex[$settingId]
    
    if ($occurrences.Count -gt 1) {
        # Group by unique source files to avoid counting same setting multiple times in same file
        # Get unique source files as strings to ensure proper deduplication
        $uniqueSourceFiles = $occurrences | Select-Object -ExpandProperty SourceFile -Unique
        
        # If the setting appears in only one file, skip it (it's a collection with multiple items, not a true duplicate)
        if ($uniqueSourceFiles.Count -le 1) {
            continue
        }
        
        # Group by source file for reporting
        $uniqueSources = $occurrences | Group-Object -Property SourceFile
        
        # Check if values conflict (different values for same setting)
        $allValues = $uniqueSources | ForEach-Object { 
            $val = $_.Group[0].Value
            if ($null -eq $val) { "<null>" } 
            elseif ($val -is [bool]) { $val.ToString().ToLower() }
            else { $val.ToString() }
        }
        $uniqueValues = $allValues | Select-Object -Unique
        $hasConflict = $uniqueValues.Count -gt 1
        
        $duplicates += [PSCustomObject]@{
            SettingId = $settingId
            OccurrenceCount = $uniqueSources.Count
            HasConflict = $hasConflict
            Configurations = ($uniqueSources | ForEach-Object { $_.Group[0].ConfigName }) -join ' | '
            ReferenceIds = ($uniqueSources | ForEach-Object { $_.Group[0].ReferenceId }) -join ', '
            Values = $allValues -join ' | '
            SourceFiles = ($uniqueSources | ForEach-Object { $_.Group[0].SourceFile }) -join ' | '
        }
    }
}

#endregion

#region Output Results

if ($duplicates.Count -eq 0) {
    Write-Host "✅ No duplicate settings found!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Total configurations analyzed: $($configFiles.Count)"
    Write-Host "  Total unique settings: $($settingIndex.Keys.Count)"
    exit 0
}

# Sort by occurrence count (most duplicated first)
$duplicates = $duplicates | Sort-Object -Property OccurrenceCount -Descending

Write-Host "⚠️  Found $($duplicates.Count) duplicate settings across configurations" -ForegroundColor Yellow
Write-Host ""

# Output based on format
switch ($OutputFormat) {
    'CSV' {
        if (-not $OutputFile) {
            $OutputFile = Join-Path $Path "duplicate-settings.csv"
        }
        $duplicates | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
        Write-Host "📄 Results saved to: $OutputFile" -ForegroundColor Green
    }
    'JSON' {
        if (-not $OutputFile) {
            $OutputFile = Join-Path $Path "duplicate-settings.json"
        }
        $duplicates | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputFile -Encoding UTF8
        Write-Host "📄 Results saved to: $OutputFile" -ForegroundColor Green
    }
    'Console' {
        Write-Host "Duplicate Settings Report" -ForegroundColor Cyan
        Write-Host ("=" * 100) -ForegroundColor Gray
        Write-Host ""
        
        # Show conflicts first
        $conflicts = $duplicates | Where-Object { $_.HasConflict }
        if ($conflicts.Count -gt 0) {
            Write-Host "⚠️  CONFLICTS - Same setting with different values:" -ForegroundColor Red
            Write-Host ""
            
            foreach ($dup in $conflicts) {
                Write-Host "Setting: " -NoNewline -ForegroundColor White
                Write-Host $dup.SettingId -ForegroundColor Yellow
                Write-Host "  ⚠️  CONFLICT DETECTED - Different values in different policies!" -ForegroundColor Red
                Write-Host "  Occurrences: " -NoNewline -ForegroundColor Gray
                Write-Host $dup.OccurrenceCount -ForegroundColor Red
                Write-Host "  Found in these policies:" -ForegroundColor Gray
                
                $configs = $dup.Configurations -split ' \| '
                $refs = $dup.ReferenceIds -split ', '
                $values = $dup.Values -split ' \| '
                $files = $dup.SourceFiles -split ' \| '
                
                for ($i = 0; $i -lt $configs.Count; $i++) {
                    Write-Host "    • " -NoNewline -ForegroundColor DarkGray
                    Write-Host "$($refs[$i])" -NoNewline -ForegroundColor Cyan
                    Write-Host " - $($configs[$i])" -ForegroundColor White
                    Write-Host "      File: " -NoNewline -ForegroundColor DarkGray
                    Write-Host "$($files[$i])" -ForegroundColor Blue
                    if ($values[$i]) {
                        Write-Host "      Value: " -NoNewline -ForegroundColor DarkGray
                        Write-Host $values[$i] -ForegroundColor Magenta
                    }
                }
                Write-Host ""
            }
            
            Write-Host ("=" * 100) -ForegroundColor Gray
            Write-Host ""
        }
        
        # Show duplicates with same values
        $sameValues = $duplicates | Where-Object { -not $_.HasConflict }
        if ($sameValues.Count -gt 0) {
            Write-Host "ℹ️  DUPLICATES - Same setting with same value (redundant):" -ForegroundColor Yellow
            Write-Host ""
            
            foreach ($dup in $sameValues) {
                Write-Host "Setting: " -NoNewline -ForegroundColor White
                Write-Host $dup.SettingId -ForegroundColor Yellow
                Write-Host "  Occurrences: " -NoNewline -ForegroundColor Gray
                Write-Host $dup.OccurrenceCount -ForegroundColor Yellow
                Write-Host "  Found in these policies:" -ForegroundColor Gray
                
                $configs = $dup.Configurations -split ' \| '
                $refs = $dup.ReferenceIds -split ', '
                $values = $dup.Values -split ' \| '
                $files = $dup.SourceFiles -split ' \| '
                
                for ($i = 0; $i -lt $configs.Count; $i++) {
                    Write-Host "    • " -NoNewline -ForegroundColor DarkGray
                    Write-Host "$($refs[$i])" -NoNewline -ForegroundColor Cyan
                    Write-Host " - $($configs[$i])" -ForegroundColor White
                    Write-Host "      File: " -NoNewline -ForegroundColor DarkGray
                    Write-Host "$($files[$i])" -ForegroundColor Blue
                    if ($values[$i]) {
                        Write-Host "      Value: " -NoNewline -ForegroundColor DarkGray
                        Write-Host $values[$i] -ForegroundColor Magenta
                    }
                }
                Write-Host ""
            }
            
            Write-Host ("=" * 100) -ForegroundColor Gray
            Write-Host ""
        }
    }
}

# Summary statistics
$conflicts = $duplicates | Where-Object { $_.HasConflict }
$redundant = $duplicates | Where-Object { -not $_.HasConflict }

Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total configurations analyzed: $($configFiles.Count)"
Write-Host "  Total settings found: $($allSettings.Count)"
Write-Host "  Total unique settings: $($settingIndex.Keys.Count)"
Write-Host "  Duplicate settings: $($duplicates.Count)" -ForegroundColor Yellow
if ($conflicts.Count -gt 0) {
    Write-Host "    - Conflicts (different values): $($conflicts.Count)" -ForegroundColor Red
}
if ($redundant.Count -gt 0) {
    Write-Host "    - Redundant (same values): $($redundant.Count)" -ForegroundColor Yellow
}
Write-Host ""

# Show most duplicated settings
if ($conflicts.Count -gt 0) {
    Write-Host "⚠️  Settings with Conflicting Values:" -ForegroundColor Red
    foreach ($dup in $conflicts) {
        Write-Host "  • $($dup.SettingId) " -NoNewline -ForegroundColor White
        Write-Host "($($dup.OccurrenceCount) configurations with different values)" -ForegroundColor Red
    }
    Write-Host ""
}

$topDuplicates = $duplicates | Select-Object -First 5
if ($topDuplicates.Count -gt 0) {
    Write-Host "Top 5 Most Duplicated Settings:" -ForegroundColor Cyan
    foreach ($dup in $topDuplicates) {
        $conflictMarker = if ($dup.HasConflict) { " ⚠️" } else { "" }
        Write-Host "  • $($dup.SettingId) " -NoNewline -ForegroundColor White
        Write-Host "($($dup.OccurrenceCount) configurations)$conflictMarker" -ForegroundColor $(if ($dup.HasConflict) { "Red" } else { "Yellow" })
    }
    Write-Host ""
}

#endregion
