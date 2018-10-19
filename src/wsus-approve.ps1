# Use instead of approval rules as the approval rule system is too limited

Param (
    [string]$WsusServer = 'wsus',
    [int]$Port = 8530,
    [switch]$UseSSL,
    [switch]$NoSync,
    [switch]$Reset,
    [switch]$DryRun
)

# Do not add upgrades here. They are currently handled manually for more control
$auto_approve_classifications = @(
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
$auto_approve_group = "All Computers"


[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($WsusServer, $UseSSL, $Port)
$group = $wsus.GetComputerTargetGroups() | Where-Object {$_.Name -eq $auto_approve_group}
$subscription = $wsus.GetSubscription()

If (-Not $NoSync) {
    If ($subscription.GetSynchronizationStatus() -eq "NotProcessing") {
        Write-Output "Starting synchronization..."
        $subscription.StartSynchronization()
    }
}

# Wait for any currently running synchronization jobs to finish before continuing
While ($subscription.GetSynchronizationStatus() -ne "NotProcessing") {
    Write-Output "Waiting for synchronization to finish..."
    Start-Sleep -s 10
}

If ($Reset) {
    $updates = $wsus.GetUpdates()
} Else {
    $updates = $wsus.GetUpdates() | Where-Object {-Not $_.IsDeclined}
}

$updates | Foreach-Object {
    # Ensure decline rules are processed first!
    If ($_.Title -Match 'ia64|itanium' -Or $_.LegacyName -Match 'ia64|itanium') {
        Write-Output "Declining $($_.Title) [itanium]"
        If (-Not $DryRun) { $_.Decline() }
    } Elseif ($_.Title -Match 'arm64') {
        Write-Output "Declining $($_.Title) [arm]"
        If (-Not $DryRun) { $_.Decline() }
    } Elseif ($_.Title -Match 'preview') {
        Write-Output "Declining $($_.Title) [preview]"
        If (-Not $DryRun) { $_.Decline() }
    } Elseif ($_.IsBeta -Or $_.Title -Match 'beta') {
        Write-Output "Declining $($_.Title) [beta]"
        If (-Not $DryRun) { $_.Decline() }
    } Elseif ($_.IsSuperseded) {
        Write-Output "Declining $($_.Title) [superseded]"
        If (-Not $DryRun) { $_.Decline() }
    } Elseif ($_.PublicationState -eq "Expired") {
        Write-Output "Declining $($_.Title) [expired]"
        If (-Not $DryRun) { $_.Decline() }
    } Elseif (-Not $_.IsApproved) {
        If ($auto_approve_classifications.Contains($_.UpdateClassificationTitle)) {
            If ($_.RequiresLicenseAgreementAcceptance) {
                Write-Output "Accepting license agreement for $($_.Title)"
                If (-Not $DryRun) { $_.AcceptLicenseAgreement() }
            }

            Write-Output "Approving $($_.Title)"
            If (-Not $DryRun) { $_.Approve("Install", $group) }
        }
    }
}
