<#
.SYNOPSIS
    Quick-start examples for the Compare-VMMSettings module.

.DESCRIPTION
    This script demonstrates the most common usage patterns of the module.
    Run each section interactively or copy individual snippets as needed.

    Prerequisites:
      - System Center VMM console / PowerShell module installed
      - A reachable VMM server (connection is handled via -VMMServer or a prior Get-SCVMMServer call)

.NOTES
    Module : Compare-VMMSettings
    Version: 1.5.0
#>

#requires -Modules VirtualMachineManager

# ──────────────────────────────────────────────────────────────────────────────
# 0. Import the module
# ──────────────────────────────────────────────────────────────────────────────
Import-Module .\Compare-VMMSettings.psd1 -Force

# ──────────────────────────────────────────────────────────────────────────────
# 0a. Connect to a VMM server (pick one of the options below)
# ──────────────────────────────────────────────────────────────────────────────
# Option 1: Pass a hostname string — connects on default port 8100
#   Every function supports -VMMServer, e.g.:
#   Get-VMMPortProfileUsage -VMMServer 'vmm01.contoso.com'

# Option 2: Pass hostname:port for a custom port
#   Get-VMMPortProfileUsage -VMMServer 'vmm01.contoso.com:8101'

# Option 3: Pass a pre-established connection object
#   $vmm = Get-SCVMMServer -ComputerName 'vmm01.contoso.com' -TCPPort 8100
#   Get-VMMPortProfileUsage -VMMServer $vmm

# Option 4: Rely on an existing session default (no -VMMServer needed)
#   If you already ran Get-SCVMMServer earlier in your session, all functions
#   will use that connection automatically.

# ──────────────────────────────────────────────────────────────────────────────
# 1. List all vNIC port profiles and see where they are bound
# ──────────────────────────────────────────────────────────────────────────────
Get-VMMPortProfileUsage |
Format-Table Name, LogicalSwitchNames, PortClassificationNames -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 2. Find orphaned / unbound port profiles
# ──────────────────────────────────────────────────────────────────────────────
Get-VMMPortProfileUsage |
Where-Object { -not $_.LogicalSwitchNames } |
Select-Object Name, Description

# ──────────────────────────────────────────────────────────────────────────────
# 3. Filter by wildcard name
# ──────────────────────────────────────────────────────────────────────────────
Get-VMMPortProfileUsage -Name 'High*'

# ──────────────────────────────────────────────────────────────────────────────
# 4. Include uplink profiles as well
# ──────────────────────────────────────────────────────────────────────────────
Get-VMMPortProfileUsage -IncludeUplinkProfiles |
Format-Table ProfileType, Name, LogicalSwitchNames -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 5. Compare two vNIC port profiles – full comparison (table view)
# ──────────────────────────────────────────────────────────────────────────────
$result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' `
    -DifferenceProfileName 'LowBandwidth'
$result.PropertyComparison | Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 6. Compare two vNIC port profiles – differences only (table view)
# ──────────────────────────────────────────────────────────────────────────────
$result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' `
    -DifferenceProfileName 'LowBandwidth' `
    -DifferencesOnly
$result.PropertyComparison | Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 7. Compare two uplink profiles (table view)
# ──────────────────────────────────────────────────────────────────────────────
$result = Compare-VMMPortProfile -ReferenceProfileName 'UplinkTeamA' `
    -DifferenceProfileName 'UplinkTeamB' `
    -IncludeUplinkProfiles
$result.PropertyComparison | Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 8. Export a comparison to CSV for documentation / auditing
# ──────────────────────────────────────────────────────────────────────────────
$result = Compare-VMMPortProfile 'ProfileA' 'ProfileB'
$result.PropertyComparison | Export-Csv -Path .\ProfileComparison.csv -NoTypeInformation
Write-Host "Exported to .\ProfileComparison.csv"

# ──────────────────────────────────────────────────────────────────────────────
# 9. Pass profile objects directly (pipeline / scripting scenario)
# ──────────────────────────────────────────────────────────────────────────────
$ref = Get-SCVirtualNetworkAdapterNativePortProfile -Name 'ProfileA'
$diff = Get-SCVirtualNetworkAdapterNativePortProfile -Name 'ProfileB'
Compare-VMMPortProfile -ReferenceProfile $ref -DifferenceProfile $diff

# ──────────────────────────────────────────────────────────────────────────────
# 10. Binding matrix – quick cross-reference of profiles ↔ logical switches
# ──────────────────────────────────────────────────────────────────────────────
Get-VMMPortProfileBindingMatrix | Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 11. Binding matrix – include uplinks, export to CSV
# ──────────────────────────────────────────────────────────────────────────────
Get-VMMPortProfileBindingMatrix -IncludeUplinkProfiles |
Export-Csv -Path .\BindingMatrix.csv -NoTypeInformation
Write-Host "Exported to .\BindingMatrix.csv"

# ──────────────────────────────────────────────────────────────────────────────
# 12. Query a specific VMM server (all connection variants)
# ──────────────────────────────────────────────────────────────────────────────
# Hostname (default port 8100)
Get-VMMPortProfileUsage -VMMServer 'vmm01.contoso.com' |
    Format-Table Name, LogicalSwitchNames, PortProfileSetNames -AutoSize

# Hostname with custom port
Get-VMMPortProfileUsage -VMMServer 'vmm01.contoso.com:8101' |
    Format-Table Name, LogicalSwitchNames, PortProfileSetNames -AutoSize

# Pre-established connection object
$vmm = Get-SCVMMServer -ComputerName 'vmm01.contoso.com' -TCPPort 8100
Get-VMMPortProfileUsage -VMMServer $vmm |

# ──────────────────────────────────────────────────────────────────────────────
# 13. Settings matrix – compare key settings of multiple profiles at once (table view)
# ──────────────────────────────────────────────────────────────────────────────
Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency', 'GuestDefault' |
Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 14. Settings matrix – show only differing settings (table view)
# ──────────────────────────────────────────────────────────────────────────────
Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency', 'GuestDefault' |
Where-Object { -not $_.AllMatch } |
Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 15. Settings matrix – all profiles (table view)
# ──────────────────────────────────────────────────────────────────────────────
Compare-VMMPortProfileSettings | Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 16. Settings matrix – pipe profile objects directly
# ──────────────────────────────────────────────────────────────────────────────
$profiles = Get-SCVirtualNetworkAdapterNativePortProfile
Compare-VMMPortProfileSettings -ProfileObject $profiles

# ──────────────────────────────────────────────────────────────────────────────
# 17. Settings matrix – include uplink profiles in the comparison (table view)
# ──────────────────────────────────────────────────────────────────────────────
Compare-VMMPortProfileSettings -Name 'UplinkTeamLBFO', 'UplinkTeamSET' -IncludeUplinkProfiles |
Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 18. Settings matrix – export differences to CSV
# ──────────────────────────────────────────────────────────────────────────────
Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency', 'GuestDefault' |
Where-Object { -not $_.AllMatch } |
Export-Csv -Path .\SettingsMatrixDiff.csv -NoTypeInformation
Write-Host "Exported to .\SettingsMatrixDiff.csv"
