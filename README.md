# wsus-helpers
Helper scripts for WSUS management

## wsus-approve
Allows for more complex approval rules than the ones in WSUS GUI. By default it declines the following updates automatically:

* Itanium/IA64 updates
* ARM64 updates
* x86 Updates
* Beta updates
* Preview updates
* Expired updates
* Superseded updates

It approves all other updates automatically for "All Computers" group with the exception of "Upgrades" category, which is left for manual approval.

For your own sanity you should remove all approval rules, unselect all advanced approval options and disable automatic sync in WSUS before using this script to handle syncs and approvals.

## wsus-maintenance
WSUS database maintenance script. The script has three modes

    # Create indexes and reindex. It is only necessary to run this once
    wsus-maintenance.ps1 -Init

    # Reindex. Run after every sync and maintenance
    wsus-maintenance.ps1

    # Reindex, run the built-in WSUS maintenance jobs and delete declined updates
    wsus-maintenance.ps1 -Full
    
## Scheduling recommendations
Create a daily task that runs these actions
1. wsus-approve.ps1
2. wsus-maintenance.ps1

Create a monthly task that runs this action
1. wsus-maintenance.ps1 -Full

# Offline WSUS sync
## wsus-sync
File based sync to servers without direct internet connectivity

## wsus-import
Wrapper for wsus-sync to run wsus-approve automatically after wsus-sync import as it only makes sense to check for new updates after an import for offline servers

# Credits
* CreateWsusIndexes.sql: https://support.microsoft.com/en-us/help/4490644/complete-guide-to-microsoft-wsus-and-configuration-manager-sup-maint
* WsusDBMaintenance.sql: https://gallery.technet.microsoft.com/scriptcenter/6f8cde49-5c52-4abd-9820-f1d270ddea61
