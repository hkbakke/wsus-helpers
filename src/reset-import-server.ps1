Param (
    [string]$WsusServer = 'wsus',
    [int]$Port = 8530,
    [bool]$UseSSL = $False
)

[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($WsusServer, $UseSSL, $Port)

$updates = $wsus.GetUpdates() | Where-Object {-Not $_.IsDeclined}
$updates | Foreach-Object {
    If ($_.State -eq "NotReady") {
        Write-Host "Removing $($_.Title)"
        $wsus.DeleteUpdate($_.Id.UpdateId.ToString())
    }
}