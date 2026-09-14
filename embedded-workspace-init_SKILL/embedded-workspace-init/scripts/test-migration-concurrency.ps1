[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ewimc-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$assertions = 0
$children = [Collections.Generic.List[Diagnostics.Process]]::new()

function Assert-True {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:assertions++ | Out-Null
}

function Assert-Equal {
    param($Expected, $Actual, [Parameter(Mandatory)] [string] $Message)
    if ($Expected -cne $Actual) { throw "Assertion failed: $Message. Expected '$Expected', actual '$Actual'." }
    $script:assertions++ | Out-Null
}

function Assert-Throws {
    param([Parameter(Mandatory)] [scriptblock] $Action, [Parameter(Mandatory)] [string] $Pattern)
    try { & $Action }
    catch {
        if ($_.Exception.Message -notlike "*$Pattern*") { throw }
        $script:assertions++ | Out-Null
        return
    }
    throw "Assertion failed: expected an error containing '$Pattern'."
}

function Write-Utf8Text {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-TreeFingerprint {
    param([Parameter(Mandatory)] [string] $Root)
    $facts = [Collections.Generic.List[string]]::new()
    foreach ($item in Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName) {
        $relative = [IO.Path]::GetRelativePath($Root, $item.FullName).Replace('\', '/')
        if ($relative -eq '.git' -or $relative.StartsWith('.git/')) { continue }
        if ($item.PSIsContainer) { $facts.Add("D`t$relative") }
        else { $facts.Add("F`t$relative`t$($item.Length)`t$((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash)") }
    }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $facts))))
}

function Start-ChildPowerShell {
    param([Parameter(Mandatory)] [string] $Script, [Parameter(Mandatory)] [string[]] $Arguments)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Process -Id $PID).Path
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $Script) + $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw "Could not start child PowerShell: $Script" }
    $children.Add($process)
    return $process
}

