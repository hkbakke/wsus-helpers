param (
    [string]$WsusSync = "$PSScriptRoot\wsus-sync.ps1",
    [string]$SyncDir,
    [string]$WsusApprove = "$PSScriptRoot\wsus-approve.ps1",
    [string]$WsusMaintenance = "$PSScriptRoot\wsus-maintenance.ps1"
)

& $WsusMaintenance -Full
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $WsusApprove
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $WsusMaintenance
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $WsusSync -Mode export -SyncDir $SyncDir
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
