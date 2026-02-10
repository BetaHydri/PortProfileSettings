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

function Test-VMMConnection {
    <#
    .SYNOPSIS
        Validates that a VMM server connection is available before querying.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$ServerParam = @{}
    )

    try {
        $null = Get-SCVMMServer @ServerParam -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Resolve-VMMServerConnection {
    <#
    .SYNOPSIS
        Resolves a VMMServer parameter and establishes the VMM connection.
    .DESCRIPTION
        Accepts either a hostname string or an existing VMM server connection object.
        If a string is passed, connects via Get-SCVMMServer. Supports 'server:port'
        notation for custom ports, or just 'server' which defaults to port 8100.

        Once Get-SCVMMServer is called, it sets the default VMM connection for the
        session. All subsequent SC cmdlets use this connection implicitly, so this
        function returns an empty hashtable for splatting. This avoids issues with
        deserialized ServerConnection objects that cannot be passed via -VMMServer.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        $VMMServer
    )

    if (-not $VMMServer) {
        return @{}
    }

    # If it's a string, establish a connection (sets the session default)
    if ($VMMServer -is [string]) {
        if ($VMMServer -match '^(?<host>[^:]+):(?<port>\d+)$') {
            $computerName = $Matches['host']
            $port = [int]$Matches['port']
        }
        else {
            $computerName = $VMMServer
            $port = 8100
        }
        try {
            $null = Get-SCVMMServer -ComputerName $computerName -TCPPort $port -ErrorAction Stop
            Write-Verbose "Connected to VMM server '$computerName' on port $port."
            return @{}
        }
        catch {
            throw "Failed to connect to VMM server '$computerName' on port ${port}: $($_.Exception.Message)"
        }
    }

    # Already a connection object (or deserialized) — the session should already
    # have an active default connection, so no need to pass it explicitly.
    Write-Verbose 'Using existing VMM server connection.'
    return @{}
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
        The VMM server to query. Accepts a hostname string, 'server:port' for custom ports (defaults to port 8100), or an existing VMM server connection object. If omitted, the current default connection is used.

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
        Get-VMMPortProfileUsage -VMMServer 'vmm01.contoso.com'

        Connects to the specified VMM server on port 8100 and retrieves port profile usage.

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
        $serverParam = Resolve-VMMServerConnection -VMMServer $VMMServer

        $results = [System.Collections.Generic.List[PSObject]]::new()
    }

    process {
        # --- Validate VMM connection ---
        try {
            # --- Virtual Network Adapter Native Port Profiles ---
            Write-Verbose 'Retrieving virtual network adapter native port profiles...'
            $vNicProfiles = if ($Name) {
                Get-SCVirtualNetworkAdapterNativePortProfile -Name $Name @serverParam -ErrorAction Stop
            }
            else {
                Get-SCVirtualNetworkAdapterNativePortProfile @serverParam -ErrorAction Stop
            }
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match 'TypeInitializer|BitBos|VMMServer|not connected' -or
                $_.Exception.InnerException) {
                Write-Error ('Cannot connect to VMM. Ensure you have an active VMM server connection ' +
                    '(use Get-SCVMMServer first) or pass -VMMServer. Original error: {0}' -f $msg)
            }
            else {
                Write-Error "Failed to retrieve port profiles: $msg"
            }
            return
        }

        # Pre-fetch port profile sets and logical switches for look-up
        Write-Verbose 'Retrieving port profile sets and logical switches...'
        try {
            $allPortProfileSets = Get-SCVirtualNetworkAdapterPortProfileSet @serverParam -ErrorAction Stop
            $allLogicalSwitches = Get-SCLogicalSwitch @serverParam -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match 'TypeInitializer|BitBos|VMMServer|not connected' -or
                $_.Exception.InnerException) {
                Write-Error ('Cannot connect to VMM. Ensure you have an active VMM server connection ' +
                    '(use Get-SCVMMServer first) or pass -VMMServer. Original error: {0}' -f $msg)
            }
            else {
                Write-Error "Failed to retrieve port profile sets or logical switches: $msg"
            }
            return
        }

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
            try {
                $uplinkProfiles = if ($Name) {
                    Get-SCNativeUplinkPortProfile -Name $Name @serverParam -ErrorAction Stop
                }
                else {
                    Get-SCNativeUplinkPortProfile @serverParam -ErrorAction Stop
                }

                $allUplinkSets = Get-SCUplinkPortProfileSet @serverParam -ErrorAction Stop
            }
            catch {
                $msg = $_.Exception.Message
                if ($msg -match 'TypeInitializer|BitBos|VMMServer|not connected' -or
                    $_.Exception.InnerException) {
                    Write-Error ('Cannot connect to VMM. Ensure you have an active VMM server connection ' +
                        '(use Get-SCVMMServer first) or pass -VMMServer. Original error: {0}' -f $msg)
                }
                else {
                    Write-Error "Failed to retrieve uplink port profiles: $msg"
                }
                return
            }

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
        The VMM server to query. Accepts a hostname string, 'server:port' for custom ports (defaults to port 8100), or an existing VMM server connection object. If omitted, the current default connection is used.

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

    $serverParam = Resolve-VMMServerConnection -VMMServer $VMMServer

    # Resolve profiles by name
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        try {
            if ($IncludeUplinkProfiles) {
                $ReferenceProfile = Get-SCNativeUplinkPortProfile -Name $ReferenceProfileName @serverParam -ErrorAction Stop
                $DifferenceProfile = Get-SCNativeUplinkPortProfile -Name $DifferenceProfileName @serverParam -ErrorAction Stop
            }
            else {
                $ReferenceProfile = Get-SCVirtualNetworkAdapterNativePortProfile -Name $ReferenceProfileName @serverParam -ErrorAction Stop
                $DifferenceProfile = Get-SCVirtualNetworkAdapterNativePortProfile -Name $DifferenceProfileName @serverParam -ErrorAction Stop
            }
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match 'TypeInitializer|BitBos|VMMServer|not connected' -or
                $_.Exception.InnerException) {
                Write-Error ('Cannot connect to VMM. Ensure you have an active VMM server connection ' +
                    '(use Get-SCVMMServer first) or pass -VMMServer. Original error: {0}' -f $msg)
            }
            else {
                Write-Error "Failed to retrieve port profiles: $msg"
            }
            return
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
    $comparisonParams = @{
        ReferenceObject  = $ReferenceProfile
        DifferenceObject = $DifferenceProfile
        Properties       = $properties
        ReferenceName    = $ReferenceProfile.Name
        DifferenceName   = $DifferenceProfile.Name
    }
    $comparison = Format-PropertyComparison @comparisonParams

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

    # Show property comparison table
    Write-Host '--- Property Comparison ---' -ForegroundColor Cyan
    $comparison | Format-Table -AutoSize | Out-String | Write-Host

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
        The VMM server to query. Accepts a hostname string, 'server:port' for custom ports (defaults to port 8100), or an existing VMM server connection object. If omitted, the current default connection is used.

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

    $serverParam = Resolve-VMMServerConnection -VMMServer $VMMServer

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


