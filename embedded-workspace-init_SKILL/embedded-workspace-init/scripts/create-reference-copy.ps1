[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $WorkspaceRoot,
    [Parameter(Mandatory)] [ValidatePattern('^\d{8}-[a-z0-9][a-z0-9-]{0,47}-[a-f0-9]{4}$')] [string] $WorkstreamId,
    [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')] [string] $ReferenceId,
    [Parameter(Mandatory)] [string] $Purpose,
    [string] $CleanupCondition = 'Workstream is terminal and all wanted results are retained.',
    [int] $MutexTimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/workspace-common.psm1') -Force

$context = Assert-EwiActiveWorkspace -WorkspaceRoot $WorkspaceRoot
$root = $context.root
$workstreamRoot = Join-Path $root "work/$WorkstreamId"
$referenceRoot = Join-Path $root "reference-projects/$ReferenceId"
$manifestPath = Join-Path $referenceRoot 'manifest.json'
if (-not (Test-Path -LiteralPath (Join-Path $workstreamRoot 'workstream.json') -PathType Leaf)) {
    throw "Workstream does not exist: $WorkstreamId"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Reference does not exist: $ReferenceId"
}
$workstream = Read-EwiJson -Path (Join-Path $workstreamRoot 'workstream.json') -SchemaPath (Join-Path $root 'workspace-management/schemas/workstream.schema.json')
if ($workstream.status -notin @('active', 'paused', 'blocked')) {
    throw "Cannot add a reference copy to terminal workstream state '$($workstream.status)'."
}
$manifest = Read-EwiJson -Path $manifestPath -SchemaPath (Join-Path $root 'workspace-management/schemas/reference-manifest.schema.json')
$sourceProject = Join-Path $referenceRoot 'project'
$inventory = Get-EwiFileInventory -Root $sourceProject -MappingId $ReferenceId
if (-not $inventory.scan_complete -or (Get-EwiInventoryDigest $inventory) -ne $manifest.inventory_digest) {
    throw 'Reference snapshot no longer matches its immutable manifest.'
}

$destinationRoot = Join-Path $workstreamRoot "reference-copies/$ReferenceId"
$result = Invoke-EwiLocked -WorkspaceRoot $root -TimeoutSeconds $MutexTimeoutSeconds -ScriptBlock {
    $null = Assert-EwiActiveWorkspace -WorkspaceRoot $root
    if (Test-Path -LiteralPath $destinationRoot) {
        throw "Reference copy already exists: $destinationRoot"
    }
    $current = Get-EwiFileInventory -Root $sourceProject -MappingId $ReferenceId
    if ((Get-EwiInventoryDigest $current) -ne $manifest.inventory_digest) {
        throw 'Reference snapshot changed after preflight.'
    }
    try {
        $project = Join-Path $destinationRoot 'project'
        $null = New-Item -ItemType Directory -Path $project
        $copied = Copy-EwiSnapshot -Source $sourceProject -Destination $project -MappingId $ReferenceId
        $null = Initialize-EwiGitRepository -Repository $project
        $paths = @($copied.files | ForEach-Object path)
        $commit = if ($paths.Count) {
            New-EwiGitCommit -Repository $project -Message "chore: establish reference copy baseline for $ReferenceId" -RelativePaths $paths
        }
        else {
            $null = Invoke-EwiGit -Repository $project -ArgumentList @('commit', '--allow-empty', '-m', "chore: establish reference copy baseline for $ReferenceId")
            (Invoke-EwiGit -Repository $project -ArgumentList @('rev-parse', 'HEAD')).StdOut.Trim()
        }

        $template = Get-Content -LiteralPath (Join-Path $root 'workspace-management/templates/reference-copy-README.md') -Raw -Encoding UTF8
        $readme = $template.Replace('{{REFERENCE_ID}}', $ReferenceId).
            Replace('{{REFERENCE_PATH}}', "reference-projects/$ReferenceId/project").
            Replace('{{REFERENCE_DIGEST}}', $manifest.inventory_digest).
            Replace('{{WORKSTREAM_ID}}', $WorkstreamId).
            Replace('{{CREATED_AT}}', (Get-EwiTimestamp)).
            Replace('{{PURPOSE}}', $Purpose).
            Replace('{{BUILD_STATUS}}', 'not-run').
            Replace('{{CLEANUP_CONDITION}}', $CleanupCondition)
        [IO.File]::WriteAllText((Join-Path $destinationRoot 'README.md'), $readme.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        $null = New-EwiGitCommit -Repository $root -Message "chore: add $ReferenceId to workstream $WorkstreamId" -RelativePaths @("work/$WorkstreamId/reference-copies/$ReferenceId/README.md")
        return [pscustomobject][ordered]@{
            status = 'created'
            workstream_id = $WorkstreamId
            reference_id = $ReferenceId
            path = "work/$WorkstreamId/reference-copies/$ReferenceId/project"
            baseline_commit = $commit
        }
    }
    catch {
        if (Test-Path -LiteralPath $destinationRoot) {
            $resolved = Resolve-EwiPath $destinationRoot
            $allowed = Join-Path $workstreamRoot 'reference-copies'
            if (-not (Test-EwiPathWithin -Path $resolved -Parent $allowed)) {
                throw 'Refusing to clean a partial reference copy outside its workstream.'
            }
            Get-ChildItem -LiteralPath $resolved -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
            (Get-Item -LiteralPath $resolved -Force).Attributes = 'Directory'
            [IO.Directory]::Delete($resolved, $true)
        }
        throw
    }
}

$result | ConvertTo-Json -Depth 10
