<#
.SYNOPSIS
    Audit script: detect port profile drift across a VMM environment.

.DESCRIPTION
    Uses Compare-VMMSettings to compare every vNIC port profile against a chosen
    "golden" reference profile. Outputs a report of which profiles deviate and
    in which settings.

    Useful for periodic compliance checks or change-management audits.

.PARAMETER ReferenceProfileName
    The name of the port profile considered the "golden" baseline.

.PARAMETER VMMServer
    The VMM server to query. Accepts a hostname string (default port 8100),
    'server:port' for custom ports, or an existing VMM server connection object.
    If omitted, the current default connection is used.

.PARAMETER ReportPath
    Path to write the CSV audit report. Defaults to .\AuditReport.csv.

.EXAMPLE
    .\Sample-AuditDrift.ps1 -ReferenceProfileName 'GoldenProfile'

    Compares all vNIC port profiles against 'GoldenProfile' and writes a report.

.EXAMPLE
    .\Sample-AuditDrift.ps1 -ReferenceProfileName 'GoldenProfile' -VMMServer 'vmm01.contoso.com'

    Connects to the specified VMM server and runs the drift audit.

.EXAMPLE
    .\Sample-AuditDrift.ps1 -ReferenceProfileName 'GoldenProfile' -ReportPath C:\Reports\Drift.csv

    Same as above but saves the report to a custom path.

.NOTES
    Module : Compare-VMMSettings
    Version: 1.5.0
#>

#requires -Modules VirtualMachineManager

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReferenceProfileName,

    [Parameter()]
    [string]$VMMServer,

    [Parameter()]
    [string]$ReportPath = '.\AuditReport.csv'
)

Import-Module "$PSScriptRoot\..\Compare-VMMSettings.psd1" -Force

# Build splatting hashtable for -VMMServer
$vmmParam = @{}
if ($VMMServer) { $vmmParam['VMMServer'] = $VMMServer }

# Retrieve all profiles
$allProfiles = Get-VMMPortProfileUsage @vmmParam
$referenceProfile = $allProfiles | Where-Object Name -EQ $ReferenceProfileName

if (-not $referenceProfile) {
    Write-Error "Reference profile '$ReferenceProfileName' not found."
    return
}

$auditResults = [System.Collections.Generic.List[PSObject]]::new()

foreach ($profile in $allProfiles) {
    # Skip self-comparison
    if ($profile.Name -eq $ReferenceProfileName) { continue }

    Write-Verbose "Comparing '$($profile.Name)' against '$ReferenceProfileName'..."

    $comparison = Compare-VMMPortProfile `
        -ReferenceProfileName $ReferenceProfileName `
        -DifferenceProfileName $profile.Name `
        @vmmParam `
        -DifferencesOnly 6>$null  # Suppress host output in batch mode

    if ($comparison.DifferingProperties -gt 0) {
        foreach ($diff in $comparison.PropertyComparison) {
            $auditResults.Add([PSCustomObject]@{
                    ProfileName     = $profile.Name
                    LogicalSwitches = $profile.LogicalSwitchNames
                    Property        = $diff.Property
                    ReferenceValue  = $diff."$ReferenceProfileName"
                    ActualValue     = $diff."$($profile.Name)"
                })
        }
    }
}

# Report
if ($auditResults.Count -eq 0) {
    Write-Host "`nAll profiles match the reference '$ReferenceProfileName'. No drift detected." -ForegroundColor Green
}
else {
    $auditResults | Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host "`nDrift detected in $($auditResults.Count) setting(s)." -ForegroundColor Yellow
    Write-Host "Report saved to: $ReportPath"

    # Also show a summary on screen
    $auditResults |
    Group-Object ProfileName |
    ForEach-Object {
        [PSCustomObject]@{
            ProfileName      = $_.Name
            DriftCount       = $_.Count
            AffectedSettings = ($_.Group.Property | Sort-Object -Unique) -join ', '
        }
    } |
    Format-Table -AutoSize
}