function Compare-VMMPortProfileSettings {
    <#
    .SYNOPSIS
        Compares key settings of multiple port profiles side by side in a matrix.

    .DESCRIPTION
        Takes two or more port profile names (or objects from Get-VMMPortProfileUsage)
        and builds a matrix where each row is a key setting and each column is a
        profile. A final "AllMatch" column indicates whether every profile has the
        same value for that setting.

        This makes it easy to spot configuration drift across many profiles at once
        rather than comparing them pair by pair.

    .PARAMETER Name
        One or more port profile names to include in the matrix. Supports wildcards.
        When omitted, all vNIC native port profiles are included.

    .PARAMETER ProfileObject
        One or more profile usage objects (from Get-VMMPortProfileUsage) to compare
        directly, bypassing the VMM query.

    .PARAMETER VMMServer
        The VMM server to query. Accepts a hostname string, 'server:port' for custom ports (defaults to port 8100), or an existing VMM server connection object. If omitted, the current default connection is used.

    .PARAMETER IncludeUplinkProfiles
        When specified, native uplink port profiles are compared instead of vNIC profiles.

    .EXAMPLE
        Compare-VMMPortProfileSettings

        Compares all vNIC native port profiles and shows a settings matrix.

    .EXAMPLE
        Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency', 'GuestDefault'

        Compares the three named profiles in a side-by-side settings matrix.

    .EXAMPLE
        Compare-VMMPortProfileSettings -IncludeUplinkProfiles

        Compares all native uplink port profiles in a settings matrix.

    .EXAMPLE
        $profiles = Get-VMMPortProfileUsage -Name 'Profile1', 'Profile2', 'Profile3'
        Compare-VMMPortProfileSettings -ProfileObject $profiles

        Passes pre-fetched profile objects to avoid re-querying VMM.

    .EXAMPLE
        Compare-VMMPortProfileSettings | Where-Object { -not $_.AllMatch }

        Returns only the settings rows where at least one profile differs.

    .LINK
        Get-VMMPortProfileUsage

    .LINK
        Compare-VMMPortProfile

    .LINK
        Get-VMMPortProfileBindingMatrix
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string[]]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        [PSObject[]]$ProfileObject,

        [Parameter()]
        $VMMServer,

        [Parameter()]
        [switch]$IncludeUplinkProfiles
    )

    begin {
        $collectedObjects = [System.Collections.Generic.List[PSObject]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject') {
            foreach ($obj in $ProfileObject) {
                $collectedObjects.Add($obj)
            }
        }
    }

    end {
        $serverParam = Resolve-VMMServerConnection -VMMServer $VMMServer

        # Resolve profiles
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            if ($Name) {
                foreach ($n in $Name) {
                    $found = Get-VMMPortProfileUsage -Name $n @serverParam -IncludeUplinkProfiles:$IncludeUplinkProfiles
                    foreach ($f in $found) { $collectedObjects.Add($f) }
                }
            }
            else {
                $found = Get-VMMPortProfileUsage @serverParam -IncludeUplinkProfiles:$IncludeUplinkProfiles
                foreach ($f in $found) { $collectedObjects.Add($f) }
            }
        }

        if ($collectedObjects.Count -lt 2) {
            Write-Warning 'At least two port profiles are required for a settings comparison matrix.'
            return
        }

        # De-duplicate by profile name
        $profiles = $collectedObjects | Sort-Object -Property Name -Unique

        # Determine which key settings to compare based on the profile types present
        $hasVNic = $profiles | Where-Object ProfileType -EQ 'VirtualNetworkAdapter'
        $hasUplink = $profiles | Where-Object ProfileType -EQ 'NativeUplink'

        $settingsMatrix = [System.Collections.Generic.List[PSObject]]::new()

        if ($hasVNic) {
            $vNicSettings = @(
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

            $vNicProfiles = @($hasVNic)

            foreach ($setting in $vNicSettings) {
                $row = [ordered]@{
                    Setting = $setting
                }

                $values = [System.Collections.Generic.List[string]]::new()

                foreach ($p in $vNicProfiles) {
                    $val = $p.$setting
                    $valStr = if ($null -eq $val) { '<not set>' } else { "$val" }
                    $row[$p.Name] = $valStr
                    $values.Add($valStr)
                }

                $row['AllMatch'] = ($values | Sort-Object -Unique | Measure-Object).Count -eq 1

                $obj = [PSCustomObject]$row
                $obj.PSObject.TypeNames.Insert(0, 'VMM.PortProfileSettingsMatrix')
                $settingsMatrix.Add($obj)
            }
        }

        if ($hasUplink) {
            $uplinkSettings = @(
                'EnableNetworkVirtualization'
                'LBFOLoadBalancingAlgorithm'
                'LBFOTeamMode'
            )

            $uplinkProfiles = @($hasUplink)

            foreach ($setting in $uplinkSettings) {
                $row = [ordered]@{
                    Setting = $setting
                }

                $values = [System.Collections.Generic.List[string]]::new()

                foreach ($p in $uplinkProfiles) {
                    $val = $p.$setting
                    $valStr = if ($null -eq $val) { '<not set>' } else { "$val" }
                    $row[$p.Name] = $valStr
                    $values.Add($valStr)
                }

                $row['AllMatch'] = ($values | Sort-Object -Unique | Measure-Object).Count -eq 1

                $obj = [PSCustomObject]$row
                $obj.PSObject.TypeNames.Insert(0, 'VMM.PortProfileSettingsMatrix')
                $settingsMatrix.Add($obj)
            }
        }

        # Console display
        $profileNames = @($profiles | ForEach-Object { $_.Name })

        Write-Host "`n=== Port Profile Settings Matrix ===" -ForegroundColor Cyan
        Write-Host "Profiles: $($profileNames -join ', ')" -ForegroundColor White
        Write-Host ("Settings: {0}  |  All identical: {1}  |  Differ: {2}" -f `
                $settingsMatrix.Count,
            ($settingsMatrix | Where-Object AllMatch | Measure-Object).Count,
            ($settingsMatrix | Where-Object { -not $_.AllMatch } | Measure-Object).Count
        )
        Write-Host ''

        # Return structured objects for pipeline
        $settingsMatrix
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'Get-VMMPortProfileUsage'
    'Compare-VMMPortProfile'
    'Compare-VMMPortProfileSettings'
    'Get-VMMPortProfileBindingMatrix'
)

#endregion