[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $WorkspaceRoot,
    [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')] [string] $SourceId,
    [Parameter(Mandatory)] [string] $MappingsJson,
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
$stateSchema = Join-Path $root 'workspace-management/schemas/source-sync-state.schema.json'
$targets = Read-EwiJson -Path $targetsPath -SchemaPath $targetsSchema
$local = Read-EwiJson -Path $localPath -SchemaPath $localSchema
$sourceProperty = $targets.sources.PSObject.Properties[$SourceId]
$localSourceProperty = $local.sources.PSObject.Properties[$SourceId]
if ($null -eq $sourceProperty -or $null -eq $localSourceProperty) { throw "Unknown source: $SourceId" }
$source = $sourceProperty.Value
$localSource = $localSourceProperty.Value
$requested = @($MappingsJson | ConvertFrom-Json -Depth 30 -ErrorAction Stop)
if ($requested.Count -eq 0) { throw 'A publishable mapping migration requires at least one directory mapping.' }

$mappingIds = @{}
$portable = [Collections.Generic.List[object]]::new()
$localMappings = [ordered]@{}
$inventories = [Collections.Generic.List[object]]::new()
foreach ($mapping in $requested) {
    $mappingId = [string]$mapping.mapping_id
    if ($mappingId -notmatch '^[a-z0-9][a-z0-9-]{0,63}$' -or $mappingIds.ContainsKey($mappingId)) { throw "Invalid or duplicate mapping id: $mappingId" }
    $mappingIds[$mappingId] = $true
    $subpath = Assert-EwiRelativePath -Path ([string]$mapping.integration_subpath) -AllowDot
    $authority = Resolve-EwiPath ([string]$mapping.source_path)
    Assert-EwiPathsSeparated -First $root -Second $authority -FirstLabel 'workspace' -SecondLabel "authority '$mappingId'"
    $inventory = Get-EwiFileInventory -Root $authority -MappingId $mappingId
    if (-not $inventory.scan_complete -or @($inventory.git_topology).Count -gt 0 -or @($inventory.sensitive).Count -gt 0 -or @($inventory.pending).Count -gt 0) {
        throw "Mapping '$mappingId' is incomplete or contains unresolved topology/content."
    }
    $portable.Add([pscustomobject][ordered]@{ mapping_id = $mappingId; integration_subpath = $subpath; kind = 'directory' })
    $oldLocal = $localSource.mappings.PSObject.Properties[$mappingId]
    $userGit = if ($null -ne $oldLocal) { $oldLocal.Value.user_git } else { [pscustomobject][ordered]@{ status = 'deferred'; repository_path = $null } }
    $localMappings[$mappingId] = [ordered]@{ source_path = $authority.Replace('\', '/'); user_git = $userGit }
    $inventories.Add([pscustomobject][ordered]@{ mapping_id = $mappingId; authority = $authority; integration_subpath = $subpath; inventory = $inventory; digest = Get-EwiInventoryDigest $inventory })
}
for ($left = 0; $left -lt $portable.Count; $left++) {
    for ($right = $left + 1; $right -lt $portable.Count; $right++) {
        $a = $portable[$left].integration_subpath
        $b = $portable[$right].integration_subpath
        if ($a -eq '.' -or $b -eq '.' -or $a -eq $b -or $a.StartsWith($b.TrimEnd('/') + '/') -or $b.StartsWith($a.TrimEnd('/') + '/')) { throw "Requested integration subpaths overlap: '$a' and '$b'." }
        Assert-EwiPathsSeparated -First $inventories[$left].authority -Second $inventories[$right].authority -FirstLabel "authority '$($portable[$left].mapping_id)'" -SecondLabel "authority '$($portable[$right].mapping_id)'"
    }
}
foreach ($otherProperty in $local.sources.PSObject.Properties | Where-Object Name -ne $SourceId) {
    foreach ($otherMapping in $otherProperty.Value.mappings.PSObject.Properties) {
        foreach ($inventory in $inventories) {
            Assert-EwiPathsSeparated -First $inventory.authority -Second ([string]$otherMapping.Value.source_path) -FirstLabel "new authority '$($inventory.mapping_id)'" -SecondLabel "existing authority '$($otherMapping.Name)'"
        }
    }
}
$newDigest = Get-EwiMappingDigest -Mappings @($portable) -LocalMappings $localMappings
$oldComparable = @($source.mappings | Sort-Object mapping_id | ForEach-Object {
    $localValue = $localSource.mappings.PSObject.Properties[[string]$_.mapping_id].Value
    [pscustomobject][ordered]@{ mapping_id = $_.mapping_id; integration_subpath = $_.integration_subpath; kind = $_.kind; source_identity = Get-EwiPathIdentity ([string]$localValue.source_path) }
})
$newComparable = @($portable | Sort-Object mapping_id | ForEach-Object {
    [pscustomobject][ordered]@{ mapping_id = $_.mapping_id; integration_subpath = $_.integration_subpath; kind = $_.kind; source_identity = Get-EwiPathIdentity ([string]$localMappings[[string]$_.mapping_id].source_path) }
})
$changed = (ConvertTo-EwiCanonicalJson $oldComparable) -cne (ConvertTo-EwiCanonicalJson $newComparable)
$nonterminal = @(Get-ChildItem -LiteralPath (Join-Path $root 'workspace-management/sync-state/transactions') -Filter '*.json' -File | Where-Object {
    $transaction = Read-EwiJson -Path $_.FullName -SchemaPath (Join-Path $root 'workspace-management/schemas/publish-transaction.schema.json')
    $transaction.state -notin @('completed', 'conflicted', 'rolled_back') -and $null -ne $transaction.mapping_revisions.PSObject.Properties[$SourceId]
})
[object[]]$blockers = @()
if ($nonterminal.Count) { $blockers = @('A nonterminal publish/recovery transaction uses this source.') }
$statePath = Join-Path $root "workspace-management/sync-state/sources/$SourceId.json"
$indexPath = Join-Path $root "workspace-management/sync-state/indexes/$SourceId.jsonl"
$payload = [pscustomobject][ordered]@{
    schema = 1; operation = 'mapping-migration'; workspace_root = $root; source_id = $SourceId
    old_revision = [int]$source.mapping_revision; new_revision = [int]$source.mapping_revision + 1; old_mappings = @($source.mappings)
    new_mappings = @($portable); local_mappings = [pscustomobject]$localMappings; inventory_digests = @($inventories | ForEach-Object { [pscustomobject][ordered]@{ mapping_id = $_.mapping_id; digest = $_.digest } })
    targets_hash = Get-EwiSha256 $targetsPath; local_hash = Get-EwiSha256 $localPath; state_hash = Get-EwiSha256 $statePath; index_hash = Get-EwiSha256 $indexPath
}
$planDigest = Get-EwiTextSha256 (ConvertTo-EwiCanonicalJson $payload)
$report = [pscustomobject][ordered]@{
    status = 'report-only'; source_id = $SourceId; old_revision = [int]$source.mapping_revision
    new_revision = if ($changed) { [int]$source.mapping_revision + 1 } else { [int]$source.mapping_revision }
    old_mappings = @($source.mappings); new_mappings = @($portable); mapping_digest = $newDigest
    blockers = $blockers; approval_required = $changed; plan_digest = $planDigest; can_apply = ($changed -and $blockers.Count -eq 0); changed = $false
}
if (-not $Apply) { $report | ConvertTo-Json -Depth 30; return }
if (-not $report.can_apply) { throw "Mapping migration is not applicable: $([string]::Join('; ', $blockers))" }
if ([string]::IsNullOrWhiteSpace($ExpectedPlanDigest) -or $ExpectedPlanDigest -ne $planDigest) { throw 'Current mapping plan does not match the explicitly approved digest.' }

$integration = Join-EwiContainedPath -Root $root -RelativePath ([string]$source.integration_path)
$state = Read-EwiJson -Path $statePath -SchemaPath $stateSchema
$oldHead = (Invoke-EwiGit -Repository $integration -ArgumentList @('rev-parse', 'HEAD')).StdOut.Trim()
if (-not [string]::IsNullOrWhiteSpace((Invoke-EwiGit -Repository $integration -ArgumentList @('status', '--porcelain=v1')).StdOut)) { throw 'Integration must be clean before mapping migration.' }
$targetsOriginal = [IO.File]::ReadAllBytes($targetsPath)
$localOriginal = [IO.File]::ReadAllBytes($localPath)
$stateOriginal = [IO.File]::ReadAllBytes($statePath)
$indexOriginal = [IO.File]::ReadAllBytes($indexPath)
$managementHead = (Invoke-EwiGit -Repository $root -ArgumentList @('rev-parse', 'HEAD')).StdOut.Trim()
$newBaselineRef = $null
$migrationId = 'mapping-' + [DateTimeOffset]::Now.ToString('yyyyMMddHHmmssfff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
$staging = Join-Path $root "workspace-management/recovery/$migrationId/staging"
$result = Invoke-EwiLocked -WorkspaceRoot $root -TimeoutSeconds $MutexTimeoutSeconds -ScriptBlock {
    $null = Assert-EwiActiveWorkspace -WorkspaceRoot $root
    foreach ($pair in @(@($targetsPath, $payload.targets_hash), @($localPath, $payload.local_hash), @($statePath, $payload.state_hash), @($indexPath, $payload.index_hash))) {
        if ((Get-EwiSha256 $pair[0]) -ne $pair[1]) { throw 'Mapping state changed after planning.' }
    }
    try {
        $null = New-Item -ItemType Directory -Path $staging -Force
        $newEntries = [Collections.Generic.List[object]]::new()
        $newGitPaths = [Collections.Generic.List[string]]::new()
        foreach ($inventory in $inventories) {
            $current = Get-EwiFileInventory -Root $inventory.authority -MappingId $inventory.mapping_id
            if (-not $current.scan_complete -or @($current.git_topology).Count -gt 0 -or @($current.sensitive).Count -gt 0 -or @($current.pending).Count -gt 0 -or (Get-EwiInventoryDigest $current) -ne $inventory.digest) { throw "Authority changed after mapping planning: $($inventory.mapping_id)" }
            $destination = Join-EwiContainedPath -Root $staging -RelativePath $inventory.integration_subpath -AllowDot
            $copied = Copy-EwiSnapshot -Source $inventory.authority -Destination $destination -MappingId $inventory.mapping_id
            foreach ($entry in @($copied.files)) {
                $newEntries.Add($entry)
                $newGitPaths.Add($(if ($inventory.integration_subpath -eq '.') { [string]$entry.path } else { "$($inventory.integration_subpath)/$($entry.path)" }))
            }
        }
        $oldGitPaths = @(((Invoke-EwiGit -Repository $integration -ArgumentList @('ls-files', '-z')).StdOut).Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))
        foreach ($relative in $oldGitPaths) {
            $file = Join-EwiContainedPath -Root $integration -RelativePath $relative
            if (Test-Path -LiteralPath $file -PathType Leaf) { [IO.File]::Delete($file) }
        }
        foreach ($relative in $newGitPaths) {
            $sourceFile = Join-EwiContainedPath -Root $staging -RelativePath $relative
            $targetFile = Join-EwiContainedPath -Root $integration -RelativePath $relative
            $parent = Split-Path -Parent $targetFile
            if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent }
            [IO.File]::Copy($sourceFile, $targetFile, $true)
        }
        $allGitPaths = @($oldGitPaths + @($newGitPaths) | Sort-Object -Unique)
        $newCommit = New-EwiGitCommit -Repository $integration -Message "chore: apply mapping revision $($payload.new_revision)" -RelativePaths $allGitPaths
        if (-not $newCommit) { throw 'Changed mappings did not produce a source-private baseline commit.' }

        $currentTargets = Read-EwiJson -Path $targetsPath -SchemaPath $targetsSchema
        $currentLocal = Read-EwiJson -Path $localPath -SchemaPath $localSchema
        $currentSource = $currentTargets.sources.PSObject.Properties[$SourceId].Value
        $oldMappingsById = @{}
        foreach ($mapping in @($currentSource.mappings)) { $oldMappingsById[[string]$mapping.mapping_id] = $mapping }
        $newMappingsById = @{}
        foreach ($mapping in @($portable)) { $newMappingsById[[string]$mapping.mapping_id] = $mapping }
        foreach ($targetProperty in $currentTargets.targets.PSObject.Properties | Where-Object { $_.Value.source -eq $SourceId }) {
            $targetPath = ([string]$targetProperty.Value.path).Replace('\', '/')
            foreach ($mappingId in $oldMappingsById.Keys) {
                if (-not $newMappingsById.ContainsKey($mappingId)) { continue }
                $oldSubpath = [string]$oldMappingsById[$mappingId].integration_subpath
                $relative = if ($oldSubpath -eq '.') { $targetPath } elseif ($targetPath -eq $oldSubpath) { '.' } elseif ($targetPath.StartsWith($oldSubpath.TrimEnd('/') + '/')) { $targetPath.Substring($oldSubpath.TrimEnd('/').Length + 1) } else { $null }
                if ($null -ne $relative) {
                    $newSubpath = [string]$newMappingsById[$mappingId].integration_subpath
                    $targetProperty.Value.path = if ($newSubpath -eq '.') { $relative } elseif ($relative -eq '.') { $newSubpath } else { "$newSubpath/$relative" }
                    break
                }
            }
            foreach ($metaProperty in $currentTargets.field_metadata.PSObject.Properties | Where-Object Name -like "/targets/$($targetProperty.Name)/*") { $metaProperty.Value.freshness = 'stale' }
        }
        $currentSource.user_source = 'configured'
        $currentSource.write_policy = 'explicit-publish-only'
        $currentSource.sync_strategy = 'three-way'
        $currentSource.mapping_revision = [int]$payload.new_revision
        $currentSource.mappings = @($portable)
        $currentLocal.sources.PSObject.Properties[$SourceId].Value.mappings = [pscustomobject]$localMappings
        Write-EwiJsonAtomic -Path $targetsPath -Value $currentTargets -SchemaPath $targetsSchema
        Write-EwiJsonAtomic -Path $localPath -Value $currentLocal -SchemaPath $localSchema
        Write-EwiJsonLinesAtomic -Path $indexPath -Records @($newEntries) -SchemaPath (Join-Path $root 'workspace-management/schemas/file-index-record.schema.json')
        $baselineId = 'baseline-' + [DateTimeOffset]::Now.ToString('yyyyMMddHHmmssfff')
        $newBaselineRef = "refs/agent/user-baselines/$baselineId"
        $null = Invoke-EwiGit -Repository $integration -ArgumentList @('update-ref', $newBaselineRef, $newCommit)
        $currentState = Read-EwiJson -Path $statePath -SchemaPath $stateSchema
        $currentState.mapping_revision = [int]$payload.new_revision
        $currentState.mapping_digest = $newDigest
        $currentState.user_baseline_id = $baselineId
        $currentState.user_baseline_commit = $newCommit
        $currentState.user_baseline_ref = $newBaselineRef
        $currentState.captured_at = Get-EwiTimestamp
        $currentState.scan_complete = $true
        Write-EwiJsonAtomic -Path $statePath -Value $currentState -SchemaPath $stateSchema
        $managementCommit = New-EwiGitCommit -Repository $root -Message "chore: migrate $SourceId mappings to revision $($payload.new_revision)" -RelativePaths @('workspace-management/config/targets.json')
        $evidenceId = New-EwiEvidenceId 'mapping-migration'
        $null = Write-EwiEvidence -WorkspaceRoot $root -EvidenceId $evidenceId -Kind migration `
            -Subject ([pscustomobject][ordered]@{ workspace = $root; source_id = $SourceId; target_id = $null; build_id = $null; workstream_id = $null; publish_id = $null; reference_id = $null }) `
            -Result ([pscustomobject][ordered]@{ status = 'passed'; summary = "Migrated source '$SourceId' to mapping revision $($payload.new_revision)."; exit_code = 0; details = [pscustomobject][ordered]@{ old_revision = $payload.old_revision; new_revision = $payload.new_revision; user_baseline_commit = $newCommit; management_commit = $managementCommit } }) -Artifacts @()
        return [pscustomobject][ordered]@{ status = 'migrated'; source_id = $SourceId; old_revision = $payload.old_revision; new_revision = $payload.new_revision; user_baseline_commit = $newCommit; user_baseline_ref = $newBaselineRef; management_commit = $managementCommit; evidence = "workspace-management/evidence/$evidenceId.json" }
    }
    catch {
        $null = Invoke-EwiGit -Repository $root -ArgumentList @('reset', '--mixed', $managementHead) -AllowFailure
        $null = Invoke-EwiGit -Repository $integration -ArgumentList @('reset', '--hard', $oldHead) -AllowFailure
        if ($newBaselineRef) { $null = Invoke-EwiGit -Repository $integration -ArgumentList @('update-ref', '-d', $newBaselineRef) -AllowFailure }
        [IO.File]::WriteAllBytes($targetsPath, $targetsOriginal)
        [IO.File]::WriteAllBytes($localPath, $localOriginal)
        [IO.File]::WriteAllBytes($statePath, $stateOriginal)
        [IO.File]::WriteAllBytes($indexPath, $indexOriginal)
        $null = Invoke-EwiGit -Repository $root -ArgumentList @('reset', '--', 'workspace-management/config/targets.json') -AllowFailure
        throw
    }
    finally {
        $recoveryRoot = Split-Path -Parent $staging
        if (Test-Path -LiteralPath $recoveryRoot) {
            Get-ChildItem -LiteralPath $recoveryRoot -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
            (Get-Item -LiteralPath $recoveryRoot -Force).Attributes = 'Directory'
            [IO.Directory]::Delete($recoveryRoot, $true)
        }
    }
}

$result | ConvertTo-Json -Depth 30
