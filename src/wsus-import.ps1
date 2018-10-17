$wsus_sync = "path-to-wsus-sync.ps1"
$sync_dir = "pat-to-sync-dir"
$wsus_approve = "path-to-wsus-approve.ps1"

& $wsus_sync -Mode import -SyncDir $sync_dir

if ($LASTEXITCODE -ne 0) {
    & $wsus_approve -Sync:$false
}