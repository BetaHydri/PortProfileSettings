#Requires -Modules VirtualMachineManager

<#
.SYNOPSIS
    Module for comparing and reporting on VMM Port Profile settings and their bindings.

.DESCRIPTION
    Provides functions to retrieve, compare, and report on Virtual Network Adapter
    Port Profiles and their settings in System Center Virtual Machine Manager (VMM).
    Helps identify where Port Profiles are used and bound to across the VMM fabric.

    By default, only virtual network adapter (vNIC) port profiles are included.
    Uplink port profiles can be included via the -IncludeUplinkProfiles switch.
#>

#region Helper Functions

function Get-PortProfilePropertyMap {
    <#
    .SYNOPSIS
        Returns the list of comparable properties for a given port profile type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('VirtualNetworkAdapter', 'NativeUplink')]
        [string]$ProfileType
    )

    switch ($ProfileType) {
        'VirtualNetworkAdapter' {
            @(
                'Name'
                'Description'
                'AllowIeeePriorityTagging'
                'AllowMacAddressSpoofing'
                'AllowTeaming'
                'EnableDhcpGuard'
                'EnableGuestIPNetworkVirtualizationUpdates'
                'EnableRouterGuard'
                'EnableVmq'
                'EnableIPsecOffload'
                'EnableVrss'
                'EnableIov'
                'MinimumBandwidthWeight'
                'MinimumBandwidthAbsolute'
                'MaximumBandwidth'
                'PortACL'
            )
        }
        'NativeUplink' {
            @(
                'Name'
                'Description'
                'EnableNetworkVirtualization'
                'LBFOLoadBalancingAlgorithm'
                'LBFOTeamMode'
            )
        }
    }
}

function Format-PropertyComparison {
    <#
    .SYNOPSIS
        Compares two objects property-by-property and returns difference records.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ReferenceObject,

        [Parameter(Mandatory)]
        $DifferenceObject,

        [Parameter(Mandatory)]
        [string[]]$Properties,

        [string]$ReferenceName = 'Reference',
        [string]$DifferenceName = 'Difference'
    )

    foreach ($prop in $Properties) {
        $refValue = $ReferenceObject.$prop
        $diffValue = $DifferenceObject.$prop

        # Normalise nulls for comparison
        $refStr = if ($null -eq $refValue) { '<not set>' } else { "$refValue" }
        $diffStr = if ($null -eq $diffValue) { '<not set>' } else { "$diffValue" }

        $match = $refStr -eq $diffStr

        [PSCustomObject]@{
            Property        = $prop
            $ReferenceName  = $refStr
            $DifferenceName = $diffStr
            Match           = $match
        }
    }
}

#endregion

#region Public Functions

