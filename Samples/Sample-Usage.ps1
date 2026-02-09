<#
.SYNOPSIS
    Quick-start examples for the Compare-VMMSettings module.

.DESCRIPTION
    This script demonstrates the most common usage patterns of the module.
    Run each section interactively or copy individual snippets as needed.

    Prerequisites:
      - System Center VMM console / PowerShell module installed
      - An active connection to a VMM server (Get-SCVMMServer)

.NOTES
    Module : Compare-VMMSettings
    Version: 1.0.0
#>

#requires -Modules VirtualMachineManager

# ──────────────────────────────────────────────────────────────────────────────
# 0. Import the module
# ──────────────────────────────────────────────────────────────────────────────
Import-Module .\Compare-VMMSettings.psd1 -Force

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
# 5. Compare two vNIC port profiles – full comparison
# ──────────────────────────────────────────────────────────────────────────────
Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' `
                       -DifferenceProfileName 'LowBandwidth'

# ──────────────────────────────────────────────────────────────────────────────
# 6. Compare two vNIC port profiles – differences only
# ──────────────────────────────────────────────────────────────────────────────
Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' `
                       -DifferenceProfileName 'LowBandwidth' `
                       -DifferencesOnly

# ──────────────────────────────────────────────────────────────────────────────
# 7. Compare two uplink profiles
# ──────────────────────────────────────────────────────────────────────────────
Compare-VMMPortProfile -ReferenceProfileName 'UplinkTeamA' `
                       -DifferenceProfileName 'UplinkTeamB' `
                       -IncludeUplinkProfiles

# ──────────────────────────────────────────────────────────────────────────────
# 8. Export a comparison to CSV for documentation / auditing
# ──────────────────────────────────────────────────────────────────────────────
$result = Compare-VMMPortProfile 'ProfileA' 'ProfileB'
$result.PropertyComparison | Export-Csv -Path .\ProfileComparison.csv -NoTypeInformation
Write-Host "Exported to .\ProfileComparison.csv"

# ──────────────────────────────────────────────────────────────────────────────
# 9. Pass profile objects directly (pipeline / scripting scenario)
# ──────────────────────────────────────────────────────────────────────────────
$ref  = Get-SCVirtualNetworkAdapterNativePortProfile -Name 'ProfileA'
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
# 12. Query a specific VMM server
# ──────────────────────────────────────────────────────────────────────────────
$vmm = Get-SCVMMServer -ComputerName 'vmm01.contoso.com'
Get-VMMPortProfileUsage -VMMServer $vmm |
    Format-Table Name, LogicalSwitchNames, PortProfileSetNames -AutoSize
