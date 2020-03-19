# Use instead of approval rules as the approval rule system is too limited

param (
    [string]$WsusServer = "localhost",
    [int]$Port = 8530,
    [switch]$UseSSL,
    [switch]$NoSync,
    [switch]$Reset,
    [switch]$DryRun
)

# Do not add upgrades here. They are currently handled manually for more control
$approve_classifications = @(
    "Critical Updates",
    "Definition Updates",
    "Drivers",
    "Feature Packs",
    "Security Updates",
    "Service Packs",
    "Tools",
    "Update Rollups",
    "Updates"
)
$approve_group = "All Computers"

# Decline settings for architectures and categories
$decline_arch_ia64 = $true
$decline_arch_arm64 = $true
$decline_arch_x86 = $true
$decline_arch_x64 = $false
$decline_preview = $true
$decline_beta = $true


[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($WsusServer, $UseSSL, $Port)
$group = $wsus.GetComputerTargetGroups() | Where-Object {$_.Name -eq $approve_group}
$subscription = $wsus.GetSubscription()

if (-not $NoSync) {
    if ($subscription.GetSynchronizationStatus() -eq "NotProcessing") {
        Write-Output "Starting synchronization..."
        $subscription.StartSynchronization()
    }
}

# Wait for any currently running synchronization jobs to finish before continuing
while ($subscription.GetSynchronizationStatus() -ne "NotProcessing") {
    Write-Output "Waiting for synchronization to finish..."
    Start-Sleep -s 10
}

if ($Reset) {
    $updates = $wsus.GetUpdates()
} else {
    $updates = $wsus.GetUpdates() | Where-Object {-not $_.IsDeclined}
}

$updates | Foreach-Object {
    if ($decline_arch_ia64 -and $_.Title -Match 'ia64|itanium' -or $_.LegacyName -Match 'ia64|itanium') {
        Write-Output "Declining $($_.Title) [ia64]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($decline_arch_arm64 -and $_.Title -Match 'arm64') {
        Write-Output "Declining $($_.Title) [arm64]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($decline_arch_x86 -and $_.Title -Match 'x86') {
        Write-Output "Declining $($_.Title) [x86]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($decline_arch_x64 -and $_.Title -Match 'x64') {
        Write-Output "Declining $($_.Title) [x64]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($decline_preview -and $_.Title -Match 'preview') {
        Write-Output "Declining $($_.Title) [preview]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($decline_beta -and ($_.IsBeta -or $_.Title -Match 'beta')) {
        Write-Output "Declining $($_.Title) [beta]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($_.IsSuperseded -or $_.PublicationState -eq "Expired") {
        # Handle superseded and expired packages after any new updates have been approved
        return
    } elseif (-not $_.IsApproved) {
        if ($_.IsWsusInfrastructureUpdate -or $approve_classifications.Contains($_.UpdateClassificationTitle)) {
            if ($_.RequiresLicenseAgreementAcceptance) {
                Write-Output "Accepting license agreement for $($_.Title)"
                if (-not $DryRun) { $_.AcceptLicenseAgreement() }
            }

            Write-Output "Approving $($_.Title)"
            if (-not $DryRun) { $_.Approve("Install", $group) }
        }
    }
}

# After any new superseding updates have been approved above, superseded and expired updates
# can be declined. We need to handle both here as it seems like superseded updates are also
# marked expired, but some updates are just expired without being superseded.
$updates = $wsus.GetUpdates() | Where-Object {-not $_.IsDeclined}
$updates | Foreach-Object {
    if ($_.IsSuperseded) {
        Write-Output "Declining $($_.Title) [superseded]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($_.IsSuperseded -or $_.PublicationState -eq "Expired") {
        Write-Output "Declining $($_.Title) [expired]"
        if (-not $DryRun) { $_.Decline() }
    }
}