function Get-VMMPortProfileUsage {
    <#
    .SYNOPSIS
        Retrieves VMM port profiles with their settings and shows where they are bound.

    .DESCRIPTION
        Collects all virtual network adapter native port profiles (and optionally
        native uplink port profiles) from VMM, enriches each with the logical
        switches and port profile sets that reference them, and returns a summary
        object per profile.

    .PARAMETER Name
        Filter port profiles by name. Supports wildcards.

    .PARAMETER VMMServer
        The VMM server connection to query. If omitted, the current default connection is used.

    .PARAMETER IncludeUplinkProfiles
        When specified, native uplink port profiles are also included in the output.

    .EXAMPLE
        Get-VMMPortProfileUsage

        Returns all vNIC native port profiles with their settings and binding
        information (logical switches, port profile sets, port classifications).

    .EXAMPLE
        Get-VMMPortProfileUsage -IncludeUplinkProfiles

        Returns all vNIC **and** native uplink port profiles with their bindings.
        Uplink profiles are excluded by default and only appear when this switch
        is specified.

    .EXAMPLE
        Get-VMMPortProfileUsage -Name "High*"

        Returns only vNIC port profiles whose name matches the wildcard pattern
        "High*", e.g. "HighBandwidth", "HighPerformance".

    .EXAMPLE
        Get-VMMPortProfileUsage | Where-Object LogicalSwitchNames -eq '' | Select-Object Name

        Lists all vNIC port profiles that are not bound to any logical switch.
        Useful for finding orphaned or unused profiles.

    .EXAMPLE
        Get-VMMPortProfileUsage | Format-Table Name, LogicalSwitchNames, PortClassificationNames -AutoSize

        Displays a quick overview table of all port profiles and their bindings.

    .EXAMPLE
        Get-VMMPortProfileUsage -VMMServer (Get-SCVMMServer -ComputerName "vmm01.contoso.com")

        Queries a specific VMM server for port profile usage information.

    .LINK
        Compare-VMMPortProfile

    .LINK
        Get-VMMPortProfileBindingMatrix
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter()]
        $VMMServer,

        [Parameter()]
        [switch]$IncludeUplinkProfiles
    )

    begin {
        $serverParam = @{}
        if ($VMMServer) { $serverParam['VMMServer'] = $VMMServer }

        $results = [System.Collections.Generic.List[PSObject]]::new()
    }

    process {
        # --- Virtual Network Adapter Native Port Profiles ---
        Write-Verbose 'Retrieving virtual network adapter native port profiles...'
        $vNicProfiles = if ($Name) {
            Get-SCVirtualNetworkAdapterNativePortProfile -Name $Name @serverParam -ErrorAction SilentlyContinue
        }
        else {
            Get-SCVirtualNetworkAdapterNativePortProfile @serverParam
        }

        # Pre-fetch port profile sets and logical switches for look-up
        Write-Verbose 'Retrieving port profile sets and logical switches...'
        $allPortProfileSets = Get-SCVirtualNetworkAdapterPortProfileSet @serverParam
        $allLogicalSwitches = Get-SCLogicalSwitch @serverParam

        foreach ($profile in $vNicProfiles) {
            # Find port profile sets that reference this native port profile
            $boundSets = $allPortProfileSets | Where-Object {
                $_.NativePortProfile.ID -eq $profile.ID
            }

            # Derive which logical switches use those port profile sets
            $boundSwitches = foreach ($pps in $boundSets) {
                $allLogicalSwitches | Where-Object {
                    $_.VirtualNetworkAdapterPortProfileSets.ID -contains $pps.ID -or
                    $_.ID -eq $pps.LogicalSwitch.ID
                }
            }
            $boundSwitches = $boundSwitches | Sort-Object -Property Name -Unique

            # Gather port classifications from the port profile sets
            $classifications = ($boundSets | ForEach-Object { $_.PortClassification } |
                Where-Object { $_ } | Sort-Object -Property Name -Unique)

            $obj = [PSCustomObject]@{
                PSTypeName                                = 'VMM.PortProfileUsage'
                ProfileType                               = 'VirtualNetworkAdapter'
                Name                                      = $profile.Name
                Description                               = $profile.Description
                ID                                        = $profile.ID
                # Key settings
                AllowIeeePriorityTagging                  = $profile.AllowIeeePriorityTagging
                AllowMacAddressSpoofing                   = $profile.AllowMacAddressSpoofing
                AllowTeaming                              = $profile.AllowTeaming
                EnableDhcpGuard                           = $profile.EnableDhcpGuard
                EnableGuestIPNetworkVirtualizationUpdates = $profile.EnableGuestIPNetworkVirtualizationUpdates
                EnableRouterGuard                         = $profile.EnableRouterGuard
                EnableVmq                                 = $profile.EnableVmq
                EnableIPsecOffload                        = $profile.EnableIPsecOffload
                EnableVrss                                = $profile.EnableVrss
                EnableIov                                 = $profile.EnableIov
                MinimumBandwidthWeight                    = $profile.MinimumBandwidthWeight
                MinimumBandwidthAbsolute                  = $profile.MinimumBandwidthAbsolute
                MaximumBandwidth                          = $profile.MaximumBandwidth
                PortACL                                   = $profile.PortACL
                # Bindings
                PortProfileSets                           = $boundSets
                PortProfileSetNames                       = ($boundSets | ForEach-Object { $_.Name }) -join ', '
                LogicalSwitches                           = $boundSwitches
                LogicalSwitchNames                        = ($boundSwitches | ForEach-Object { $_.Name }) -join ', '
                PortClassifications                       = $classifications
                PortClassificationNames                   = ($classifications | ForEach-Object { $_.Name }) -join ', '
                SourceObject                              = $profile
            }

            $results.Add($obj)
        }

        # --- Native Uplink Port Profiles (opt-in) ---
        if ($IncludeUplinkProfiles) {
            Write-Verbose 'Retrieving native uplink port profiles...'
            $uplinkProfiles = if ($Name) {
                Get-SCNativeUplinkPortProfile -Name $Name @serverParam -ErrorAction SilentlyContinue
            }
            else {
                Get-SCNativeUplinkPortProfile @serverParam
            }

            $allUplinkSets = Get-SCUplinkPortProfileSet @serverParam

            foreach ($profile in $uplinkProfiles) {
                $boundSets = $allUplinkSets | Where-Object {
                    $_.NativeUplinkPortProfile.ID -eq $profile.ID
                }

                $boundSwitches = foreach ($ups in $boundSets) {
                    $allLogicalSwitches | Where-Object {
                        $_.UplinkPortProfileSets.ID -contains $ups.ID -or
                        $_.ID -eq $ups.LogicalSwitch.ID
                    }
                }
                $boundSwitches = $boundSwitches | Sort-Object -Property Name -Unique

                $obj = [PSCustomObject]@{
                    PSTypeName                  = 'VMM.PortProfileUsage'
                    ProfileType                 = 'NativeUplink'
                    Name                        = $profile.Name
                    Description                 = $profile.Description
                    ID                          = $profile.ID
                    EnableNetworkVirtualization = $profile.EnableNetworkVirtualization
                    LBFOLoadBalancingAlgorithm  = $profile.LBFOLoadBalancingAlgorithm
                    LBFOTeamMode                = $profile.LBFOTeamMode
                    # Bindings
                    UplinkPortProfileSets       = $boundSets
                    UplinkPortProfileSetNames   = ($boundSets | ForEach-Object { $_.Name }) -join ', '
                    LogicalSwitches             = $boundSwitches
                    LogicalSwitchNames          = ($boundSwitches | ForEach-Object { $_.Name }) -join ', '
                    SourceObject                = $profile
                }

                $results.Add($obj)
            }
        }
    }

    end {
        $results
    }
}


