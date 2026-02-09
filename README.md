# Compare-VMMSettings

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)
![SCVMM](https://img.shields.io/badge/SCVMM-2019%20%7C%202022%20%7C%202025-5C2D91?logo=microsoft&logoColor=white)
![Module Version](https://img.shields.io/badge/Version-1.1.0-orange)
![Functions](https://img.shields.io/badge/Functions-4-informational)

A PowerShell module for **comparing and reporting on VMM Port Profile settings** and their bindings across the System Center Virtual Machine Manager (SCVMM) fabric.

Quickly identify where port profiles are used, which logical switches reference them, and how two profiles differ — all from the command line.

## Features

- **Retrieve** all vNIC native port profiles with their full settings and binding context
- **Compare** two port profiles property-by-property with a clear OK / DIFF report
- **Cross-reference** profiles against logical switches in a single binding matrix
- Uplink port profiles excluded by default — opt-in with `-IncludeUplinkProfiles`
- Structured output objects for further pipeline processing or CSV export

## Requirements

| Requirement | Version |
|---|---|
| PowerShell | 5.1+ |
| VirtualMachineManager module | (ships with the SCVMM console) |
| SCVMM server connection | `Get-SCVMMServer` |

## Installation

Copy the module folder to a location on your `$env:PSModulePath`, or import directly:

```powershell
Import-Module .\Compare-VMMSettings.psd1
```

## Exported Functions

| Function | Description |
|---|---|
| `Get-VMMPortProfileUsage` | Retrieves port profiles with their settings and shows where they are bound |
| `Compare-VMMPortProfile` | Side-by-side comparison of two port profiles with binding context |
| `Compare-VMMPortProfileSettings` | Multi-profile key-settings matrix (rows = settings, columns = profiles) |
| `Get-VMMPortProfileBindingMatrix` | Cross-reference matrix of profiles → logical switches |

---

## Usage & Sample Output

### 1. List all vNIC port profiles and their bindings

```powershell
Get-VMMPortProfileUsage |
    Format-Table Name, LogicalSwitchNames, PortClassificationNames -AutoSize
```

**Output:**

| Name | LogicalSwitchNames | PortClassificationNames |
|---|---|---|
| HighBandwidth | ConvergedSwitch01, MgmtSwitch | High Bandwidth, SR-IOV |
| LowLatency | ConvergedSwitch01 | Low Latency |
| GuestDefault | ConvergedSwitch01, TestSwitch | Guest Dynamic |
| ManagementOS | MgmtSwitch | Host Management |
| LiveMigration | ConvergedSwitch01 | Live Migration |
| ClusterHeartbeat | ConvergedSwitch01 | Cluster |

### 2. Find orphaned / unbound port profiles

```powershell
Get-VMMPortProfileUsage |
    Where-Object { -not $_.LogicalSwitchNames } |
    Select-Object Name, Description
```

**Output:**

| Name | Description |
|---|---|
| OldTestProfile | Legacy test profile – no longer in use |
| DeprecatedSRIOV | Was used for SR-IOV testing, now replaced |

### 3. Include uplink profiles

```powershell
Get-VMMPortProfileUsage -IncludeUplinkProfiles |
    Format-Table ProfileType, Name, LogicalSwitchNames -AutoSize
```

**Output:**

| ProfileType | Name | LogicalSwitchNames |
|---|---|---|
| VirtualNetworkAdapter | HighBandwidth | ConvergedSwitch01, MgmtSwitch |
| VirtualNetworkAdapter | LowLatency | ConvergedSwitch01 |
| VirtualNetworkAdapter | GuestDefault | ConvergedSwitch01, TestSwitch |
| NativeUplink | UplinkTeamLBFO | ConvergedSwitch01 |
| NativeUplink | UplinkTeamSET | MgmtSwitch |
| NativeUplink | StandaloneUplink | TestSwitch |

### 4. Compare two vNIC port profiles — full comparison

```powershell
Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' `
                       -DifferenceProfileName 'LowLatency'
```

**Output:**

```
=== Port Profile Comparison ===
Reference : HighBandwidth
Difference: LowLatency
Type      : VirtualNetworkAdapter
Matching  : 12/16  |  Differing: 4/16
```

| Property | HighBandwidth | LowLatency | Match |
|---|---|---|---|
| Name | HighBandwidth | LowLatency | ⚠ DIFF |
| Description | High throughput | Low latency NIC | ⚠ DIFF |
| AllowIeeePriorityTagging | True | True | ✅ OK |
| AllowMacAddressSpoofing | False | False | ✅ OK |
| AllowTeaming | True | True | ✅ OK |
| EnableDhcpGuard | False | False | ✅ OK |
| EnableGuestIPNetworkVirtualizationUpdates | False | False | ✅ OK |
| EnableRouterGuard | False | False | ✅ OK |
| EnableVmq | True | False | ⚠ DIFF |
| EnableIPsecOffload | True | True | ✅ OK |
| EnableVrss | True | True | ✅ OK |
| EnableIov | False | False | ✅ OK |
| MinimumBandwidthWeight | 80 | 50 | ⚠ DIFF |
| MinimumBandwidthAbsolute | 0 | 0 | ✅ OK |
| MaximumBandwidth | 10000 | 10000 | ✅ OK |
| PortACL | *not set* | *not set* | ✅ OK |

```
--- Bindings ---

  [HighBandwidth]
    Logical Switches     : ConvergedSwitch01, MgmtSwitch
    Port Profile Sets    : HighBW-PPS, MgmtHigh-PPS
    Port Classifications : High Bandwidth, SR-IOV

  [LowLatency]
    Logical Switches     : ConvergedSwitch01
    Port Profile Sets    : LowLat-PPS
    Port Classifications : Low Latency
```

### 5. Compare two profiles — differences only

```powershell
Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' `
                       -DifferenceProfileName 'LowLatency' `
                       -DifferencesOnly
```

**Output:**

```
=== Port Profile Comparison ===
Reference : HighBandwidth
Difference: LowLatency
Type      : VirtualNetworkAdapter
Matching  : 12/16  |  Differing: 4/16
```

| Property | HighBandwidth | LowLatency | Match |
|---|---|---|---|
| Name | HighBandwidth | LowLatency | ⚠ DIFF |
| Description | High throughput | Low latency NIC | ⚠ DIFF |
| EnableVmq | True | False | ⚠ DIFF |
| MinimumBandwidthWeight | 80 | 50 | ⚠ DIFF |

### 6. Compare uplink profiles

```powershell
Compare-VMMPortProfile -ReferenceProfileName 'UplinkTeamLBFO' `
                       -DifferenceProfileName 'UplinkTeamSET' `
                       -IncludeUplinkProfiles
```

**Output:**

```
=== Port Profile Comparison ===
Reference : UplinkTeamLBFO
Difference: UplinkTeamSET
Type      : NativeUplink
Matching  : 2/5  |  Differing: 3/5
```

| Property | UplinkTeamLBFO | UplinkTeamSET | Match |
|---|---|---|---|
| Name | UplinkTeamLBFO | UplinkTeamSET | ⚠ DIFF |
| Description | LBFO team uplink | SET team uplink | ⚠ DIFF |
| EnableNetworkVirtualization | True | True | ✅ OK |
| LBFOLoadBalancingAlgorithm | HyperVPort | Dynamic | ⚠ DIFF |
| LBFOTeamMode | SwitchIndependent | SwitchIndependent | ✅ OK |

```
--- Bindings ---

  [UplinkTeamLBFO]
    Logical Switches     : ConvergedSwitch01
    Port Profile Sets    : LBFO-UplinkPPS

  [UplinkTeamSET]
    Logical Switches     : MgmtSwitch
    Port Profile Sets    : SET-UplinkPPS
```

### 7. Binding matrix overview

```powershell
Get-VMMPortProfileBindingMatrix | Format-Table -AutoSize
```

**Output:**

| ProfileType | ProfileName | Description | LogicalSwitches | PortProfileSets | Classifications |
|---|---|---|---|---|---|
| VirtualNetworkAdapter | HighBandwidth | High throughput | ConvergedSwitch01, MgmtSwitch | HighBW-PPS, MgmtHigh | High Bandwidth, SR-IOV |
| VirtualNetworkAdapter | LowLatency | Low latency NIC | ConvergedSwitch01 | LowLat-PPS | Low Latency |
| VirtualNetworkAdapter | GuestDefault | Default guest NIC | ConvergedSwitch01, TestSwitch | Guest-PPS, Test-PPS | Guest Dynamic |
| VirtualNetworkAdapter | ManagementOS | Host mgmt adapter | MgmtSwitch | MgmtOS-PPS | Host Management |
| VirtualNetworkAdapter | OldTestProfile | Legacy test profile | *unbound* | *unbound* | - |

### 8. Find unbound profiles in the matrix

```powershell
Get-VMMPortProfileBindingMatrix |
    Where-Object LogicalSwitches -eq '<unbound>'
```

**Output:**

| ProfileType | ProfileName | Description | LogicalSwitches | PortProfileSets | Classifications |
|---|---|---|---|---|---|
| VirtualNetworkAdapter | OldTestProfile | Legacy test profile | *unbound* | *unbound* | - |

### 9. Export comparison to CSV

```powershell
$result = Compare-VMMPortProfile 'HighBandwidth' 'LowLatency'
$result.PropertyComparison | Export-Csv -Path .\ProfileComparison.csv -NoTypeInformation
```

The CSV will contain columns: `Property`, `HighBandwidth`, `LowLatency`, `Match`.

### 10. Export binding matrix to CSV

```powershell
Get-VMMPortProfileBindingMatrix -IncludeUplinkProfiles |
    Export-Csv -Path .\BindingMatrix.csv -NoTypeInformation
```

### 11. Query a specific VMM server

```powershell
$vmm = Get-SCVMMServer -ComputerName 'vmm01.contoso.com'
Get-VMMPortProfileUsage -VMMServer $vmm |
    Format-Table Name, LogicalSwitchNames, PortProfileSetNames -AutoSize
```

### 12. Audit drift against a golden baseline

```powershell
.\Samples\Sample-AuditDrift.ps1 -ReferenceProfileName 'GoldenProfile'
```

**Output:**

```
Drift detected in 6 setting(s).
Report saved to: .\AuditReport.csv
```

| ProfileName | DriftCount | AffectedSettings |
|---|---|---|
| LowLatency | 2 | EnableVmq, MinimumBandwidthWeight |
| OldTestProfile | 4 | AllowTeaming, EnableVmq, EnableVrss, MinimumBandwidthWeight |

### 13. Settings matrix — compare multiple profiles at once

```powershell
Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency', 'GuestDefault'
```

**Output:**

```
=== Port Profile Settings Matrix ===
Profiles: HighBandwidth, LowLatency, GuestDefault
Settings: 14  |  All identical: 8  |  Differ: 6
```

| Setting | HighBandwidth | LowLatency | GuestDefault | AllMatch |
|---|---|---|---|---|
| AllowIeeePriorityTagging | True | True | True | ✅ OK |
| AllowMacAddressSpoofing | False | False | True | ⚠ DIFF |
| AllowTeaming | True | True | False | ⚠ DIFF |
| EnableDhcpGuard | False | False | False | ✅ OK |
| EnableGuestIPNetworkVirtualizationUpdates | False | False | False | ✅ OK |
| EnableRouterGuard | False | False | False | ✅ OK |
| EnableVmq | True | False | False | ⚠ DIFF |
| EnableIPsecOffload | True | True | False | ⚠ DIFF |
| EnableVrss | True | True | True | ✅ OK |
| EnableIov | False | False | False | ✅ OK |
| MinimumBandwidthWeight | 80 | 50 | 20 | ⚠ DIFF |
| MinimumBandwidthAbsolute | 0 | 0 | 0 | ✅ OK |
| MaximumBandwidth | 10000 | 10000 | 5000 | ⚠ DIFF |
| PortACL | *not set* | *not set* | *not set* | ✅ OK |

### 14. Settings matrix — show only differences

```powershell
Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency', 'GuestDefault' |
    Where-Object { -not $_.AllMatch }
```

**Output:**

| Setting | HighBandwidth | LowLatency | GuestDefault | AllMatch |
|---|---|---|---|---|
| AllowMacAddressSpoofing | False | False | True | ⚠ DIFF |
| AllowTeaming | True | True | False | ⚠ DIFF |
| EnableVmq | True | False | False | ⚠ DIFF |
| EnableIPsecOffload | True | True | False | ⚠ DIFF |
| MinimumBandwidthWeight | 80 | 50 | 20 | ⚠ DIFF |
| MaximumBandwidth | 10000 | 10000 | 5000 | ⚠ DIFF |

### 15. Settings matrix — all profiles with highlighted differences

```powershell
Compare-VMMPortProfileSettings -HighlightDifferences
```

Outputs the full matrix to the console with differing rows printed in **yellow**
for quick visual identification.

---

## Return Objects

All functions return structured PowerShell objects for pipeline use:

| Type Name | Returned By | Key Properties |
|---|---|---|
| `VMM.PortProfileUsage` | `Get-VMMPortProfileUsage` | `Name`, `ProfileType`, all settings, `LogicalSwitchNames`, `PortProfileSetNames`, `PortClassificationNames` |
| `VMM.PortProfileComparison` | `Compare-VMMPortProfile` | `PropertyComparison` (array), `MatchingProperties`, `DifferingProperties`, `ReferenceBindings`, `DifferenceBindings` |
| `VMM.PortProfileSettingsMatrix` | `Compare-VMMPortProfileSettings` | `Setting`, one column per profile name, `AllMatch` |
| `VMM.PortProfileBindingMatrix` | `Get-VMMPortProfileBindingMatrix` | `ProfileName`, `ProfileType`, `LogicalSwitches`, `PortProfileSets`, `Classifications` |

## Project Structure

```
Compare-VMMSettings/
├── Compare-VMMSettings.psd1    # Module manifest
├── Compare-VMMSettings.psm1    # Module implementation
├── LICENSE                     # MIT license
├── README.md                   # This file
└── Samples/
    ├── Sample-Usage.ps1        # Quick-start interactive examples
    └── Sample-AuditDrift.ps1   # Automated drift-detection script
```

## Getting Help

```powershell
# Overview of all functions
Get-Command -Module Compare-VMMSettings

# Detailed help with examples
Get-Help Get-VMMPortProfileUsage -Full
Get-Help Compare-VMMPortProfile -Examples
Get-Help Compare-VMMPortProfileSettings -Examples
Get-Help Get-VMMPortProfileBindingMatrix -Examples
```

## License

This project is licensed under the [MIT License](LICENSE).
