# This script should never be executed when WSUS synchronization is running. It will try its best to enforce
# this by itself but you should also try to avoid this by proper job scheduling.

param (
    [string]$WsusServer = "localhost",
    [int]$Port = 8530,
    [switch]$UseSSL,
    [switch]$Init,
    [switch]$Full
)

$sqlcmd = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE"
$CreateWsusIndexes = "$PSScriptRoot\CreateWsusIndexes.sql"
$WsusDBMaintenance = "$PSScriptRoot\WsusDBMaintenance.sql"
$logs = "$PSScriptRoot\logs"

# Delete declined updates from database. Note that updates still being matched by existing categories and languages
# will reappear after the next sync. This is primarily useful to get rid of old updates when you have removed and
# declined things from the category or language list. This job is only executed if -Full is used.
$delete_declined = $true


[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($WsusServer, $UseSSL, $Port)
$subscription = $wsus.GetSubscription()

# Wait for any currently running synchronization jobs to finish before continuing
function Check-Sync {
    if ($subscription.GetSynchronizationStatus() -ne "NotProcessing") {
        throw "WSUS is synchronizing"
    }
}

if ($Init) {
    # Create a couple of WSUS indexes to speed things up. Nothing happens if you run this
    # every time, but you'll get an error saying that an index already 
    Check-Sync
    & $sqlcmd -S np:\\.\pipe\MICROSOFT##WID\tsql\query -i $CreateWsusIndexes -I -o $logs/CreateWsusIndexes.log
}

# Run WSUS maintenance jobs
if ($Full) {
    $cleanupScope = new-object Microsoft.UpdateServices.Administration.CleanupScope
    #$cleanupScope.DeclineSupersededUpdates = $true # Handled by wsus-approve.ps1
    #$cleanupScope.DeclineExpiredUpdates = $true # Handled by wsus-approve.ps1

    if ($delete_declined) {
        $declined_updates = $wsus.GetUpdates() | Where-Object {$_.IsDeclined}
        $declined_updates | Foreach-Object {$wsus.DeleteUpdate($_.Id.UpdateId)}
    }

    $cleanupScope.CleanupObsoleteUpdates = $true
    $cleanupScope.CompressUpdates = $true
    $cleanupScope.CleanupObsoleteComputers = $true
    $cleanupScope.CleanupUnneededContentFiles = $true
    $cleanupScope.CleanupLocalPublishedContentFiles = $true
    $cleanupManager = $wsus.GetCleanupManager()
    $cleanupManager.PerformCleanup($cleanupScope) | Out-File $logs\WsusCleanup.log
}

# Reindex WSUS DB
Check-Sync
& $sqlcmd -S np:\\.\pipe\MICROSOFT##WID\tsql\query -i $WsusDBMaintenance -I -o $logs/WsusDBMaintenance.log