function Compare-VMMPortProfile {
    <#
    .SYNOPSIS
        Compares two VMM port profiles and reports differences in their settings.

    .DESCRIPTION
        Takes two port profile names (or objects) and performs a property-by-property
        comparison of their settings. Returns a table showing each property with the
        values from both profiles and whether they match.

        By default only virtual network adapter native port profiles are compared.
        Use -IncludeUplinkProfiles to compare uplink profiles instead.

    .PARAMETER ReferenceProfileName
        Name of the first (reference) port profile.

    .PARAMETER DifferenceProfileName
        Name of the second (difference) port profile.

    .PARAMETER ReferenceProfile
        A port profile object to use as the reference side of the comparison.

    .PARAMETER DifferenceProfile
        A port profile object to use as the difference side of the comparison.

    .PARAMETER VMMServer
        The VMM server connection to query. If omitted, the current default connection is used.

    .PARAMETER IncludeUplinkProfiles
        When specified, compares native uplink port profiles instead of vNIC port profiles.

    .PARAMETER DifferencesOnly
        When specified, only properties that differ between the two profiles are returned.

    .EXAMPLE
        Compare-VMMPortProfile -ReferenceProfileName "HighBandwidth" -DifferenceProfileName "LowBandwidth"

        Compares every setting of the two vNIC native port profiles side by side
        and shows where they are bound (logical switches, port profile sets).
        Output includes a formatted table with OK / <<< DIFF markers.

    .EXAMPLE
        Compare-VMMPortProfile -ReferenceProfileName "HighBandwidth" -DifferenceProfileName "LowBandwidth" -DifferencesOnly

        Same as above but only the properties that actually differ are shown.
        Handy when you just need to see what changed between two profiles.

    .EXAMPLE
        Compare-VMMPortProfile -ReferenceProfileName "UplinkA" -DifferenceProfileName "UplinkB" -IncludeUplinkProfiles

        Compares two **native uplink** port profiles. Without -IncludeUplinkProfiles
        the cmdlet looks for vNIC profiles and would not find uplink profiles.

    .EXAMPLE
        $ref  = Get-SCVirtualNetworkAdapterNativePortProfile -Name "ProfileA"
        $diff = Get-SCVirtualNetworkAdapterNativePortProfile -Name "ProfileB"
        Compare-VMMPortProfile -ReferenceProfile $ref -DifferenceProfile $diff

        Passes pre-fetched profile objects directly instead of resolving by name.
        Useful in scripts where you already have the objects available.

    .EXAMPLE
        $result = Compare-VMMPortProfile "ProfileA" "ProfileB"
        $result.PropertyComparison | Export-Csv -Path .\Comparison.csv -NoTypeInformation

        Captures the structured comparison result and exports the property-level
        details to a CSV file for documentation or auditing.

    .LINK
        Get-VMMPortProfileUsage

    .LINK
        Get-VMMPortProfileBindingMatrix
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [string]$ReferenceProfileName,

        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 1)]
        [string]$DifferenceProfileName,

        [Parameter(Mandatory, ParameterSetName = 'ByObject')]
        $ReferenceProfile,

        [Parameter(Mandatory, ParameterSetName = 'ByObject')]
        $DifferenceProfile,

        [Parameter()]
        $VMMServer,

        [Parameter()]
        [switch]$IncludeUplinkProfiles,

        [Parameter()]
        [switch]$DifferencesOnly
    )

    $serverParam = @{}
    if ($VMMServer) { $serverParam['VMMServer'] = $VMMServer }

    # Resolve profiles by name
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        if ($IncludeUplinkProfiles) {
            $ReferenceProfile = Get-SCNativeUplinkPortProfile -Name $ReferenceProfileName @serverParam
            $DifferenceProfile = Get-SCNativeUplinkPortProfile -Name $DifferenceProfileName @serverParam
        }
        else {
            $ReferenceProfile = Get-SCVirtualNetworkAdapterNativePortProfile -Name $ReferenceProfileName @serverParam
            $DifferenceProfile = Get-SCVirtualNetworkAdapterNativePortProfile -Name $DifferenceProfileName @serverParam
        }
    }

    if (-not $ReferenceProfile) {
        Write-Error "Reference profile '$ReferenceProfileName' not found."
        return
    }
    if (-not $DifferenceProfile) {
        Write-Error "Difference profile '$DifferenceProfileName' not found."
        return
    }

    # Determine profile type and properties to compare
    $profileType = if ($IncludeUplinkProfiles) { 'NativeUplink' } else { 'VirtualNetworkAdapter' }
    $properties = Get-PortProfilePropertyMap -ProfileType $profileType

    # Run property comparison
    $comparison = Format-PropertyComparison `
        -ReferenceObject  $ReferenceProfile `
        -DifferenceObject $DifferenceProfile `
        -Properties       $properties `
        -ReferenceName    $ReferenceProfile.Name `
        -DifferenceName   $DifferenceProfile.Name

    if ($DifferencesOnly) {
        $comparison = $comparison | Where-Object { -not $_.Match }
    }

    # Add binding context for both profiles
    Write-Verbose 'Resolving port profile bindings...'
    $refUsage = Get-VMMPortProfileUsage -Name $ReferenceProfile.Name @serverParam -IncludeUplinkProfiles:$IncludeUplinkProfiles
    $diffUsage = Get-VMMPortProfileUsage -Name $DifferenceProfile.Name @serverParam -IncludeUplinkProfiles:$IncludeUplinkProfiles

    # Build summary output
    $summary = [PSCustomObject]@{
        PSTypeName          = 'VMM.PortProfileComparison'
        ReferenceProfile    = $ReferenceProfile.Name
        DifferenceProfile   = $DifferenceProfile.Name
        ProfileType         = $profileType
        PropertyComparison  = $comparison
        TotalProperties     = ($comparison | Measure-Object).Count
        MatchingProperties  = ($comparison | Where-Object { $_.Match } | Measure-Object).Count
        DifferingProperties = ($comparison | Where-Object { -not $_.Match } | Measure-Object).Count
        ReferenceBindings   = $refUsage
        DifferenceBindings  = $diffUsage
    }

    # Display output
    Write-Host "`n=== Port Profile Comparison ===" -ForegroundColor Cyan
    Write-Host "Reference : $($ReferenceProfile.Name)" -ForegroundColor Green
    Write-Host "Difference: $($DifferenceProfile.Name)" -ForegroundColor Yellow
    Write-Host "Type      : $profileType"
    Write-Host ("Matching  : {0}/{1}  |  Differing: {2}/{1}" -f $summary.MatchingProperties, $summary.TotalProperties, $summary.DifferingProperties)
    Write-Host ''

    $comparison | Format-Table -AutoSize -Property Property,
    @{Name = $ReferenceProfile.Name; Expression = { $_.$($ReferenceProfile.Name) } },
    @{Name = $DifferenceProfile.Name; Expression = { $_.$($DifferenceProfile.Name) } },
    @{Name = 'Match'; Expression = {
            if ($_.Match) { 'OK' } else { '<<< DIFF' }
        }
    }

    # Show bindings
    Write-Host '--- Bindings ---' -ForegroundColor Cyan

    if ($refUsage) {
        Write-Host "`n  [$($ReferenceProfile.Name)]" -ForegroundColor Green
        Write-Host "    Logical Switches     : $(if ($refUsage.LogicalSwitchNames) { $refUsage.LogicalSwitchNames } else { '<none>' })"
        Write-Host "    Port Profile Sets    : $(if ($refUsage.PortProfileSetNames) { $refUsage.PortProfileSetNames } elseif ($refUsage.UplinkPortProfileSetNames) { $refUsage.UplinkPortProfileSetNames } else { '<none>' })"
        if ($refUsage.PortClassificationNames) {
            Write-Host "    Port Classifications : $($refUsage.PortClassificationNames)"
        }
    }

    if ($diffUsage) {
        Write-Host "`n  [$($DifferenceProfile.Name)]" -ForegroundColor Yellow
        Write-Host "    Logical Switches     : $(if ($diffUsage.LogicalSwitchNames) { $diffUsage.LogicalSwitchNames } else { '<none>' })"
        Write-Host "    Port Profile Sets    : $(if ($diffUsage.PortProfileSetNames) { $diffUsage.PortProfileSetNames } elseif ($diffUsage.UplinkPortProfileSetNames) { $diffUsage.UplinkPortProfileSetNames } else { '<none>' })"
        if ($diffUsage.PortClassificationNames) {
            Write-Host "    Port Classifications : $($diffUsage.PortClassificationNames)"
        }
    }

    Write-Host ''

    # Return structured object for pipeline usage
    $summary
}


