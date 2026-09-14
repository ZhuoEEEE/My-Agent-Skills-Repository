[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $WorkspaceRoot,
    [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')] [string] $TargetId,
    [Parameter(Mandatory)] [string] $ConfigurationJson,
    [ValidateSet('detected', 'confirmed', 'imported')] [string] $Provenance = 'detected',
    [ValidatePattern('^[0-9a-f]{64}$')] [string] $ExpectedPlanDigest,
    [switch] $Apply,
    [int] $MutexTimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/workspace-common.psm1') -Force

$context = Assert-EwiActiveWorkspace -WorkspaceRoot $WorkspaceRoot
$root = $context.root
$targetsPath = Join-Path $root 'workspace-management/config/targets.json'
$localPath = Join-Path $root 'workspace-management/config/targets.local.json'
$targetsSchema = Join-Path $root 'workspace-management/schemas/targets.schema.json'
$localSchema = Join-Path $root 'workspace-management/schemas/targets-local.schema.json'
$targets = Read-EwiJson -Path $targetsPath -SchemaPath $targetsSchema
$local = Read-EwiJson -Path $localPath -SchemaPath $localSchema
$targetProperty = $targets.targets.PSObject.Properties[$TargetId]
if ($null -eq $targetProperty) { throw "Unknown target: $TargetId" }
$config = $ConfigurationJson | ConvertFrom-Json -Depth 30 -ErrorAction Stop
$buildId = [string]$config.build_id
if ($buildId -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw "Invalid build id: $buildId" }
if ([string]::IsNullOrWhiteSpace([string]$config.configuration)) { throw 'Build configuration display name is required.' }
$cwd = Assert-EwiRelativePath -Path ([string]$config.cwd) -AllowDot
$toolId = [string]$config.command.tool
if ($toolId -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw "Invalid tool id: $toolId" }
$commandState = [string]$config.command_state
if ($commandState -notin @('candidate', 'verified', 'unavailable', 'unconfirmed', 'stale')) { throw "Invalid command state: $commandState" }
if ($commandState -eq 'verified') { throw 'Configuration registration cannot claim verified without a successful build evidence run.' }
$toolExecutable = if ($config.PSObject.Properties.Name -contains 'tool_executable' -and $config.tool_executable) { Resolve-EwiPath ([string]$config.tool_executable) } else { $null }
$toolVersion = if ($config.PSObject.Properties.Name -contains 'tool_version') { $config.tool_version } else { $null }
if ($commandState -in @('candidate', 'unconfirmed', 'stale') -and $null -eq $toolExecutable -and $null -eq $local.tools.PSObject.Properties[$toolId]) {
    throw "An executable path is required for runnable tool '$toolId'."
}

function Normalize-Paths {
    param([object[]] $Values)
    $result = [Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($value in $Values) {
        $path = (Assert-EwiRelativePath -Path ([string]$value) -AllowDot).Replace('\', '/')
        $key = $path.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "Duplicate declared build path: $path" }
        $seen[$key] = $true
        $result.Add($path)
    }
    return @($result)
}

function Get-Prefix {
    param([string] $Value)
    $prefix = ($Value -split '[*?\[]', 2)[0].TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($prefix)) { return '.' }
    return $prefix
}

function Test-Overlap {
    param([string] $First, [string] $Second)
    $a = Get-Prefix $First
    $b = Get-Prefix $Second
    return $a -eq '.' -or $b -eq '.' -or $a -eq $b -or $a.StartsWith($b.TrimEnd('/') + '/', [StringComparison]::OrdinalIgnoreCase) -or $b.StartsWith($a.TrimEnd('/') + '/', [StringComparison]::OrdinalIgnoreCase)
}

$outputPaths = @(Normalize-Paths @($config.output_paths))
$generatedPaths = @(Normalize-Paths @($config.generated_write_paths))
$outputs = @(Normalize-Paths @($config.outputs))
if (($outputPaths.Count -gt 0 -or $generatedPaths.Count -gt 0) -and $Provenance -ne 'confirmed') {
    throw 'output_paths and generated_write_paths may be persisted only with confirmed provenance.'
}
foreach ($outputPath in $outputPaths) {
    foreach ($generatedPath in $generatedPaths) {
        if (Test-Overlap $outputPath $generatedPath) { throw "Build output path '$outputPath' overlaps generated-write path '$generatedPath'." }
    }
}
$build = [pscustomobject][ordered]@{
    configuration = [string]$config.configuration
    cwd = $cwd
    default_execution_context = 'agent-copy'
    command = [pscustomobject][ordered]@{ tool = $toolId; args = @($config.command.args | ForEach-Object { [string]$_ }) }
    command_state = $commandState
    output_paths = @($outputPaths)
    generated_write_paths = @($generatedPaths)
    outputs = @($outputs)
}
$existingBuild = $targetProperty.Value.builds.PSObject.Properties[$buildId]
$existingComparable = if ($null -eq $existingBuild) { $null } else { ConvertTo-EwiCanonicalJson $existingBuild.Value }
$newComparable = ConvertTo-EwiCanonicalJson $build
$existingTool = $local.tools.PSObject.Properties[$toolId]
$existingToolComparable = if ($null -eq $existingTool) { $null } else { ConvertTo-EwiCanonicalJson $existingTool.Value }
$newToolComparable = if ($null -eq $toolExecutable) { $existingToolComparable } else { ConvertTo-EwiCanonicalJson ([pscustomobject][ordered]@{ executable = $toolExecutable.Replace('\', '/'); version = $toolVersion }) }
$targetsHash = Get-EwiSha256 $targetsPath
$localHash = Get-EwiSha256 $localPath
$payload = [pscustomobject][ordered]@{
    schema = 1; operation = 'set-build-config'; workspace_root = $root; target_id = $TargetId; build_id = $buildId
    build = $build; provenance = $Provenance; tool_id = $toolId; tool_executable = $toolExecutable; tool_version = $toolVersion
    targets_hash = $targetsHash; local_hash = $localHash
}
$digest = Get-EwiTextSha256 (ConvertTo-EwiCanonicalJson $payload)
$changed = $existingComparable -cne $newComparable -or $existingToolComparable -cne $newToolComparable
$report = [pscustomobject][ordered]@{
    status = 'report-only'; target_id = $TargetId; build_id = $buildId; build = $build; tool_id = $toolId
    tool_executable = $toolExecutable; tool_version = $toolVersion; provenance = $Provenance
    approval_required = $changed; plan_digest = $digest; can_apply = $changed; changed = $false
}
if (-not $Apply) { $report | ConvertTo-Json -Depth 20; return }
if (-not $report.can_apply) { throw 'Build configuration is unchanged.' }
if ([string]::IsNullOrWhiteSpace($ExpectedPlanDigest) -or $ExpectedPlanDigest -ne $digest) { throw 'Current build configuration plan does not match the explicitly approved digest.' }

$targetsOriginal = [IO.File]::ReadAllBytes($targetsPath)
$localOriginal = [IO.File]::ReadAllBytes($localPath)
$result = Invoke-EwiLocked -WorkspaceRoot $root -TimeoutSeconds $MutexTimeoutSeconds -ScriptBlock {
    $null = Assert-EwiActiveWorkspace -WorkspaceRoot $root
    if ((Get-EwiSha256 $targetsPath) -ne $targetsHash -or (Get-EwiSha256 $localPath) -ne $localHash) { throw 'Build configuration changed after planning.' }
    try {
        $currentTargets = Read-EwiJson -Path $targetsPath -SchemaPath $targetsSchema
        $currentLocal = Read-EwiJson -Path $localPath -SchemaPath $localSchema
        $currentBuild = $currentTargets.targets.PSObject.Properties[$TargetId].Value.builds.PSObject.Properties[$buildId]
        if ($null -eq $currentBuild) { $currentTargets.targets.PSObject.Properties[$TargetId].Value.builds | Add-Member -NotePropertyName $buildId -NotePropertyValue $build }
        else { $currentBuild.Value = $build }
        if ($null -ne $toolExecutable) {
            $tool = [pscustomobject][ordered]@{ executable = $toolExecutable.Replace('\', '/'); version = $toolVersion }
            $currentTool = $currentLocal.tools.PSObject.Properties[$toolId]
            if ($null -eq $currentTool) { $currentLocal.tools | Add-Member -NotePropertyName $toolId -NotePropertyValue $tool }
            else { $currentTool.Value = $tool }
        }
        foreach ($field in @('command', 'output_paths', 'generated_write_paths')) {
            $pointer = "/targets/$TargetId/builds/$buildId/$field"
            $metadata = [pscustomobject][ordered]@{ provenance = $Provenance; verification = 'unverified'; freshness = 'current' }
            $existing = $currentTargets.field_metadata.PSObject.Properties[$pointer]
            if ($null -eq $existing) { $currentTargets.field_metadata | Add-Member -NotePropertyName $pointer -NotePropertyValue $metadata }
            else { $existing.Value = $metadata }
        }
        Write-EwiJsonAtomic -Path $targetsPath -Value $currentTargets -SchemaPath $targetsSchema
        Write-EwiJsonAtomic -Path $localPath -Value $currentLocal -SchemaPath $localSchema
        $commit = New-EwiGitCommit -Repository $root -Message "chore: configure build $TargetId/$buildId" -RelativePaths @('workspace-management/config/targets.json')
        return [pscustomobject][ordered]@{ status = 'configured'; target_id = $TargetId; build_id = $buildId; command_state = $commandState; management_commit = $commit }
    }
    catch {
        [IO.File]::WriteAllBytes($targetsPath, $targetsOriginal)
        [IO.File]::WriteAllBytes($localPath, $localOriginal)
        $null = Invoke-EwiGit -Repository $root -ArgumentList @('reset', '--', 'workspace-management/config/targets.json') -AllowFailure
        throw
    }
}

$result | ConvertTo-Json -Depth 10
