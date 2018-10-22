param (
    [string]$WsusServer = 'wsus',
    [int]$Port = 8530,
    [switch]$UseSSL,
    [switch]$DryRun
)

[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($WsusServer, $UseSSL, $Port)

$updates = $wsus.GetUpdates() | Where-Object {-not $_.IsDeclined}
$updates | Foreach-Object {
    # Delete updates with missing files. If the update still exists in the source WSUS it should be readded
    # during the next import. This should hopefully fix any inconstencies as long as the WSUS server on the
    # import side does not approve any updates that is not approved on the export server.
    if ($_.State -eq "NotReady") {
        Write-Output "Removing $($_.Title)"
        if (-not $DryRun) {
            $_.Decline()
            $wsus.DeleteUpdate($_.Id.UpdateId.ToString())
        }
    }
}
