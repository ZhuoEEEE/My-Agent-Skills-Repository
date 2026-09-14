[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $WorkspaceRoot,
    [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')] [string] $SourceId,
    [Parameter(Mandatory)] [ValidateSet('Enable', 'Disable')] [string] $Decision,
    [ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')] [string] $MappingId,
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
$source = $targets.sources.PSObject.Properties[$SourceId]
$localSource = $local.sources.PSObject.Properties[$SourceId]
if ($null -eq $source -or $null -eq $localSource -or $source.Value.user_source -ne 'configured') {
    throw "Source has no user authority Git choice: $SourceId"
}
$mappingNames = @($localSource.Value.mappings.PSObject.Properties.Name)
if ([string]::IsNullOrWhiteSpace($MappingId)) {
    if ($mappingNames.Count -ne 1) { throw 'A source with multiple authority mappings requires -MappingId.' }
    $MappingId = $mappingNames[0]
}
if ($MappingId -notin $mappingNames) { throw "Unknown authority mapping: $MappingId" }
$mapping = $localSource.Value.mappings.PSObject.Properties[$MappingId].Value
$authority = Resolve-EwiPath ([string]$mapping.source_path)
$inventory = Get-EwiFileInventory -Root $authority -MappingId $MappingId
if (-not $inventory.scan_complete -or @($inventory.git_topology).Count -gt 0) {
    throw 'User Git planning stopped for linked-worktree, nested Git, link, or unreadable topology.'
}
if (@($inventory.sensitive).Count -gt 0 -or @($inventory.pending).Count -gt 0) {
    throw 'User Git planning stopped for unresolved sensitive or ambiguous-license files.'
}
if (Test-Path -LiteralPath (Join-Path $authority '.gitmodules') -PathType Leaf) { throw 'User Git planning stopped for submodule metadata.' }
$attributes = Join-Path $authority '.gitattributes'
if ((Test-Path -LiteralPath $attributes -PathType Leaf) -and @(Select-String -LiteralPath $attributes -Pattern 'filter=lfs' -SimpleMatch).Count -gt 0) {
    throw 'User Git planning stopped for Git LFS metadata.'
}

$gitProbe = Invoke-EwiProcess -Executable 'git' -ArgumentList @('-C', $authority, 'rev-parse', '--show-toplevel') -WorkingDirectory $authority -AllowFailure
$gitExists = $gitProbe.ExitCode -eq 0
$repositoryRoot = if ($gitExists) { Resolve-EwiPath $gitProbe.StdOut.Trim() } else { $authority }
Assert-EwiPathsSeparated -First $root -Second $repositoryRoot -FirstLabel 'workspace' -SecondLabel 'user Git repository'
$gitMarker = Join-Path $repositoryRoot '.git'
$report = [pscustomobject][ordered]@{
    status = 'report-only'
    source_id = $SourceId
    mapping_id = $MappingId
    decision = $Decision.ToLowerInvariant()
    repository_root = $repositoryRoot
    existing_git = [bool]$gitExists
    file_count = @($inventory.files).Count
    excluded = @($inventory.excluded)
    warnings = @($inventory.warnings)
    would_create_gitignore = ($Decision -eq 'Enable' -and -not $gitExists -and -not (Test-Path -LiteralPath (Join-Path $authority '.gitignore')))
    would_create_baseline = ($Decision -eq 'Enable' -and -not $gitExists)
    can_apply = $true
}
if (-not $Apply) {
    $report | ConvertTo-Json -Depth 10
    return
}

$inventoryDigest = Get-EwiInventoryDigest $inventory
$result = Invoke-EwiLocked -WorkspaceRoot $root -TimeoutSeconds $MutexTimeoutSeconds -ScriptBlock {
    $null = Assert-EwiActiveWorkspace -WorkspaceRoot $root
    $currentLocal = Read-EwiJson -Path $localPath -SchemaPath $localSchema
    $currentMapping = $currentLocal.sources.PSObject.Properties[$SourceId].Value.mappings.PSObject.Properties[$MappingId].Value
    if ((Get-EwiPathIdentity ([string]$currentMapping.source_path)) -ne (Get-EwiPathIdentity $authority)) { throw 'Authority mapping changed after user Git planning.' }
    $currentInventory = Get-EwiFileInventory -Root $authority -MappingId $MappingId
    if (-not $currentInventory.scan_complete -or @($currentInventory.git_topology).Count -gt 0 -or @($currentInventory.sensitive).Count -gt 0 -or @($currentInventory.pending).Count -gt 0 -or
        (Get-EwiInventoryDigest $currentInventory) -ne $inventoryDigest) {
        throw 'Authority content or topology changed after user Git planning.'
    }

    if ($Decision -eq 'Disable') {
        $currentMapping.user_git.status = 'disabled'
        $currentMapping.user_git.repository_path = $null
        Write-EwiJsonAtomic -Path $localPath -Value $currentLocal -SchemaPath $localSchema
        return [pscustomobject][ordered]@{ status = 'disabled'; source_id = $SourceId; mapping_id = $MappingId; repository_root = $repositoryRoot; baseline_commit = $null; existing_git = [bool]$gitExists }
    }

    $createdGit = $false
    $createdIgnore = $false
    try {
        $baseline = $null
        if (-not $gitExists) {
            $ignorePath = Join-Path $repositoryRoot '.gitignore'
            if (-not (Test-Path -LiteralPath $ignorePath)) {
                $ignore = @('.metadata/', '.pio/', '.vs/', 'Debug/', 'Release/', 'build/', 'dist/', 'out/') -join [Environment]::NewLine
                [IO.File]::WriteAllText($ignorePath, $ignore + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
                $createdIgnore = $true
            }
            $null = Initialize-EwiGitRepository -Repository $repositoryRoot
            $createdGit = $true
            $paths = [Collections.Generic.List[string]]::new()
            foreach ($entry in @($currentInventory.files)) { $paths.Add([string]$entry.path) }
            if (-not $paths.Contains('.gitignore')) { $paths.Add('.gitignore') }
            $baseline = New-EwiGitCommit -Repository $repositoryRoot -Message 'chore: establish embedded project baseline' -RelativePaths @($paths)
            if (-not $baseline) {
                $null = Invoke-EwiGit -Repository $repositoryRoot -ArgumentList @('commit', '--allow-empty', '-m', 'chore: establish embedded project baseline')
                $baseline = (Invoke-EwiGit -Repository $repositoryRoot -ArgumentList @('rev-parse', 'HEAD')).StdOut.Trim()
            }
        }
        $currentMapping.user_git.status = 'enabled'
        $currentMapping.user_git.repository_path = $repositoryRoot.Replace('\', '/')
        Write-EwiJsonAtomic -Path $localPath -Value $currentLocal -SchemaPath $localSchema
        return [pscustomobject][ordered]@{ status = 'enabled'; source_id = $SourceId; mapping_id = $MappingId; repository_root = $repositoryRoot; baseline_commit = $baseline; existing_git = [bool]$gitExists }
    }
    catch {
        if ($createdGit -and (Test-Path -LiteralPath $gitMarker)) {
            Get-ChildItem -LiteralPath $gitMarker -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
            (Get-Item -LiteralPath $gitMarker -Force).Attributes = 'Directory'
            [IO.Directory]::Delete($gitMarker, $true)
        }
        if ($createdIgnore -and (Test-Path -LiteralPath (Join-Path $repositoryRoot '.gitignore'))) { [IO.File]::Delete((Join-Path $repositoryRoot '.gitignore')) }
        throw
    }
}

$evidenceId = New-EwiEvidenceId 'user-git'
$null = Write-EwiEvidence -WorkspaceRoot $root -EvidenceId $evidenceId -Kind 'workspace-validation' `
    -Subject ([pscustomobject][ordered]@{ workspace = $root; source_id = $SourceId; target_id = $null; build_id = $null; workstream_id = $null; publish_id = $null; reference_id = $null }) `
    -Result ([pscustomobject][ordered]@{ status = 'passed'; summary = "Recorded the explicit user Git decision '$($result.status)' for mapping '$MappingId'."; exit_code = 0; details = [pscustomobject][ordered]@{ repository_root = $repositoryRoot; existing_git = $result.existing_git; baseline_commit = $result.baseline_commit } }) -Artifacts @()
$result | Add-Member -NotePropertyName evidence -NotePropertyValue "workspace-management/evidence/$evidenceId.json"
$result | ConvertTo-Json -Depth 10
