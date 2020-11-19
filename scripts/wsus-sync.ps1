param (
    [ValidateSet("import", "export")][String]$Mode,
    [String]$SyncDir,
    [String]$WSUSDir = "D:\wsus"
)

$wsusutil = "C:\Program Files\Update Services\Tools\WsusUtil.exe"
$exportfile = "$WSUSDir\export.xml.gz"
$maintenance = "$PSScriptRoot\wsus-maintenance.ps1"
$logdir = "$PSScriptRoot\logs\"
$logfile = "$logdir\wsus-sync.log"
$export_log = "$logdir\wsus-export.log"
$import_log = "$logdir\wsus-import.log"
$lastsync = "$SyncDir\lastsync"
$syncing = "$SyncDir\syncing"

[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, 8530)
$subscription = $wsus.GetSubscription()

function log ($text) {
    Write-Output "$(get-date -format s): $text" | Tee-Object -Append $logfile
}

function create_dir ($directory) {
    if (-Not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType directory | Out-Null
        if (-Not ($?)) {
            log "ERROR: Could not create $directory"
            exit 1
        }
    }
}

function store_timestamp ($file) {
    Get-Date -Format s | Out-File $file
}

function wsus_export ($exportfile) {
    & $wsusutil export $exportfile "$export_log"
    if (-Not ($?)) {
        exit 1
    }
}

function wsus_import ($exportfile) {
    & $wsusutil import $exportfile "$import_log"
    if (-Not ($?)) {
        exit 1
    }
}

function export_sync ($src, $dst) {
    & robocopy $src $dst /UNILOG+:$logfile /TEE /NP /MIR /R:5 /W:60 /XF syncing
    if ($LASTEXITCODE -gt 8) {
        exit $LASTEXITCODE
    }
}

function import_sync ($src, $dst) {
    # Do not use /MIR or /PURGE to delete files in destination WSUS folder that does
    # not exist in the source, as there may be approved updates in the destination WSUS that
    # will get angry and add bitstransfer jobs if the files suddenly disappears. Use
    # maintenance jobs to keep destination server tidy as you would usually do
    & robocopy $src $dst /UNILOG+:$logfile /TEE /NP /E /R:5 /W:60 /XD UpdateServicesPackages
    if ($LASTEXITCODE -gt 8) {
        exit $LASTEXITCODE
    }
}



create_dir $logdir

# Reset logfile
if (Test-Path $logfile) {
    Remove-Item $logfile
}

if ($Mode -eq "export") {
    # Write a syncing file to ensure the importing end is not starting a import
    # while an export is ongoing
    Write-Output "Sync started at $(Get-Date -Format s)" | Out-File $syncing
    if ($LASTEXITCODE -gt 0) {
        log "Could not write syncing file $syncing"
        exit $LASTEXITCODE
    }

    # Wait for any currently running synchronization jobs to finish before continuing
    while ($subscription.GetSynchronizationStatus() -ne "NotProcessing") {
        log "Waiting for synchronization to finish..."
        Start-Sleep -s 10
    }

    # Wait for any currently running downloads to complete before continuing
    while ($wsus.GetContentDownloadProgress().TotalBytesToDownload -gt 0) {
        $total = $wsus.GetContentDownloadProgress().TotalBytesToDownload
        $downloaded = $wsus.GetContentDownloadProgress().DownloadedBytes
        log "Waiting for downloads to finish. Progress: $([math]::Round($downloaded / $total * 100))%"
        Start-Sleep -s 10
    }

    # Export Wsus database
    log "Starting WSUS export"
    wsus_export $exportfile

    # Sync WSUS content to syncdir
    export_sync $WSUSDir $SyncDir

    # Clear syncing file
    Remove-Item $syncing

    # Write timestamp to lastsync
    store_timestamp $lastsync
} elseif ($Mode -eq "import") {
    if (Test-Path $syncing) {
        log "An export is currently ongoing. Exiting..."
        exit 3
    }

    if (-Not (Test-Path $lastsync)) {
        log "$lastsync not found"
        exit 1
    }

    $lastsync_time = Get-Date -Date $(Get-Content $lastsync)
    $lastimport = "$PSScriptRoot\lastimport"

    if (Test-Path $lastimport) {
        $lastimport_time = Get-Date -Date $(Get-Content $lastimport)
        if ($lastimport_time -ge $lastsync_time) {
            log "Incoming sync timestamp must be newer than the previous import timestamp"
            exit 2
        }
    }

    # Cancel any currently running downloads, as the import will provide the WSUS content
    $wsus.CancelAllDownloads()

    # Run full maintenance to clean out old stuff only just before import, to shorten the period
    # where there are updates that WSUS does not know about.
    & $maintenance -Full

    # Sync syncdir to WSUS content dir
    import_sync $SyncDir $WSUSDir

    # Import WsusConfiguration
     og "Starting WSUS export"
    wsus_import $exportfile

    # Write import timestamp to lastimport
    store_timestamp $lastimport
}