try {
    $legacy = Join-Path $testRoot 'legacy'
    $destination = Join-Path $testRoot 'new-workspace'
    Write-Utf8Text -Path (Join-Path $legacy 'AGENTS.md') -Text "legacy root instructions`r`n"
    Write-Utf8Text -Path (Join-Path $legacy 'AGENTS.override.md') -Text "legacy override instructions`r`n"
    Write-Utf8Text -Path (Join-Path $legacy 'CUSTOM_RULES.md') -Text "legacy root instructions`r`n"
    Write-Utf8Text -Path (Join-Path $legacy 'notes\plan.md') -Text "legacy plan`r`n"
    Write-Utf8Text -Path (Join-Path $legacy 'code\main.c') -Text "int legacy = 1;`r`n"
    Write-Utf8Text -Path (Join-Path $legacy 'keep.dat') -Text "preserve in old root only`r`n"
    $null = & git -C $legacy init --initial-branch=main
    $null = & git -C $legacy config user.name 'Legacy User'
    $null = & git -C $legacy config user.email 'legacy@local.invalid'
    $null = & git -C $legacy add --all
    $null = & git -C $legacy commit -m 'legacy baseline'
    $legacyBefore = Get-TreeFingerprint $legacy
    $legacyHead = (& git -C $legacy rev-parse HEAD | Out-String).Trim()

    $planScript = Join-Path $PSScriptRoot 'plan-migration.ps1'
    $emptyPlan = (& $planScript -WorkspaceRoot $destination -LegacyWorkspaceRoot $legacy -LegacyRuleFile 'CUSTOM_RULES.md' | Out-String) | ConvertFrom-Json -Depth 40
    Assert-Equal 'legacy-migration' $emptyPlan.route 'an explicit legacy source must select migration'
    Assert-True (-not $emptyPlan.can_apply) 'a migration without classifications must not be applicable'
    Assert-True $emptyPlan.approval_required 'a migration must require explicit approval'
    Assert-True (-not (Test-Path -LiteralPath $destination)) 'migration planning must not create the destination'
    Assert-Equal $legacyBefore (Get-TreeFingerprint $legacy) 'migration planning must not alter the old workspace'

    $broadMappings = @([ordered]@{ source_relative = '.'; action = 'copy'; destination_relative = 'workspace-management/migration/legacy-all'; classification = 'legacy-all' }) | ConvertTo-Json -Depth 10 -Compress
    $broadPlan = (& $planScript -WorkspaceRoot $destination -LegacyWorkspaceRoot $legacy -CopyMappingsJson $broadMappings -LegacyRuleFile 'CUSTOM_RULES.md' | Out-String) | ConvertFrom-Json -Depth 40
    Assert-Equal 'legacy-migration' $broadPlan.route 'a broad legacy mapping must remain an explicit migration plan'
    Assert-True (-not $broadPlan.can_apply) 'a broad mapping containing active rule filenames must be blocked'
    Assert-True (@($broadPlan.summary.blockers | Where-Object { $_ -like '*includes active rule file*' }).Count -eq 3) 'every default/configured active rule included by the broad mapping must be reported'

    $partialMappings = @([ordered]@{ source_relative = 'notes'; action = 'copy'; destination_relative = 'project-docs/imported-notes'; classification = 'documentation' }) | ConvertTo-Json -Depth 10 -Compress
    $partialPlan = (& $planScript -WorkspaceRoot $destination -LegacyWorkspaceRoot $legacy -CopyMappingsJson $partialMappings -LegacyRuleFile 'CUSTOM_RULES.md' | Out-String) | ConvertFrom-Json -Depth 40
    Assert-True (-not $partialPlan.can_apply) 'a partially classified migration plan must not be applicable'
    Assert-True (@($partialPlan.summary.blockers | Where-Object { $_ -like '*requires exactly one copy/preserve classification*' }).Count -eq 2) 'every unclassified legacy file must be listed before approval'

    $mappings = @(
        [ordered]@{ source_relative = 'notes'; action = 'copy'; destination_relative = 'project-docs/imported-notes'; classification = 'documentation' },
        [ordered]@{ source_relative = 'code'; action = 'copy'; destination_relative = 'workspace-management/migration/imported-code'; classification = 'historical-code' },
        [ordered]@{ source_relative = 'keep.dat'; action = 'preserve-only'; classification = 'legacy-only' }
    ) | ConvertTo-Json -Depth 10 -Compress
    $approvedPlan = (& $planScript -WorkspaceRoot $destination -LegacyWorkspaceRoot $legacy -CopyMappingsJson $mappings -LegacyRuleFile 'CUSTOM_RULES.md' | Out-String) | ConvertFrom-Json -Depth 40
    Assert-True $approvedPlan.can_apply 'a complete disjoint migration plan must be applicable after approval'
    Assert-Throws -Pattern 'explicitly approved digest' -Action {
        & (Join-Path $PSScriptRoot 'apply-migration.ps1') -PlanBase64 $approvedPlan.plan_base64 -ApprovalDigest ('0' * 64) | Out-Null
    }
    Assert-True (-not (Test-Path -LiteralPath $destination)) 'a wrong approval digest must write nothing'

    Write-Utf8Text -Path (Join-Path $legacy 'notes\plan.md') -Text "changed after planning`r`n"
    Assert-Throws -Pattern 'changed after approval' -Action {
        & (Join-Path $PSScriptRoot 'apply-migration.ps1') -PlanBase64 $approvedPlan.plan_base64 -ApprovalDigest $approvedPlan.approval_digest | Out-Null
    }
    Assert-True (-not (Test-Path -LiteralPath $destination)) 'legacy drift before apply must leave the destination absent'
    $null = & git -C $legacy checkout -- 'notes/plan.md'
    Assert-Equal $legacyBefore (Get-TreeFingerprint $legacy) 'the test fixture must restore the exact approved legacy state'
    Assert-Equal '' ((& git -C $legacy status --short | Out-String).Trim()) 'the restored legacy test fixture must be clean'

    $approvedPlan = (& $planScript -WorkspaceRoot $destination -LegacyWorkspaceRoot $legacy -CopyMappingsJson $mappings -LegacyRuleFile 'CUSTOM_RULES.md' | Out-String) | ConvertFrom-Json -Depth 40
    $migration = (& (Join-Path $PSScriptRoot 'apply-migration.ps1') -PlanBase64 $approvedPlan.plan_base64 -ApprovalDigest $approvedPlan.approval_digest | Out-String) | ConvertFrom-Json -Depth 40
    Assert-Equal 'active' $migration.status 'the approved migration must activate the new workspace'
    Assert-True $migration.old_workspace_unchanged 'migration must report the legacy root as unchanged'
    Assert-Equal $legacyBefore (Get-TreeFingerprint $legacy) 'successful migration must leave the old workspace byte-for-byte and Git-state unchanged'
    Assert-Equal $legacyHead ((& git -C $legacy rev-parse HEAD | Out-String).Trim()) 'migration must not move the legacy Git HEAD'
    Assert-Equal '' ((& git -C $legacy status --short | Out-String).Trim()) 'migration must not dirty the legacy Git worktree'
    Assert-True (Test-Path -LiteralPath (Join-Path $destination 'project-docs\imported-notes\plan.md')) 'approved documentation must be copied to its classified destination'
    Assert-True (Test-Path -LiteralPath (Join-Path $destination 'workspace-management\migration\imported-code\main.c')) 'approved historical code must be copied to its classified destination'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destination 'keep.dat'))) 'preserve-only content must remain only in the legacy root'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $testRoot 'legacy.pre-init-backup'))) 'migration must not create a duplicate pre-init backup'

    $workspaceState = Get-Content -Raw -LiteralPath (Join-Path $destination 'workspace-management\config\workspace.json') | ConvertFrom-Json -Depth 30
    Assert-Equal 'active' $workspaceState.workspace_state 'the migrated workspace must be active only after validation'
    Assert-Equal $migration.legacy_workspace_id $workspaceState.migration.migrated_from 'the workspace must record the stable legacy id'
    Assert-True ($null -ne $workspaceState.migration.migrated_at) 'the workspace must record migration time'
    $preActivationCommit = (& git -C $destination rev-parse 'HEAD^' | Out-String).Trim()
    $preActivationState = (& git -C $destination show "$preActivationCommit`:workspace-management/config/workspace.json" | Out-String) | ConvertFrom-Json -Depth 20
    Assert-Equal 'initializing' $preActivationState.workspace_state 'the durable migration checkpoint before activation must remain initializing'
    Assert-Equal '' ((& git -C $destination status --short | Out-String).Trim()) 'the activated migrated workspace must have clean management Git'

    $archiveRoot = Join-Path $destination 'workspace-management\history\legacy-instructions'
    $archiveManifest = Get-Content -Raw -LiteralPath (Join-Path $archiveRoot 'manifest.json') | ConvertFrom-Json -Depth 30
    Assert-Equal 3 @($archiveManifest.files).Count 'default and configured fallback legacy rules must all be archived'
    Assert-Equal 3 @($archiveManifest.files.archive_path | Sort-Object -Unique).Count 'different legacy rule origins with identical content must use distinct archive paths'
    foreach ($entry in $archiveManifest.files) {
        $archive = Join-Path $destination $entry.archive_path
        Assert-Equal $entry.sha256 (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() 'each archived rule must match its recorded hash'
        Assert-True ([IO.Path]::GetFileName($archive) -notin @('AGENTS.md', 'AGENTS.override.md')) 'an archived rule must not use an active discovery name'
    }
    $report = Get-Content -Raw -LiteralPath (Join-Path $destination 'workspace-management\migration\initialization-report.md')
    Assert-True (-not ($report -match '\{\{[A-Z0-9_]+\}\}')) 'the migration report must contain no template placeholders'
    Assert-True (Test-Path -LiteralPath (Join-Path $destination $migration.evidence)) 'successful migration must record common-envelope evidence'
    $migratedTargets = Get-Content -Raw -LiteralPath (Join-Path $destination 'workspace-management\config\targets.json') | ConvertFrom-Json -Depth 30
    Assert-Equal 0 @($migratedTargets.sources.PSObject.Properties).Count 'legacy history must not become a normal source group'
    $migratedLocal = Get-Content -Raw -LiteralPath (Join-Path $destination 'workspace-management\config\targets.local.json') | ConvertFrom-Json -Depth 30
    Assert-True ($null -ne $migratedLocal.legacy_workspaces.PSObject.Properties[$migration.legacy_workspace_id]) 'legacy history must be recorded only as a local historical reference'
    Write-Utf8Text -Path (Join-Path $legacy 'late\Makefile') -Text "all:`r`n"
    $legacyDetection = (& (Join-Path $destination 'workspace-management\tools\detect-targets.ps1') -WorkspaceRoot $destination | Out-String) | ConvertFrom-Json -Depth 20
    Assert-Equal 0 @($legacyDetection.candidates).Count 'target detection must never scan newly added legacy-history content'
    Assert-True (-not (Get-Content -Raw -LiteralPath (Join-Path $destination 'AGENTS.md')).Contains('legacy root instructions')) 'legacy rules must not become current workspace instructions'

    $driftLegacy = Join-Path $testRoot 'drift-legacy'
    $driftDestination = Join-Path $testRoot 'drift-destination'
    Write-Utf8Text -Path (Join-Path $driftLegacy 'AGENTS.md') -Text "drift legacy rule`r`n"
    foreach ($index in 1..200) { Write-Utf8Text -Path (Join-Path $driftLegacy "bulk\file-$index.txt") -Text "value-$index`r`n" }
    $driftMappings = @([ordered]@{ source_relative = 'bulk'; action = 'copy'; destination_relative = 'workspace-management/migration/bulk'; classification = 'historical' }) | ConvertTo-Json -Depth 10 -Compress
    $driftPlan = (& $planScript -WorkspaceRoot $driftDestination -LegacyWorkspaceRoot $driftLegacy -CopyMappingsJson $driftMappings | Out-String) | ConvertFrom-Json -Depth 40
    Assert-True $driftPlan.can_apply 'the drift fixture must have a complete approved plan'
    $driftScript = Join-Path $testRoot 'drift-legacy.ps1'
    Write-Utf8Text -Path $driftScript -Text @'
param([string] $Destination, [string] $Legacy)
$marker = Join-Path $Destination 'workspace-management/config/workspace.json'
foreach ($attempt in 1..400) {
    if (Test-Path -LiteralPath $marker) { break }
    Start-Sleep -Milliseconds 25
}
if (-not (Test-Path -LiteralPath $marker)) { exit 2 }
[IO.File]::WriteAllText((Join-Path $Legacy 'bulk/external-drift.txt'), 'external drift')
'@
    $drifter = Start-ChildPowerShell -Script $driftScript -Arguments @($driftDestination, $driftLegacy)
    Assert-Throws -Pattern 'changed after destination initialization' -Action {
        & (Join-Path $PSScriptRoot 'apply-migration.ps1') -PlanBase64 $driftPlan.plan_base64 -ApprovalDigest $driftPlan.approval_digest | Out-Null
    }
    if (-not $drifter.WaitForExit(10000)) { $drifter.Kill($true); throw 'Legacy drift child did not exit.' }
    Assert-Equal 0 $drifter.ExitCode 'the external drift injector must run after initialization begins'
    $driftState = Get-Content -Raw -LiteralPath (Join-Path $driftDestination 'workspace-management\config\workspace.json') | ConvertFrom-Json -Depth 20
    Assert-Equal 'initializing' $driftState.workspace_state 'legacy drift during copy must never activate the new workspace'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $testRoot 'drift-legacy.pre-init-backup'))) 'drift handling must not duplicate the legacy workspace'

    $authority = Join-Path $testRoot 'owned-source'
    Write-Utf8Text -Path (Join-Path $authority 'Makefile') -Text "all:`r`n"
    $ownerWorkspace = Join-Path $testRoot 'owner-workspace'
    $null = & (Join-Path $PSScriptRoot 'init-workspace.ps1') -WorkspaceRoot $ownerWorkspace -UserSourcePath $authority
    $secondPlan = (& $planScript -WorkspaceRoot (Join-Path $testRoot 'second-workspace') -UserSourcePath $authority -KnownActiveWorkspaceRoot $ownerWorkspace | Out-String) | ConvertFrom-Json -Depth 40
    Assert-True (-not $secondPlan.can_apply) 'an authority known to belong to another active workspace must be blocked'
    Assert-True (@($secondPlan.summary.blockers | Where-Object { $_ -like '*authority owned by active workspace*' }).Count -eq 1) 'the known ownership conflict must identify the active root'

    Import-Module (Join-Path $PSScriptRoot 'lib\workspace-common.psm1') -Force
    $alias = Join-Path $testRoot 'workspace-alias'
    $null = New-Item -ItemType Junction -Path $alias -Target $destination
    Assert-Equal (Get-EwiMutexName $destination) (Get-EwiMutexName $alias) 'real path and junction alias must share one mutex identity'
    Assert-Equal (Get-EwiMutexName ($destination.ToUpperInvariant() + '\')) (Get-EwiMutexName $destination) 'case and trailing separator aliases must share one mutex identity'

    $holdScript = Join-Path $testRoot 'hold-lock.ps1'
    $ready = Join-Path $testRoot 'lock-ready'
    Write-Utf8Text -Path $holdScript -Text @'
param([string] $Module, [string] $Root, [string] $Ready)
Import-Module $Module -Force
$name = Get-EwiMutexName $Root
$mutex = [Threading.Mutex]::new($false, $name)
$acquired = $mutex.WaitOne([TimeSpan]::FromSeconds(10))
if (-not $acquired) { exit 2 }
try {
    [IO.File]::WriteAllText($Ready, 'ready')
    Start-Sleep -Seconds 8
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
'@
    $module = Join-Path $PSScriptRoot 'lib\workspace-common.psm1'
    $holder = Start-ChildPowerShell -Script $holdScript -Arguments @($module, $destination, $ready)
    foreach ($attempt in 1..100) {
        if (Test-Path -LiteralPath $ready) { break }
        Start-Sleep -Milliseconds 50
    }
    Assert-True (Test-Path -LiteralPath $ready) 'the child process must acquire the named mutex'
    $forbiddenWrite = Join-Path $destination 'workspace-management\config\lock-timeout-write.txt'
    Assert-Throws -Pattern 'mutex timed out without writing' -Action {
        Invoke-EwiLocked -WorkspaceRoot $destination -TimeoutSeconds 1 -ScriptBlock { [IO.File]::WriteAllText($forbiddenWrite, 'bad') }
    }
    Assert-True (-not (Test-Path -LiteralPath $forbiddenWrite)) 'a mutex timeout must execute no shared-state write'
    if (-not $holder.WaitForExit(15000)) { $holder.Kill($true); throw 'Mutex holder did not exit.' }
    Assert-Equal 0 $holder.ExitCode 'the mutex holder must exit successfully'

    $sharedRoot = Join-Path $testRoot 'shared'
    $null = New-Item -ItemType Directory -Path $sharedRoot
    $sharedPath = Join-Path $sharedRoot 'state.json'
    $sharedSchema = Join-Path $sharedRoot 'state.schema.json'
    Write-Utf8Text -Path $sharedSchema -Text '{"type":"object","additionalProperties":false,"required":["values"],"properties":{"values":{"type":"object","additionalProperties":{"type":"string"}}}}'
    Write-Utf8Text -Path $sharedPath -Text '{"values":{}}'
    $updateScript = Join-Path $testRoot 'update-shared.ps1'
    Write-Utf8Text -Path $updateScript -Text @'
param([string] $Module, [string] $Root, [string] $State, [string] $Schema, [string] $Key)
Import-Module $Module -Force
Invoke-EwiLocked -WorkspaceRoot $Root -TimeoutSeconds 20 -ScriptBlock {
    $value = Read-EwiJson -Path $State -SchemaPath $Schema
    Start-Sleep -Milliseconds 300
    $value.values | Add-Member -NotePropertyName $Key -NotePropertyValue $Key
    Write-EwiJsonAtomic -Path $State -Value $value -SchemaPath $Schema
} | Out-Null
'@
    $firstProcess = Start-ChildPowerShell -Script $updateScript -Arguments @($module, $sharedRoot, $sharedPath, $sharedSchema, 'first')
    $secondProcess = Start-ChildPowerShell -Script $updateScript -Arguments @($module, $sharedRoot, $sharedPath, $sharedSchema, 'second')
    foreach ($process in @($firstProcess, $secondProcess)) {
        if (-not $process.WaitForExit(30000)) { $process.Kill($true); throw 'Shared update child did not exit.' }
        if ($process.ExitCode -ne 0) { throw "Shared update child failed: $($process.StandardError.ReadToEnd())" }
    }
    $shared = Get-Content -Raw -LiteralPath $sharedPath | ConvertFrom-Json
    Assert-Equal 2 @($shared.values.PSObject.Properties).Count 'serialized lock-time rereads must preserve both shared updates'
    Assert-Equal 'first' $shared.values.first 'the first update must be retained'
    Assert-Equal 'second' $shared.values.second 'the second update must be retained'

    [pscustomobject][ordered]@{
        status = 'passed'
        assertions = $assertions
        powershell = $PSVersionTable.PSVersion.ToString()
        git = ((& git --version | Out-String).Trim())
    } | ConvertTo-Json
}
finally {
    foreach ($process in $children) {
        if (-not $process.HasExited) { $process.Kill($true) }
        $process.Dispose()
    }
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        if ([IO.Path]::GetDirectoryName($resolved).TrimEnd('\') -ne $expectedParent -or
            -not [IO.Path]::GetFileName($resolved).StartsWith('ewimc-')) {
            throw "Refusing to clean unexpected test path: $resolved"
        }
        $links = @(Get-ChildItem -LiteralPath $resolved -Recurse -Force | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } | Sort-Object { $_.FullName.Length } -Descending)
        foreach ($link in $links) {
            if ($link.PSIsContainer) { [IO.Directory]::Delete($link.FullName, $false) }
            else { [IO.File]::Delete($link.FullName) }
        }
        Get-ChildItem -LiteralPath $resolved -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
        (Get-Item -LiteralPath $resolved -Force).Attributes = 'Directory'
        [IO.Directory]::Delete($resolved, $true)
    }
}
