# Use instead of approval rules as the approval rule system is too limited

param (
    [string]$WsusServer = "localhost",
    [int]$Port = 8530,
    [switch]$UseSSL,
    [switch]$NoSync,
    [switch]$Reset,
    [switch]$DryRun,
    [bool]$DeclineIA64 = $true,
    [bool]$DeclineARM64 = $true,
    [bool]$DeclineX86 = $true,
    [bool]$DeclineX64 = $false,
    [bool]$DeclinePreview = $true,
    [bool]$DeclineBeta = $true
)

$logfile = "$PSScriptRoot\logs\wsus-approve.log"

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


[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($WsusServer, $UseSSL, $Port)
$group = $wsus.GetComputerTargetGroups() | Where-Object {$_.Name -eq $approve_group}
$subscription = $wsus.GetSubscription()
$update_categories = $subscription.GetUpdateCategories()
$update_classifications = $subscription.GetUpdateClassifications()


function log ($text) {
    Write-Output "$(get-date -format s): $text" | Tee-Object -Append $logfile
}

function is_selected ($update) {
    #
    # Is there any way to check update against language list in here?
    #
    if ($update.UpdateClassificationTitle -in $update_classifications.Title) {
        return $true
    }

    Foreach ($product in $update.ProductTitles) {
        if ($product -in $update_categories.Title) {
	        return $true
        }
    }

    return $false
}

# Reset logfile
if (Test-Path $logfile) {
    Remove-Item $logfile
}

if (-not $NoSync) {
    if ($subscription.GetSynchronizationStatus() -eq "NotProcessing") {
        log "Starting synchronization..."
        $subscription.StartSynchronization()
    }
}

# Wait for any currently running synchronization jobs to finish before continuing
while ($subscription.GetSynchronizationStatus() -ne "NotProcessing") {
    log "Waiting for synchronization to finish..."
    Start-Sleep -s 10
}

# Start by removing deselected updates as there is no need to do further processing on them
log "Checking for deselected updates"
$wsus.GetUpdates() | Foreach-Object {
    if (-Not (is_selected $_)) {
        log "Deleting deselected update: $($_.Title)"
        if (-not $DryRun) { $wsus.DeleteUpdate($_.Id.UpdateId) }
    }
}

if ($Reset) {
    $updates = $wsus.GetUpdates()
} else {
    $updates = $wsus.GetUpdates() | Where-Object {-not $_.IsDeclined}
}

$updates | Foreach-Object {
    if ($DeclineIA64 -and $_.Title -Match 'ia64|itanium' -or $_.LegacyName -Match 'ia64|itanium') {
        log "Declining $($_.Title) [ia64]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($DeclineARM64 -and $_.Title -Match 'arm64') {
        log "Declining $($_.Title) [arm64]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($DeclineX86 -and $_.Title -Match 'x86') {
        log "Declining $($_.Title) [x86]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($DeclineX64 -and $_.Title -Match 'x64') {
        log "Declining $($_.Title) [x64]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($DeclinePreview -and $_.Title -Match 'preview') {
        log "Declining $($_.Title) [preview]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($DeclineBeta -and ($_.IsBeta -or $_.Title -Match 'beta')) {
        log "Declining $($_.Title) [beta]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($_.IsSuperseded -or $_.PublicationState -eq "Expired") {
        # Handle superseded and expired packages after any new updates have been approved
        return
    } elseif (-not $_.IsApproved) {
        if ($_.IsWsusInfrastructureUpdate -or $approve_classifications.Contains($_.UpdateClassificationTitle)) {
            if ($_.RequiresLicenseAgreementAcceptance) {
                log "Accepting license agreement for $($_.Title)"
                if (-not $DryRun) { $_.AcceptLicenseAgreement() }
            }

            log "Approving $($_.Title)"
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
        log "Declining $($_.Title) [superseded]"
        if (-not $DryRun) { $_.Decline() }
    } elseif ($_.IsSuperseded -or $_.PublicationState -eq "Expired") {
        log "Declining $($_.Title) [expired]"
        if (-not $DryRun) { $_.Decline() }
    }
}
