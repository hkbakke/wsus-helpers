Param (
    [string]$WsusServer = 'wsus',
    [int]$Port = 8530,
    [switch]$UseSSL
)

[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($WsusServer, $UseSSL, $Port)

$updates = $wsus.GetUpdates() | Where-Object {-Not $_.IsDeclined}
$updates | Foreach-Object {
    # Delete updates with missing files. If the update still exists in the source WSUS it should be readded
    # during the next import. This should hopefully fix any inconstencies as long as the WSUS server on the
    # import side does not approve any updates that is not approved on the export server.
    If ($_.State -eq "NotReady") {
        Write-Output "Removing $($_.Title)"
        $wsus.DeleteUpdate($_.Id.UpdateId.ToString())
    }
}
