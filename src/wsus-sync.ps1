param (
    [ValidateSet("import", "export")][String]$Mode,
    [String]$SyncDir,
    [String]$WSUSDir = "D:\wsus"
)

$wsusutil = "C:\Program Files\Update Services\Tools\WsusUtil.exe"
$exportfile = $($WSUSDir + "\export.xml.gz")


function log ($text) {
    Write-Output $text | Out-File -Append $logfile
}

function get_script_dir {
    $invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $invocation.MyCommand.Path
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
    & $wsusutil export $exportfile $($logdir + "\wsus_export.log")
    if (-Not ($?)) {
        exit $LASTEXITCODE
    }
}

function wsus_import ($exportfile) {
    & $wsusutil import $exportfile $($logdir + "\wsus_import.log")
    if (-Not ($?)) {
        exit $LASTEXITCODE
    }
}

function export_sync ($src, $dst) {
    & robocopy $src $dst /UNILOG+:$logfile /TEE /NP /MIR /R:5 /W:60 /XF syncing
    if ($LASTEXITCODE -gt 8) {
        exit $LASTEXITCODE
    }
}

function import_sync ($src, $dst) {
    & robocopy $src $dst /UNILOG+:$logfile /TEE /NP /MIR /R:5 /W:60 /XD UpdateServicesPackages
    if ($LASTEXITCODE -gt 8) {
        exit $LASTEXITCODE
    }
}


#
# Run
#

$syncroot = (Get-Item $(get_script_dir)).Parent.FullName
$logdir = $($syncroot + "\logs\")
$logfile = $($logdir + "\file_sync.log")
$lastsync = $($SyncDir + "\lastsync")
$syncing = $($SyncDir + "\syncing")

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
	
    # Export Wsus database
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
    $lastimport = $($syncroot + "\lastimport")

    if (Test-Path $lastimport) {
        $lastimport_time = Get-Date -Date $(Get-Content $lastimport)
        if ($lastimport_time -ge $lastsync_time) {
            log "Incoming sync timestamp must be newer than the previous import timestamp"
            exit 2
        }
    }

    # Sync syncdir to WSUS content dir
    import_sync $SyncDir $WSUSDir
	
    # Import WsusConfiguration
    wsus_import $exportfile
    
    # Write import timestamp to lastimport
    store_timestamp $lastimport
}