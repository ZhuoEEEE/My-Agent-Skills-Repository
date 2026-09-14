[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ewipu-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$assertions = 0

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
        if ($item.PSIsContainer) { $facts.Add("D`t$relative") }
        else { $facts.Add("F`t$relative`t$($item.Length)`t$((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash)") }
    }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $facts))))
}

function New-OldWorkspace {
    param([Parameter(Mandatory)] [string] $Name)
    $base = Join-Path $testRoot $Name
    $source = Join-Path $base 'source'
    $workspace = Join-Path $base 'workspace'
    Write-Utf8Text -Path (Join-Path $source 'Makefile') -Text "all:`r`n"
    Write-Utf8Text -Path (Join-Path $source 'main.c') -Text "int main(void) { return 0; }`r`n"
    $null = & (Join-Path $PSScriptRoot 'init-workspace.ps1') -WorkspaceRoot $workspace -UserSourcePath $source

    $oldRule = "# Old root rule`r`n`r`nThis exact policy text must be archived.`r`n"
    Write-Utf8Text -Path (Join-Path $workspace 'AGENTS.md') -Text $oldRule
    $localPath = Join-Path $workspace 'workspace-management\config\targets.local.json'
    $local = Get-Content -Raw -LiteralPath $localPath | ConvertFrom-Json -Depth 40
    foreach ($sourceProperty in $local.sources.PSObject.Properties) {
        foreach ($mappingProperty in $sourceProperty.Value.mappings.PSObject.Properties) {
            $mappingProperty.Value.PSObject.Properties.Remove('user_git')
        }
    }
    [IO.File]::WriteAllText($localPath, ($local | ConvertTo-Json -Depth 40 -Compress) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $sourceStatePath = Join-Path $workspace 'workspace-management\sync-state\sources\source.json'
    $sourceState = Get-Content -Raw -LiteralPath $sourceStatePath | ConvertFrom-Json -Depth 40
    $sourceState.mapping_digest = '0' * 64
    [IO.File]::WriteAllText($sourceStatePath, ($sourceState | ConvertTo-Json -Depth 40 -Compress) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $oldSchemaPath = Join-Path $workspace 'workspace-management\schemas\targets-local.schema.json'
    $oldSchema = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\assets\schemas\targets-local.schema.json') | ConvertFrom-Json -Depth 40
    $mappingSchema = $oldSchema.properties.sources.additionalProperties.properties.mappings.additionalProperties
    $mappingSchema.required = @('source_path')
    $mappingSchema.properties.PSObject.Properties.Remove('user_git')
    [IO.File]::WriteAllText($oldSchemaPath, ($oldSchema | ConvertTo-Json -Depth 40 -Compress) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    foreach ($relative in @(
        'workspace-management/tools/promote-reference.ps1',
        'workspace-management/tools/set-user-git.ps1',
        'workspace-management/tools/pin-workstream-dependency.ps1',
        'workspace-management/schemas/policy-upgrade.schema.json'
    )) {
        $path = Join-Path $workspace $relative
        if (Test-Path -LiteralPath $path) { [IO.File]::Delete($path) }
    }
    $null = & git -C $workspace add -- 'AGENTS.md' 'workspace-management/schemas/targets-local.schema.json'
    $null = & git -C $workspace rm --ignore-unmatch -- 'workspace-management/tools/promote-reference.ps1' 'workspace-management/tools/set-user-git.ps1' 'workspace-management/tools/pin-workstream-dependency.ps1' 'workspace-management/schemas/policy-upgrade.schema.json'
    $null = & git -C $workspace commit -m 'chore: simulate old workspace policy'
    return [pscustomobject][ordered]@{
        source = $source
        workspace = $workspace
        old_rule = $oldRule
        old_rule_hash = (Get-FileHash -LiteralPath (Join-Path $workspace 'AGENTS.md') -Algorithm SHA256).Hash.ToLowerInvariant()
        local_path = $localPath
        source_state_path = $sourceStatePath
        source_integration = Join-Path $workspace 'sources\source\integration'
        source_head = (& git -C (Join-Path $workspace 'sources\source\integration') rev-parse HEAD | Out-String).Trim()
        source_status = (& git -C (Join-Path $workspace 'sources\source\integration') status --short | Out-String).Trim()
        user_git_exists = Test-Path -LiteralPath (Join-Path $source '.git')
    }
}

try {
    $fixture = New-OldWorkspace 'success'
    $beforeHead = (& git -C $fixture.workspace rev-parse HEAD | Out-String).Trim()
    $beforeStatus = (& git -C $fixture.workspace status --short | Out-String).Trim()
    $beforeLocalHash = (Get-FileHash -LiteralPath $fixture.local_path -Algorithm SHA256).Hash
    $beforeRefresh = Get-TreeFingerprint $fixture.workspace
    $refresh = (& (Join-Path $PSScriptRoot 'refresh-workspace.ps1') -WorkspaceRoot $fixture.workspace | Out-String) | ConvertFrom-Json -Depth 40
    Assert-True $refresh.upgrade_required 'ordinary refresh must route managed differences to a controlled upgrade'
    Assert-True (-not $refresh.changed) 'upgrade detection during refresh must not apply fact updates'
    Assert-Equal $beforeRefresh (Get-TreeFingerprint $fixture.workspace) 'upgrade detection during refresh must be zero-write'
    $plan = (& (Join-Path $PSScriptRoot 'plan-migration.ps1') -WorkspaceRoot $fixture.workspace -PolicyUpgrade | Out-String) | ConvertFrom-Json -Depth 60
    Assert-Equal 'policy-upgrade' $plan.route 'explicit policy upgrade must select the upgrade route'
    Assert-True $plan.approval_required 'policy upgrade must require explicit approval'
    Assert-True $plan.can_apply 'a known version-1 policy delta must produce an applicable exact plan'
    Assert-True (@($plan.summary.policy_upgrade_operations).Count -ge 5) 'the plan must list every missing or replaced managed file'
    Assert-Equal 'add-deferred-user-git' $plan.summary.local_state_migration 'the plan must disclose the local state migration'
    Assert-Equal 1 @($plan.summary.source_state_migrations).Count 'the plan must disclose the mapping-digest state migration'
    Assert-Equal $beforeHead ((& git -C $fixture.workspace rev-parse HEAD | Out-String).Trim()) 'policy planning must not move management Git'
    Assert-Equal $beforeStatus ((& git -C $fixture.workspace status --short | Out-String).Trim()) 'policy planning must not change management status'
    Assert-Equal $beforeLocalHash (Get-FileHash -LiteralPath $fixture.local_path -Algorithm SHA256).Hash 'policy planning must not rewrite local state'

    Assert-Throws -Pattern 'explicitly approved digest' -Action {
        & (Join-Path $PSScriptRoot 'apply-policy-upgrade.ps1') -PlanBase64 $plan.plan_base64 -ApprovalDigest ('0' * 64) | Out-Null
    }
    Assert-Equal $beforeHead ((& git -C $fixture.workspace rev-parse HEAD | Out-String).Trim()) 'a wrong digest must write no management state'

    $driftPath = Join-Path $fixture.workspace 'AGENTS.md'
    $driftOriginal = [IO.File]::ReadAllText($driftPath)
    Write-Utf8Text -Path $driftPath -Text "changed after plan`r`n"
    Assert-Throws -Pattern 'changed after policy planning' -Action {
        & (Join-Path $PSScriptRoot 'apply-policy-upgrade.ps1') -PlanBase64 $plan.plan_base64 -ApprovalDigest $plan.approval_digest | Out-Null
    }
    Write-Utf8Text -Path $driftPath -Text $driftOriginal
    Assert-Equal $beforeLocalHash (Get-FileHash -LiteralPath $fixture.local_path -Algorithm SHA256).Hash 'stale approval must not migrate local state'

    $plan = (& (Join-Path $PSScriptRoot 'plan-migration.ps1') -WorkspaceRoot $fixture.workspace -PolicyUpgrade | Out-String) | ConvertFrom-Json -Depth 60
    $result = (& (Join-Path $PSScriptRoot 'apply-policy-upgrade.ps1') -PlanBase64 $plan.plan_base64 -ApprovalDigest $plan.approval_digest | Out-String) | ConvertFrom-Json -Depth 40
    Assert-Equal 'upgraded' $result.status 'the unchanged approved policy plan must apply'
    Assert-True (Test-Path -LiteralPath (Join-Path $fixture.workspace $result.evidence)) 'policy upgrade must record evidence'
    Assert-Equal $fixture.source_head ((& git -C $fixture.source_integration rev-parse HEAD | Out-String).Trim()) 'policy upgrade must not change source-private history'
    Assert-Equal $fixture.source_status ((& git -C $fixture.source_integration status --short | Out-String).Trim()) 'policy upgrade must not dirty source-private Git'
    Assert-Equal $fixture.user_git_exists (Test-Path -LiteralPath (Join-Path $fixture.source '.git')) 'policy upgrade must not initialize user Git'
    $local = Get-Content -Raw -LiteralPath $fixture.local_path | ConvertFrom-Json -Depth 40
    Assert-Equal 'deferred' $local.sources.source.mappings.source.user_git.status 'local state migration must preserve no-response as deferred'
    $postUpgradeImport = (& (Join-Path $PSScriptRoot 'import-sources.ps1') -WorkspaceRoot $fixture.workspace -SourceId source | Out-String) | ConvertFrom-Json -Depth 30
    Assert-True $postUpgradeImport.can_apply 'policy upgrade must leave the migrated mapping digest valid for normal import planning'
    Assert-True (Test-Path -LiteralPath (Join-Path $fixture.workspace 'workspace-management\tools\set-user-git.ps1')) 'missing runtime tools must be installed by the exact upgrade'
    Assert-True (Test-Path -LiteralPath (Join-Path $fixture.workspace 'workspace-management\schemas\policy-upgrade.schema.json')) 'missing policy schema must be installed'
    $history = Get-ChildItem -LiteralPath (Join-Path $fixture.workspace 'workspace-management\history\policy-upgrades') -Recurse -File -Filter 'root-agents-*.txt' | Select-Object -First 1
    Assert-True ($null -ne $history) 'a replaced root rule must be archived'
    Assert-Equal $fixture.old_rule_hash (Get-FileHash -LiteralPath $history.FullName -Algorithm SHA256).Hash.ToLowerInvariant() 'the archived root rule must be byte-for-byte exact'
    Assert-Equal (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..\assets\AGENTS.md') -Algorithm SHA256).Hash `
        (Get-FileHash -LiteralPath (Join-Path $fixture.workspace 'AGENTS.md') -Algorithm SHA256).Hash 'the upgraded root rule must match the canonical asset'
    $afterPlan = (& (Join-Path $PSScriptRoot 'plan-migration.ps1') -WorkspaceRoot $fixture.workspace -PolicyUpgrade | Out-String) | ConvertFrom-Json -Depth 40
    Assert-True (-not $afterPlan.can_apply) 'an up-to-date workspace must not produce another policy apply'
    Assert-Equal 0 @($afterPlan.summary.policy_upgrade_operations).Count 'an up-to-date workspace must have no operations'

    $failure = New-OldWorkspace 'failure'
    $failurePlan = (& (Join-Path $PSScriptRoot 'plan-migration.ps1') -WorkspaceRoot $failure.workspace -PolicyUpgrade | Out-String) | ConvertFrom-Json -Depth 60
    $failureHead = (& git -C $failure.workspace rev-parse HEAD | Out-String).Trim()
    $failureRuleHash = (Get-FileHash -LiteralPath (Join-Path $failure.workspace 'AGENTS.md') -Algorithm SHA256).Hash
    $failureLocalHash = (Get-FileHash -LiteralPath $failure.local_path -Algorithm SHA256).Hash
    $failureStateHash = (Get-FileHash -LiteralPath $failure.source_state_path -Algorithm SHA256).Hash
    $hook = Join-Path $failure.workspace '.git\hooks\pre-commit'
    Write-Utf8Text -Path $hook -Text "#!/bin/sh`nexit 1`n"
    Assert-Throws -Pattern 'Git commit failed' -Action {
        & (Join-Path $PSScriptRoot 'apply-policy-upgrade.ps1') -PlanBase64 $failurePlan.plan_base64 -ApprovalDigest $failurePlan.approval_digest | Out-Null
    }
    Assert-Equal $failureHead ((& git -C $failure.workspace rev-parse HEAD | Out-String).Trim()) 'a failed policy commit must restore management HEAD'
    Assert-Equal $failureRuleHash (Get-FileHash -LiteralPath (Join-Path $failure.workspace 'AGENTS.md') -Algorithm SHA256).Hash 'a failed policy commit must restore the old root rule'
    Assert-Equal $failureLocalHash (Get-FileHash -LiteralPath $failure.local_path -Algorithm SHA256).Hash 'a failed policy commit must restore old local state'
    Assert-Equal $failureStateHash (Get-FileHash -LiteralPath $failure.source_state_path -Algorithm SHA256).Hash 'a failed policy commit must restore old source state'
    Assert-Equal '' ((& git -C $failure.workspace status --short | Out-String).Trim()) 'a failed policy apply must leave management Git clean'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $failure.workspace 'workspace-management\history\policy-upgrades'))) 'failed policy history must be removed'

    [pscustomobject][ordered]@{
        status = 'passed'
        assertions = $assertions
        powershell = $PSVersionTable.PSVersion.ToString()
        git = ((& git --version | Out-String).Trim())
    } | ConvertTo-Json
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        if ([IO.Path]::GetDirectoryName($resolved).TrimEnd('\') -ne $expectedParent -or
            -not [IO.Path]::GetFileName($resolved).StartsWith('ewipu-')) {
            throw "Refusing to clean unexpected test path: $resolved"
        }
        Get-ChildItem -LiteralPath $resolved -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
        (Get-Item -LiteralPath $resolved -Force).Attributes = 'Directory'
        [IO.Directory]::Delete($resolved, $true)
    }
}
