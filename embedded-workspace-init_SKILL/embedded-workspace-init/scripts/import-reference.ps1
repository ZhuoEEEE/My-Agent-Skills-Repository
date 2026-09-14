[CmdletBinding(DefaultParameterSetName = 'Local')]
param(
    [Parameter(Mandatory)] [string] $WorkspaceRoot,
    [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')] [string] $ReferenceId,
    [Parameter(Mandatory, ParameterSetName = 'Local')] [string] $SourcePath,
    [Parameter(Mandatory, ParameterSetName = 'Git')] [uri] $SourceUrl,
    [Parameter(Mandatory, ParameterSetName = 'Git')] [string] $Revision,
    [Parameter(Mandatory)] [string] $Purpose,
    [string[]] $ApplicableTarget = @(),
    [string] $License = 'unknown-needs-review',
    [string] $KnownDifferences = 'none recorded',
    [switch] $Apply,
    [int] $MutexTimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/workspace-common.psm1') -Force

$context = Assert-EwiActiveWorkspace -WorkspaceRoot $WorkspaceRoot
$root = $context.root
$referenceRoot = Join-Path $root "reference-projects/$ReferenceId"
$referenceIndexPath = Join-Path $root 'reference-projects/README.md'
if (Test-Path -LiteralPath $referenceRoot) {
    throw "Reference id already exists and will not be overwritten: $ReferenceId"
}

if ($PSCmdlet.ParameterSetName -eq 'Git' -and -not $Apply) {
    [pscustomobject][ordered]@{
        status = 'report-only'
        reference_id = $ReferenceId
        source = $SourceUrl.AbsoluteUri
        revision = $Revision
        can_apply = $true
        note = 'Remote content is fetched only during an explicitly applied import.'
    } | ConvertTo-Json -Depth 5
    return
}

$temporaryClone = $null
try {
    if ($PSCmdlet.ParameterSetName -eq 'Git') {
        $temporaryClone = Join-Path ([IO.Path]::GetTempPath()) ('embedded-reference-' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $temporaryClone
        $null = Invoke-EwiProcess -Executable 'git' -ArgumentList @('clone', '--no-checkout', '--', $SourceUrl.AbsoluteUri, $temporaryClone) -WorkingDirectory (Split-Path -Parent $temporaryClone)
        $null = Invoke-EwiProcess -Executable 'git' -ArgumentList @('-C', $temporaryClone, 'checkout', '--detach', $Revision) -WorkingDirectory $temporaryClone
        $resolvedRevision = (Invoke-EwiProcess -Executable 'git' -ArgumentList @('-C', $temporaryClone, 'rev-parse', 'HEAD') -WorkingDirectory $temporaryClone).StdOut.Trim()
        $source = Resolve-EwiPath $temporaryClone
        $sourceLabel = $SourceUrl.AbsoluteUri
        $version = $resolvedRevision
    }
    else {
        $source = Resolve-EwiPath $SourcePath
        $sourceLabel = $source
        $version = $null
    }
    Assert-EwiPathsSeparated -First $root -Second $source -FirstLabel 'workspace' -SecondLabel 'reference source'
    $inventory = Get-EwiFileInventory -Root $source -MappingId $ReferenceId
    if (-not $inventory.scan_complete -or @($inventory.git_topology).Count -gt 0) { throw 'Reference scan is incomplete or contains linked-worktree/nested Git topology.' }
    if (@($inventory.sensitive).Count -gt 0) {
        throw "Reference contains files requiring sensitive-content review: $([string]::Join(', ', @($inventory.sensitive)))"
    }
    if (@($inventory.pending).Count -gt 0) {
        throw "Reference contains ambiguous license or activation files requiring confirmation: $([string]::Join(', ', @($inventory.pending)))"
    }

    $report = [pscustomobject][ordered]@{
        status = 'report-only'
        reference_id = $ReferenceId
        source = $sourceLabel
        version = $version
        file_count = @($inventory.files).Count
        inventory_digest = Get-EwiInventoryDigest $inventory
        excluded = @($inventory.excluded)
        pending = @($inventory.pending)
        warnings = @($inventory.warnings)
        can_apply = $true
    }
    if (-not $Apply) {
        $report | ConvertTo-Json -Depth 10
        return
    }

    $applied = Invoke-EwiLocked -WorkspaceRoot $root -TimeoutSeconds $MutexTimeoutSeconds -ScriptBlock {
        $null = Assert-EwiActiveWorkspace -WorkspaceRoot $root
        if (Test-Path -LiteralPath $referenceRoot) { throw "Reference appeared during planning: $ReferenceId" }
        $currentInventory = Get-EwiFileInventory -Root $source -MappingId $ReferenceId
        if ((Get-EwiInventoryDigest $currentInventory) -ne $report.inventory_digest) {
            throw 'Reference source changed after inventory; rerun the import.'
        }

        $projectRoot = Join-Path $referenceRoot 'project'
        $referenceIndexOriginal = [IO.File]::ReadAllBytes($referenceIndexPath)
        try {
            $null = New-Item -ItemType Directory -Path $projectRoot
            $copied = Copy-EwiSnapshot -Source $source -Destination $projectRoot -MappingId $ReferenceId
            $manifest = [pscustomobject][ordered]@{
                schema = 1
                reference_id = $ReferenceId
                source = $sourceLabel
                captured_at = Get-EwiTimestamp
                version = $version
                inventory_digest = Get-EwiInventoryDigest $copied
                files = @($copied.files | ForEach-Object {
                    [pscustomobject][ordered]@{
                        path = $_.path
                        type = $_.type
                        size = $_.size
                        sha256 = $_.sha256
                    }
                })
            }
            $manifestPath = Join-Path $referenceRoot 'manifest.json'
            $manifestSchema = Join-Path $root 'workspace-management/schemas/reference-manifest.schema.json'
            Write-EwiJsonAtomic -Path $manifestPath -Value $manifest -SchemaPath $manifestSchema

            $templatePath = Join-Path $root 'workspace-management/templates/reference-project-README.md'
            $readme = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
            $readme = $readme.Replace('{{REFERENCE_ID}}', $ReferenceId).
                Replace('{{SOURCE}}', $sourceLabel).
                Replace('{{CAPTURED_AT}}', $manifest.captured_at).
                Replace('{{VERSION}}', $(if ($version) { $version } else { 'local snapshot' })).
                Replace('{{PURPOSE}}', $Purpose).
                Replace('{{TARGETS}}', $(if ($ApplicableTarget.Count) { [string]::Join(', ', $ApplicableTarget) } else { 'not specified' })).
                Replace('{{LICENSE}}', $License).
                Replace('{{KNOWN_DIFFERENCES}}', $KnownDifferences).
                Replace('{{BUILD_STATUS}}', 'not-run')
            [IO.File]::WriteAllText((Join-Path $referenceRoot 'README.md'), $readme.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

            $index = Get-Content -LiteralPath $referenceIndexPath -Raw -Encoding UTF8
            $entry = "`n- ``$ReferenceId``: $Purpose (source: $sourceLabel; version: $(if ($version) { $version } else { 'local snapshot' }))`n"
            [IO.File]::WriteAllText($referenceIndexPath, $index.TrimEnd() + $entry, [Text.UTF8Encoding]::new($false))

            $null = New-EwiGitCommit -Repository $root -Message "chore: register reference $ReferenceId" -RelativePaths @(
                'reference-projects/README.md',
                "reference-projects/$ReferenceId/README.md",
                "reference-projects/$ReferenceId/manifest.json"
            )
            return [pscustomobject][ordered]@{
                status = 'imported'
                reference_id = $ReferenceId
                path = "reference-projects/$ReferenceId/project"
                file_count = @($copied.files).Count
                inventory_digest = $manifest.inventory_digest
                warnings = @($copied.warnings)
            }
        }
        catch {
            [IO.File]::WriteAllBytes($referenceIndexPath, $referenceIndexOriginal)
            if (Test-Path -LiteralPath $referenceRoot) {
                $resolvedPartial = Resolve-EwiPath $referenceRoot
                if (-not (Test-EwiPathWithin -Path $resolvedPartial -Parent (Join-Path $root 'reference-projects'))) {
                    throw 'Refusing to clean a partial reference outside reference-projects.'
                }
                [IO.Directory]::Delete($resolvedPartial, $true)
            }
            throw
        }
    }
    $evidenceId = New-EwiEvidenceId 'reference-import'
    $null = Write-EwiEvidence -WorkspaceRoot $root -EvidenceId $evidenceId -Kind 'reference-import' `
        -Subject ([pscustomobject][ordered]@{ workspace = $root; source_id = $null; target_id = $null; build_id = $null; workstream_id = $null; publish_id = $null; reference_id = $ReferenceId }) `
        -Result ([pscustomobject][ordered]@{ status = 'passed'; summary = "Imported immutable reference '$ReferenceId'."; exit_code = 0; details = [pscustomobject][ordered]@{ files = $applied.file_count; inventory_digest = $applied.inventory_digest; warnings = @($applied.warnings) } }) -Artifacts @()
    $applied | Add-Member -NotePropertyName evidence -NotePropertyValue "workspace-management/evidence/$evidenceId.json"
    $applied | ConvertTo-Json -Depth 10
}
finally {
    if ($temporaryClone -and (Test-Path -LiteralPath $temporaryClone)) {
        $resolvedTemp = Resolve-EwiPath $temporaryClone
        $tempRoot = Resolve-EwiPath ([IO.Path]::GetTempPath())
        if (-not (Test-EwiPathWithin -Path $resolvedTemp -Parent $tempRoot)) {
            throw 'Refusing to remove a temporary clone outside the system temp directory.'
        }
        [IO.Directory]::Delete($resolvedTemp, $true)
    }
}
