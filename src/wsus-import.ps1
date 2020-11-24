param (
    [string]$WsusSync = "$PSScriptRoot\wsus-sync.ps1",
    [string]$SyncDir,
    [string]$WsusApprove = "$PSScriptRoot\wsus-approve.ps1",
    [string]$WsusMaintenance = "$PSScriptRoot\wsus-maintenance.ps1"
)

& $WsusSync -Mode import -SyncDir $SyncDir
if (-Not ($?)) {
    exit 1
}

& $WsusApprove -NoSync
if (-Not ($?)) {
    exit 1
}

& $WsusMaintenance -Full
if (-Not ($?)) {
    exit 1
}