function Get-VMMPortProfileBindingMatrix {
    <#
    .SYNOPSIS
        Produces a matrix showing which port profiles are bound to which logical switches.

    .DESCRIPTION
        Queries all port profiles and all logical switches, then builds a cross-reference
        matrix that makes it easy to see at a glance which profiles are assigned where.

    .PARAMETER VMMServer
        The VMM server connection to query.

    .PARAMETER IncludeUplinkProfiles
        When specified, native uplink port profiles are also included in the matrix.

    .EXAMPLE
        Get-VMMPortProfileBindingMatrix

        Shows a cross-reference of every vNIC native port profile with its
        logical switch and port profile set bindings.

    .EXAMPLE
        Get-VMMPortProfileBindingMatrix -IncludeUplinkProfiles | Format-Table -AutoSize

        Includes both vNIC and uplink profiles in the matrix and formats
        the output as a wide table for easy reading.

    .EXAMPLE
        Get-VMMPortProfileBindingMatrix | Where-Object LogicalSwitches -eq '<unbound>'

        Filters the matrix to show only port profiles that are not assigned
        to any logical switch. Useful for cleanup tasks.

    .EXAMPLE
        Get-VMMPortProfileBindingMatrix | Export-Csv -Path .\BindingMatrix.csv -NoTypeInformation

        Exports the full binding matrix to CSV for reporting or auditing.

    .LINK
        Get-VMMPortProfileUsage

    .LINK
        Compare-VMMPortProfile
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        $VMMServer,

        [Parameter()]
        [switch]$IncludeUplinkProfiles
    )

    $serverParam = @{}
    if ($VMMServer) { $serverParam['VMMServer'] = $VMMServer }

    $allUsage = Get-VMMPortProfileUsage @serverParam -IncludeUplinkProfiles:$IncludeUplinkProfiles

    foreach ($usage in $allUsage) {
        $switchNames = if ($usage.ProfileType -eq 'VirtualNetworkAdapter') {
            $usage.LogicalSwitchNames
        }
        else {
            $usage.LogicalSwitchNames
        }

        $profileSetNames = if ($usage.ProfileType -eq 'VirtualNetworkAdapter') {
            $usage.PortProfileSetNames
        }
        else {
            $usage.UplinkPortProfileSetNames
        }

        [PSCustomObject]@{
            PSTypeName      = 'VMM.PortProfileBindingMatrix'
            ProfileType     = $usage.ProfileType
            ProfileName     = $usage.Name
            Description     = $usage.Description
            LogicalSwitches = if ($switchNames) { $switchNames } else { '<unbound>' }
            PortProfileSets = if ($profileSetNames) { $profileSetNames } else { '<unbound>' }
            Classifications = if ($usage.PortClassificationNames) { $usage.PortClassificationNames } else { '-' }
        }
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'Get-VMMPortProfileUsage'
    'Compare-VMMPortProfile'
    'Get-VMMPortProfileBindingMatrix'
)

#endregion