Param (
    [string]$WsusSync = "$PSScriptRoot\wsus-sync.ps1",
    [string]$SyncDir,
    [string]$WsusApprove = "$PSScriptRoot\wsus-approve.ps1"
)

& $WsusSync -Mode import -SyncDir $SyncDir

if ($LASTEXITCODE -ne 0) {
    & $WsusApprove -Sync:$false
}