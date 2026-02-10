# Compare-VMMSettings

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)
![SCVMM](https://img.shields.io/badge/SCVMM-2019%20%7C%202022%20%7C%202025-5C2D91?logo=microsoft&logoColor=white)
![Module Version](https://img.shields.io/badge/Version-1.5.0-orange)
![Functions](https://img.shields.io/badge/Functions-4-informational)

A PowerShell module for **comparing and reporting on VMM Port Profile settings** and their bindings across the System Center Virtual Machine Manager (SCVMM) fabric.

Quickly identify where port profiles are used, which logical switches reference them, and how two profiles differ — all from the command line.

## Features

- **Retrieve** all vNIC native port profiles with their full settings and binding context
- **Compare** two port profiles property-by-property with a clear match/diff report
- **Matrix view** of key settings across multiple profiles at once — spot differences instantly
- **Cross-reference** profiles against logical switches in a single binding matrix
- Uplink port profiles excluded by default — opt-in with `-IncludeUplinkProfiles`
- Structured output objects for further pipeline processing, `Format-Table` display, or CSV export

## Requirements

| Requirement | Version |
|---|---|
| PowerShell | 5.1+ |
| VirtualMachineManager module | (ships with the SCVMM console) |
| SCVMM server | Reachable via network |

## Installation

Copy the module folder to a location on your `$env:PSModulePath`, or import directly:

```powershell
Import-Module .\Compare-VMMSettings.psd1
```

## Connecting to a VMM Server

All functions accept an optional `-VMMServer` parameter. If omitted, the current
default VMM connection is used (established by a prior `Get-SCVMMServer` call).

**Option 1 — Hostname (default port 8100):**

```powershell
Get-VMMPortProfileUsage -VMMServer 'vmm01.contoso.com'
```

**Option 2 — Hostname with custom port:**

```powershell
Get-VMMPortProfileUsage -VMMServer 'vmm01.contoso.com:8101'
```

**Option 3 — Pre-established connection object:**

```powershell
$vmm = Get-SCVMMServer -ComputerName 'vmm01.contoso.com' -TCPPort 8100
Get-VMMPortProfileUsage -VMMServer $vmm
```

**Option 4 — Rely on existing session default (no parameter needed):**

```powershell
# If you already ran Get-SCVMMServer earlier in your session:
Get-VMMPortProfileUsage
```

> **Note:** When you pass a string, the module calls `Get-SCVMMServer` internally
> to establish the session default. All subsequent SC cmdlets then use that
> connection implicitly.

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
$result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' `
                                 -DifferenceProfileName 'LowLatency'
$result.PropertyComparison | Format-Table -AutoSize
```

**Console header output:**

```
=== Port Profile Comparison ===
Reference : HighBandwidth
Difference: LowLatency
Type      : VirtualNetworkAdapter
Matching  : 12/14  |  Differing: 2/14
```

**`PropertyComparison` table output:**

| Property | HighBandwidth | LowLatency | Match |
|---|---|---|---|
| AllowIeeePriorityTagging | True | True | True |
| AllowMacAddressSpoofing | False | False | True |
| AllowTeaming | True | True | True |
| EnableDhcpGuard | False | False | True |
| EnableGuestIPNetworkVirtualizationUpdates | False | False | True |
| EnableRouterGuard | False | False | True |
| EnableVmq | True | False | False |
| EnableIPsecOffload | True | True | True |
| EnableVrss | True | True | True |
| EnableIov | False | False | True |
| MinimumBandwidthWeight | 80 | 50 | False |
| MinimumBandwidthAbsolute | 0 | 0 | True |
| MaximumBandwidth | 10000 | 10000 | True |
| PortACL | *not set* | *not set* | True |

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
$result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' `
                                 -DifferenceProfileName 'LowLatency' `
                                 -DifferencesOnly
$result.PropertyComparison | Format-Table -AutoSize
```

**Console header output:**

```
=== Port Profile Comparison ===
Reference : HighBandwidth
Difference: LowLatency
Type      : VirtualNetworkAdapter
Matching  : 12/14  |  Differing: 2/14
```

**`PropertyComparison` table output (differences only):**

| Property | HighBandwidth | LowLatency | Match |
|---|---|---|---|
| EnableVmq | True | False | False |
| MinimumBandwidthWeight | 80 | 50 | False |

### 6. Compare uplink profiles

```powershell
$result = Compare-VMMPortProfile -ReferenceProfileName 'UplinkTeamLBFO' `
                                 -DifferenceProfileName 'UplinkTeamSET' `
                                 -IncludeUplinkProfiles
$result.PropertyComparison | Format-Table -AutoSize
```

**Console header output:**

```
=== Port Profile Comparison ===
Reference : UplinkTeamLBFO
Difference: UplinkTeamSET
Type      : NativeUplink
Matching  : 2/3  |  Differing: 1/3
```

**`PropertyComparison` table output:**

| Property | UplinkTeamLBFO | UplinkTeamSET | Match |
|---|---|---|---|
| EnableNetworkVirtualization | True | True | True |
| LBFOLoadBalancingAlgorithm | HyperVPort | Dynamic | False |
| LBFOTeamMode | SwitchIndependent | SwitchIndependent | True |

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
# Using a hostname (connects on default port 8100)
Get-VMMPortProfileUsage -VMMServer 'vmm01.contoso.com' |
    Format-Table Name, LogicalSwitchNames, PortProfileSetNames -AutoSize

# Using a custom port
Get-VMMPortProfileUsage -VMMServer 'vmm01.contoso.com:8101' |
    Format-Table Name, LogicalSwitchNames, PortProfileSetNames -AutoSize

# Using a pre-established connection object
$vmm = Get-SCVMMServer -ComputerName 'vmm01.contoso.com' -TCPPort 8100
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
Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency', 'GuestDefault' |
    Format-Table -AutoSize
```

**Console header output:**

```
=== Port Profile Settings Matrix ===
Profiles: HighBandwidth, LowLatency, GuestDefault
Settings: 14  |  All identical: 8  |  Differ: 6
```

**Table output:**

| Setting | HighBandwidth | LowLatency | GuestDefault | AllMatch |
|---|---|---|---|---|
| AllowIeeePriorityTagging | True | True | True | True |
| AllowMacAddressSpoofing | False | False | True | False |
| AllowTeaming | True | True | False | False |
| EnableDhcpGuard | False | False | False | True |
| EnableGuestIPNetworkVirtualizationUpdates | False | False | False | True |
| EnableRouterGuard | False | False | False | True |
| EnableVmq | True | False | False | False |
| EnableIPsecOffload | True | True | False | False |
| EnableVrss | True | True | True | True |
| EnableIov | False | False | False | True |
| MinimumBandwidthWeight | 80 | 50 | 20 | False |
| MinimumBandwidthAbsolute | 0 | 0 | 0 | True |
| MaximumBandwidth | 10000 | 10000 | 5000 | False |
| PortACL | *not set* | *not set* | *not set* | True |

### 14. Settings matrix — show only differences

```powershell
Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency', 'GuestDefault' |
    Where-Object { -not $_.AllMatch } |
    Format-Table -AutoSize
```

**Output:**

| Setting | HighBandwidth | LowLatency | GuestDefault | AllMatch |
|---|---|---|---|---|
| AllowMacAddressSpoofing | False | False | True | False |
| AllowTeaming | True | True | False | False |
| EnableVmq | True | False | False | False |
| EnableIPsecOffload | True | True | False | False |
| MinimumBandwidthWeight | 80 | 50 | 20 | False |
| MaximumBandwidth | 10000 | 10000 | 5000 | False |

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
├── Samples/
│   ├── Sample-Usage.ps1        # Quick-start interactive examples
│   └── Sample-AuditDrift.ps1   # Automated drift-detection script
└── Tests/
    └── Compare-VMMSettings.Tests.ps1  # Pester 5.x unit tests (mocked, no VMM required)
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
