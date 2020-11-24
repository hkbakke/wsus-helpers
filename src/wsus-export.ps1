param (
    [string]$WsusSync = "$PSScriptRoot\wsus-sync.ps1",
    [string]$SyncDir,
    [string]$WsusApprove = "$PSScriptRoot\wsus-approve.ps1",
    [string]$WsusMaintenance = "$PSScriptRoot\wsus-maintenance.ps1"
)

& $WsusApprove
if (-Not ($?)) {
    exit 1
}

& $WsusMaintenance -Full
if (-Not ($?)) {
    exit 1
}

& $WsusSync -Mode export -SyncDir $SyncDir
if (-Not ($?)) {
    exit 1
}
