# This script should never be executed when WSUS synchronization is running. It will try its best to enforce
# this by itself but you should also try to avoid this by proper job scheduling.

param (
    [string]$WsusServer = "localhost",
    [int]$Port = 8530,
    [switch]$UseSSL,
    [switch]$Init,
    [switch]$DeleteDeclined,
    [switch]$Full
)

$sqlcmd = "sqlcmd"
$CreateWsusIndexes = "$PSScriptRoot\CreateWsusIndexes.sql"
$WsusDBMaintenance = "$PSScriptRoot\WsusDBMaintenance.sql"
$logdir = "$PSScriptRoot\logs"
$logfile = "$logdir\wsus-maintenance.log"
$dbmaint_log = "$logdir\WsusDBMaintenance.log"


function Check-Sync {
    if ($subscription.GetSynchronizationStatus() -ne "NotProcessing") {
        throw "WSUS is synchronizing"
    }
}

function log ($text) {
    Write-Output "$(get-date -format s): $text" | Tee-Object -Append $logfile
}

# Reset logfile
if (Test-Path $logfile) {
    Remove-Item $logfile
}

[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($WsusServer, $UseSSL, $Port)

if ($Init) {
    # Create a couple of WSUS indexes to speed things up. Nothing happens if you run this
    # every time, but you'll get an error saying that an index already exists
    Check-Sync
    log "Creating WSUS database indexes"
    & $sqlcmd -S np:\\.\pipe\MICROSOFT##WID\tsql\query -i $CreateWsusIndexes -I -o "$logdir\wsus-init-indexes.log"
    if (-Not ($?)) {
        log "ERROR: WSUS index initialization failed"
        exit 1
    }
    log "WSUS database indexes created"
}

# Delete declined updates from database. Note that updates still being matched by existing categories and languages
# will reappear after the next sync which will take much longer than normal. This is primarily useful to get rid of
# old updates when you have removed and declined things from the category or language list.
if ($DeleteDeclined) {
    log "Deleting declined updates"
    $declined_updates = $wsus.GetUpdates() | Where-Object {$_.IsDeclined}
    $declined_updates | Foreach-Object {
        log "Deleting declined update: $($_.Title)"
        $wsus.DeleteUpdate($_.Id.UpdateId)
    }
}

# Run WSUS maintenance jobs
if ($Full) {
    log "Starting full maintenance"
    log "Running WSUS cleanup jobs"
    $cleanupScope = new-object Microsoft.UpdateServices.Administration.CleanupScope
    $cleanupScope.DeclineSupersededUpdates = $true
    $cleanupScope.DeclineExpiredUpdates = $true
    $cleanupScope.CleanupObsoleteUpdates = $true
    $cleanupScope.CompressUpdates = $true
    $cleanupScope.CleanupObsoleteComputers = $true
    $cleanupScope.CleanupUnneededContentFiles = $true
    $cleanupScope.CleanupLocalPublishedContentFiles = $true
    $cleanupManager = $wsus.GetCleanupManager()
    $cleanupManager.PerformCleanup($cleanupScope) | Out-File "$logdir\wsus-cleanup.log"
    log "Full maintenance complete"
}

# Reindex WSUS DB
& $sqlcmd -S np:\\.\pipe\MICROSOFT##WID\tsql\query -i $WsusDBMaintenance -I -o "$logdir\wsus-reindex.log"
if (-Not ($?)) {
    log "ERROR: WSUS database reindex failed"
    exit 1
}
log "WSUS database reindex complete"
