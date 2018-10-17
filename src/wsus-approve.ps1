# Use instead of approval rules as the approval rule system is too limited

Param (
    [string]$WsusServer = 'wsus',
    [int]$Port = 8530,
    [bool]$UseSSL = $False,
    [bool]$Sync = $True
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

If ($Sync) {
    If ($subscription.GetSynchronizationStatus() -eq "NotProcessing") {
        Write-Host "Starting synchronization..."
        $subscription.StartSynchronization()
    }
}

# Wait for any currently running synchronization jobs to finish before continuing
While ($subscription.GetSynchronizationStatus() -ne "NotProcessing") {
    Write-Host "Waiting for synchronization to finish..."
    Start-Sleep -s 10
}

# Ensure decline rules are processed first!
$updates = $wsus.GetUpdates() | Where-Object {-Not $_.IsDeclined}
$updates | Foreach-Object {
    If ($_.Title -Match 'ia64|itanium') {
        Write-Host "Declining $($_.Title) [itanium]"
        $_.Decline()
    } Elseif ($_.Title -Match 'arm64') {
        Write-Host "Declining $($_.Title) [arm]"
        $_.Decline()
    } Elseif ($_.Title -Match 'preview') {
        Write-Host "Declining $($_.Title) [preview]"
        $_.Decline()
    } Elseif ($_.IsBeta) {
        Write-Host "Declining $($_.Title) [beta]"
        $_.Decline()		
    } Elseif ($_.IsSuperseded) {
        Write-Host "Declining $($_.Title) [superseded]"
        $_.Decline()
    } Elseif (-Not $_.IsApproved) {
        If ($auto_approve_classifications.Contains($_.UpdateClassificationTitle)) {
            If ($_.RequiresLicenseAgreementAcceptance) {
                $_.AcceptLicenseAgreement()
            }

            Write-Host "Approving $($_.Title)"
            $_.Approve("Install", $group)
        }
    }
}
