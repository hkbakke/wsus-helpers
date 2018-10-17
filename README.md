# wsus-helpers
Helper scripts for WSUS management

## wsus-sync
File based sync to servers without direct internet connectivity

## wsus-approve
For your own sanity you should remove all approval rules and disable automatic sync in WSUS before using this script to handle syncs and approvals.

Allows for more complex approval rules than the ones in WSUS GUI. By default it declines the following updates automatically:
* Itanium updates
* ARM updates
* Beta updates
* Preview updates
* Superseded updates

It approves all other updates automatically for "All Computers" group with the exception of "Upgrades" category, which is left for manual approval.

## wsus-import
Wrapper for wsus-sync to run wsus-approve automatically after wsus-sync import as it only makes sense to check for new updates after an import for offline servers
