param (
    [string]$WsusSync = "$PSScriptRoot\wsus-sync.ps1",
    [string]$SyncDir,
    [string]$WsusApprove = "$PSScriptRoot\wsus-approve.ps1",
    [string]$WsusMaintenance = "$PSScriptRoot\wsus-maintenance.ps1"
)

& $WsusSync -Mode import -SyncDir $SyncDir
if ($LASTEXITCODE -eq 0) {
    & $WsusApprove -NoSync
    & $WsusMaintenance
}
