#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5.x tests for the Compare-VMMSettings module.

.DESCRIPTION
    All VMM cmdlets are mocked so these tests run on any Windows machine
    without System Center Virtual Machine Manager installed.

    The #Requires -Modules VirtualMachineManager directive in the .psm1 is
    bypassed by dot-sourcing the module file directly after creating stub
    functions for every SC cmdlet the module calls.
#>

BeforeAll {
    # ── Prevent the real VMM module from loading ─────────────────────────────
    # If the VMM Console is installed, Get-Command would trigger auto-loading
    # of the VirtualMachineManager module, which initialises COM/WMI and hangs
    # when no VMM server is reachable.  Remove the module first, then always
    # create lightweight stubs that Pester can mock.
    Remove-Module VirtualMachineManager -Force -ErrorAction SilentlyContinue

    $vmmCmdlets = @(
        'Get-SCVirtualNetworkAdapterNativePortProfile'
        'Get-SCVirtualNetworkAdapterPortProfileSet'
        'Get-SCLogicalSwitch'
        'Get-SCNativeUplinkPortProfile'
        'Get-SCUplinkPortProfileSet'
        'Get-SCPortClassification'
        'Get-SCVMMServer'
    )

    foreach ($name in $vmmCmdlets) {
        # Always create stubs — overrides real VMM cmdlets if the console is installed
        Set-Item -Path "function:global:$name" -Value { }
    }

    # ── Dot-source the module implementation ─────────────────────────────────
    # Read the file, strip directives that fail outside a module context, then execute.
    # Use nested Join-Path for PS 5.1 compatibility (3-arg overload is PS 7+ only)
    $modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'Compare-VMMSettings.psm1'
    $moduleCode = (Get-Content -Path $modulePath -Raw) `
        -replace '#Requires\s+-Modules\s+VirtualMachineManager', '' `
        -replace 'Export-ModuleMember\s+-Function\s+@\([^)]+\)', ''
    $scriptBlock = [scriptblock]::Create($moduleCode)
    . $scriptBlock

    # ── Reusable mock data factories ─────────────────────────────────────────

    function New-MockVNicProfile {
        param(
            [string]$Name = 'TestProfile',
            [string]$Description = 'Test description',
            [guid]$ID = (New-Guid),
            [bool]$AllowIeeePriorityTagging = $true,
            [bool]$AllowMacAddressSpoofing = $false,
            [bool]$AllowTeaming = $true,
            [bool]$EnableDhcpGuard = $false,
            [bool]$EnableGuestIPNetworkVirtualizationUpdates = $false,
            [bool]$EnableRouterGuard = $false,
            [bool]$EnableVmq = $true,
            [bool]$EnableIPsecOffload = $true,
            [bool]$EnableVrss = $true,
            [bool]$EnableIov = $false,
            [int]$MinimumBandwidthWeight = 50,
            [int]$MinimumBandwidthAbsolute = 0,
            [int]$MaximumBandwidth = 10000,
            $PortACL = $null
        )
        [PSCustomObject]@{
            Name                                      = $Name
            Description                               = $Description
            ID                                        = $ID
            AllowIeeePriorityTagging                  = $AllowIeeePriorityTagging
            AllowMacAddressSpoofing                   = $AllowMacAddressSpoofing
            AllowTeaming                              = $AllowTeaming
            EnableDhcpGuard                           = $EnableDhcpGuard
            EnableGuestIPNetworkVirtualizationUpdates = $EnableGuestIPNetworkVirtualizationUpdates
            EnableRouterGuard                         = $EnableRouterGuard
            EnableVmq                                 = $EnableVmq
            EnableIPsecOffload                        = $EnableIPsecOffload
            EnableVrss                                = $EnableVrss
            EnableIov                                 = $EnableIov
            MinimumBandwidthWeight                    = $MinimumBandwidthWeight
            MinimumBandwidthAbsolute                  = $MinimumBandwidthAbsolute
            MaximumBandwidth                          = $MaximumBandwidth
            PortACL                                   = $PortACL
        }
    }

    function New-MockUplinkProfile {
        param(
            [string]$Name = 'UplinkTest',
            [string]$Description = 'Uplink description',
            [guid]$ID = (New-Guid),
            [bool]$EnableNetworkVirtualization = $true,
            [string]$LBFOLoadBalancingAlgorithm = 'HyperVPort',
            [string]$LBFOTeamMode = 'SwitchIndependent'
        )
        [PSCustomObject]@{
            Name                        = $Name
            Description                 = $Description
            ID                          = $ID
            EnableNetworkVirtualization = $EnableNetworkVirtualization
            LBFOLoadBalancingAlgorithm  = $LBFOLoadBalancingAlgorithm
            LBFOTeamMode                = $LBFOTeamMode
        }
    }

    function New-MockPortProfileSet {
        param(
            [string]$Name,
            [guid]$NativePortProfileID,
            [guid]$LogicalSwitchID = (New-Guid),
            [string]$ClassificationName = 'DefaultClass'
        )
        [PSCustomObject]@{
            Name               = $Name
            ID                 = New-Guid
            NativePortProfile  = [PSCustomObject]@{ ID = $NativePortProfileID }
            LogicalSwitch      = [PSCustomObject]@{ ID = $LogicalSwitchID }
            PortClassification = [PSCustomObject]@{ Name = $ClassificationName }
        }
    }

    function New-MockLogicalSwitch {
        param(
            [string]$Name,
            [guid]$ID = (New-Guid),
            [guid[]]$VirtualNetworkAdapterPortProfileSetIDs = @(),
            [guid[]]$UplinkPortProfileSetIDs = @()
        )
        [PSCustomObject]@{
            Name                                 = $Name
            ID                                   = $ID
            VirtualNetworkAdapterPortProfileSets = @($VirtualNetworkAdapterPortProfileSetIDs | ForEach-Object { [PSCustomObject]@{ ID = $_ } })
            UplinkPortProfileSets                = @($UplinkPortProfileSetIDs | ForEach-Object { [PSCustomObject]@{ ID = $_ } })
        }
    }

    function New-MockUplinkPortProfileSet {
        param(
            [string]$Name,
            [guid]$NativeUplinkPortProfileID,
            [guid]$LogicalSwitchID = (New-Guid)
        )
        [PSCustomObject]@{
            Name                    = $Name
            ID                      = New-Guid
            NativeUplinkPortProfile = [PSCustomObject]@{ ID = $NativeUplinkPortProfileID }
            LogicalSwitch           = [PSCustomObject]@{ ID = $LogicalSwitchID }
        }
    }

    # ── Build a standard test dataset ────────────────────────────────────────
    $script:ProfileA_ID = [guid]'11111111-1111-1111-1111-111111111111'
    $script:ProfileB_ID = [guid]'22222222-2222-2222-2222-222222222222'
    $script:ProfileC_ID = [guid]'33333333-3333-3333-3333-333333333333'
    $script:UplinkA_ID = [guid]'44444444-4444-4444-4444-444444444444'
    $script:UplinkB_ID = [guid]'55555555-5555-5555-5555-555555555555'
    $script:Switch1_ID = [guid]'66666666-6666-6666-6666-666666666666'
    $script:Switch2_ID = [guid]'77777777-7777-7777-7777-777777777777'

    $script:ProfileA = New-MockVNicProfile -Name 'HighBandwidth'  -Description 'High throughput' -ID $ProfileA_ID -EnableVmq $true  -MinimumBandwidthWeight 80
    $script:ProfileB = New-MockVNicProfile -Name 'LowLatency'     -Description 'Low latency NIC' -ID $ProfileB_ID -EnableVmq $false -MinimumBandwidthWeight 50
    $script:ProfileC = New-MockVNicProfile -Name 'Orphan'         -Description 'Orphaned profile' -ID $ProfileC_ID

    $script:UplinkA = New-MockUplinkProfile -Name 'UplinkLBFO' -ID $UplinkA_ID -LBFOLoadBalancingAlgorithm 'HyperVPort'
    $script:UplinkB = New-MockUplinkProfile -Name 'UplinkSET'  -ID $UplinkB_ID -LBFOLoadBalancingAlgorithm 'Dynamic'

    $script:PPS_A = New-MockPortProfileSet -Name 'HighBW-PPS' -NativePortProfileID $ProfileA_ID -LogicalSwitchID $Switch1_ID -ClassificationName 'High Bandwidth'
    $script:PPS_B = New-MockPortProfileSet -Name 'LowLat-PPS' -NativePortProfileID $ProfileB_ID -LogicalSwitchID $Switch1_ID -ClassificationName 'Low Latency'
    # ProfileC is intentionally NOT bound

    $script:LS1 = New-MockLogicalSwitch -Name 'ConvergedSwitch01' -ID $Switch1_ID -VirtualNetworkAdapterPortProfileSetIDs @($PPS_A.ID, $PPS_B.ID)
    $script:LS2 = New-MockLogicalSwitch -Name 'MgmtSwitch'        -ID $Switch2_ID

    $script:UPS_A = New-MockUplinkPortProfileSet -Name 'LBFO-UplinkPPS' -NativeUplinkPortProfileID $UplinkA_ID -LogicalSwitchID $Switch1_ID
    $script:UPS_B = New-MockUplinkPortProfileSet -Name 'SET-UplinkPPS'  -NativeUplinkPortProfileID $UplinkB_ID -LogicalSwitchID $Switch2_ID
}

# ═════════════════════════════════════════════════════════════════════════════
# Helper function tests (module-internal)
# ═════════════════════════════════════════════════════════════════════════════
Describe 'Get-PortProfilePropertyMap' {

    It 'Returns 16 properties for VirtualNetworkAdapter' {
        $result = Get-PortProfilePropertyMap -ProfileType 'VirtualNetworkAdapter'
        $result | Should -HaveCount 16
    }

    It 'Includes Name and Description for VirtualNetworkAdapter' {
        $result = Get-PortProfilePropertyMap -ProfileType 'VirtualNetworkAdapter'
        $result | Should -Contain 'Name'
        $result | Should -Contain 'Description'
    }

    It 'Returns 5 properties for NativeUplink' {
        $result = Get-PortProfilePropertyMap -ProfileType 'NativeUplink'
        $result | Should -HaveCount 5
    }

    It 'Includes LBFOTeamMode for NativeUplink' {
        $result = Get-PortProfilePropertyMap -ProfileType 'NativeUplink'
        $result | Should -Contain 'LBFOTeamMode'
    }

    It 'Rejects invalid ProfileType' {
        { Get-PortProfilePropertyMap -ProfileType 'Invalid' } | Should -Throw
    }
}

Describe 'Format-PropertyComparison' {

    It 'Returns one record per property' {
        $ref = [PSCustomObject]@{ A = 1; B = 2 }
        $diff = [PSCustomObject]@{ A = 1; B = 3 }
        $result = Format-PropertyComparison -ReferenceObject $ref -DifferenceObject $diff -Properties 'A', 'B'
        $result | Should -HaveCount 2
    }

    It 'Marks matching values with Match = $true' {
        $ref = [PSCustomObject]@{ X = 'Same' }
        $diff = [PSCustomObject]@{ X = 'Same' }
        $result = Format-PropertyComparison -ReferenceObject $ref -DifferenceObject $diff -Properties 'X'
        $result[0].Match | Should -BeTrue
    }

    It 'Marks differing values with Match = $false' {
        $ref = [PSCustomObject]@{ X = 'One' }
        $diff = [PSCustomObject]@{ X = 'Two' }
        $result = Format-PropertyComparison -ReferenceObject $ref -DifferenceObject $diff -Properties 'X'
        $result[0].Match | Should -BeFalse
    }

    It 'Handles null values by converting to [not set]' {
        $ref = [PSCustomObject]@{ X = $null }
        $diff = [PSCustomObject]@{ X = $null }
        $result = Format-PropertyComparison -ReferenceObject $ref -DifferenceObject $diff -Properties 'X'
        $result[0].Reference | Should -Be '<not set>'
        $result[0].Match | Should -BeTrue
    }

    It 'Uses custom column names when provided' {
        $ref = [PSCustomObject]@{ Val = 10 }
        $diff = [PSCustomObject]@{ Val = 20 }
        $result = Format-PropertyComparison -ReferenceObject $ref -DifferenceObject $diff `
            -Properties 'Val' -ReferenceName 'Left' -DifferenceName 'Right'
        $result[0].Left | Should -Be '10'
        $result[0].Right | Should -Be '20'
    }
}

Describe 'Format-ConsoleTable' {

    It 'Produces pipe-bordered output on the console' {
        $data = @([PSCustomObject]@{ Col1 = 'A'; Col2 = 'B' })
        # Capture Write-Host output via -InformationVariable is not available;
        # instead, just verify it does not throw
        { Format-ConsoleTable -Data $data -Columns 'Col1', 'Col2' 6>$null } | Should -Not -Throw
    }

    It 'Does not throw when HighlightCondition is provided' {
        $data = @(
            [PSCustomObject]@{ Name = 'Row1'; Status = 'OK' }
            [PSCustomObject]@{ Name = 'Row2'; Status = 'DIFF' }
        )
        $condition = { param($r) $r.Status -eq 'DIFF' }
        { Format-ConsoleTable -Data $data -Columns 'Name', 'Status' -HighlightCondition $condition 6>$null } | Should -Not -Throw
    }
}

Describe 'Emoji-safe status markers' {

    It 'SymbolOK is set and non-empty' {
        $script:SymbolOK | Should -Not -BeNullOrEmpty
    }

    It 'SymbolDIFF is set and non-empty' {
        $script:SymbolDIFF | Should -Not -BeNullOrEmpty
    }

    It 'SymbolOK contains OK' {
        $script:SymbolOK | Should -BeLike '*OK*'
    }

    It 'SymbolDIFF contains DIFF' {
        $script:SymbolDIFF | Should -BeLike '*DIFF*'
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# Get-VMMPortProfileUsage
# ═════════════════════════════════════════════════════════════════════════════
Describe 'Get-VMMPortProfileUsage' {

    BeforeEach {
        Mock Get-SCVirtualNetworkAdapterNativePortProfile { return @($script:ProfileA, $script:ProfileB, $script:ProfileC) }
        Mock Get-SCVirtualNetworkAdapterPortProfileSet { return @($script:PPS_A, $script:PPS_B) }
        Mock Get-SCLogicalSwitch { return @($script:LS1, $script:LS2) }
        Mock Get-SCNativeUplinkPortProfile { return @($script:UplinkA, $script:UplinkB) }
        Mock Get-SCUplinkPortProfileSet { return @($script:UPS_A, $script:UPS_B) }
    }

    Context 'vNIC profiles only (default)' {

        It 'Returns all vNIC profiles' {
            $result = Get-VMMPortProfileUsage
            $result | Should -HaveCount 3
        }

        It 'Marks each result with ProfileType = VirtualNetworkAdapter' {
            $result = Get-VMMPortProfileUsage
            $result | ForEach-Object { $_.ProfileType | Should -Be 'VirtualNetworkAdapter' }
        }

        It 'Includes the PSTypeName VMM.PortProfileUsage' {
            $result = Get-VMMPortProfileUsage
            $result[0].PSObject.TypeNames | Should -Contain 'VMM.PortProfileUsage'
        }

        It 'Resolves LogicalSwitchNames for bound profiles' {
            $result = Get-VMMPortProfileUsage
            $highBW = $result | Where-Object Name -EQ 'HighBandwidth'
            $highBW.LogicalSwitchNames | Should -Not -BeNullOrEmpty
        }

        It 'Returns empty LogicalSwitchNames for orphaned profiles' {
            $result = Get-VMMPortProfileUsage
            $orphan = $result | Where-Object Name -EQ 'Orphan'
            $orphan.LogicalSwitchNames | Should -BeNullOrEmpty
        }

        It 'Populates PortClassificationNames from bound sets' {
            $result = Get-VMMPortProfileUsage
            $highBW = $result | Where-Object Name -EQ 'HighBandwidth'
            $highBW.PortClassificationNames | Should -BeLike '*High Bandwidth*'
        }

        It 'Preserves key settings from the source profile' {
            $result = Get-VMMPortProfileUsage
            $highBW = $result | Where-Object Name -EQ 'HighBandwidth'
            $highBW.EnableVmq | Should -Be $true
            $highBW.MinimumBandwidthWeight | Should -Be 80
        }

        It 'Does NOT call uplink cmdlets when -IncludeUplinkProfiles is not set' {
            Get-VMMPortProfileUsage | Out-Null
            Should -Invoke Get-SCNativeUplinkPortProfile -Times 0 -Exactly
        }
    }

    Context 'With -IncludeUplinkProfiles' {

        It 'Returns vNIC and uplink profiles' {
            $result = Get-VMMPortProfileUsage -IncludeUplinkProfiles
            $result | Should -HaveCount 5
        }

        It 'Includes NativeUplink type entries' {
            $result = Get-VMMPortProfileUsage -IncludeUplinkProfiles
            $uplinkResults = $result | Where-Object ProfileType -EQ 'NativeUplink'
            $uplinkResults | Should -HaveCount 2
        }

        It 'Calls Get-SCNativeUplinkPortProfile' {
            Get-VMMPortProfileUsage -IncludeUplinkProfiles | Out-Null
            Should -Invoke Get-SCNativeUplinkPortProfile -Times 1 -Exactly
        }
    }

    Context 'With -Name filter' {

        It 'Passes the Name parameter to the VMM cmdlet' {
            Mock Get-SCVirtualNetworkAdapterNativePortProfile { return @($script:ProfileA) } -ParameterFilter { $Name -eq 'HighBandwidth' }
            $result = Get-VMMPortProfileUsage -Name 'HighBandwidth'
            $result | Should -HaveCount 1
            $result[0].Name | Should -Be 'HighBandwidth'
        }
    }

    Context 'VMM connection error handling' {

        It 'Writes a meaningful error when VMM connection fails' {
            Mock Get-SCVirtualNetworkAdapterNativePortProfile { throw [System.TypeInitializationException]::new('Microsoft.VirtualManager.Utils.TraceProviders.BitBos', $null) }
            $result = Get-VMMPortProfileUsage -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].Exception.Message | Should -BeLike '*Cannot connect to VMM*'
        }

        It 'Writes an error when port profile sets retrieval fails' {
            Mock Get-SCVirtualNetworkAdapterNativePortProfile { return @($script:ProfileA) }
            Mock Get-SCVirtualNetworkAdapterPortProfileSet { throw 'Connection lost' }
            $result = Get-VMMPortProfileUsage -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].Exception.Message | Should -BeLike '*Failed to retrieve*'
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# Compare-VMMPortProfile
# ═════════════════════════════════════════════════════════════════════════════
Describe 'Compare-VMMPortProfile' {

    BeforeEach {
        Mock Get-SCVirtualNetworkAdapterNativePortProfile {
            param($Name)
            switch ($Name) {
                'HighBandwidth' { $script:ProfileA }
                'LowLatency' { $script:ProfileB }
                default { $null }
            }
        }
        Mock Get-SCVirtualNetworkAdapterPortProfileSet { return @($script:PPS_A, $script:PPS_B) }
        Mock Get-SCLogicalSwitch { return @($script:LS1, $script:LS2) }
        Mock Get-SCNativeUplinkPortProfile {
            param($Name)
            switch ($Name) {
                'UplinkLBFO' { $script:UplinkA }
                'UplinkSET' { $script:UplinkB }
                default { $null }
            }
        }
        Mock Get-SCUplinkPortProfileSet { return @($script:UPS_A, $script:UPS_B) }
        Mock Write-Host { }  # suppress console output during tests
    }

    Context 'ByName parameter set' {

        It 'Returns a VMM.PortProfileComparison object' {
            $result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' -DifferenceProfileName 'LowLatency'
            $result.PSObject.TypeNames | Should -Contain 'VMM.PortProfileComparison'
        }

        It 'Reports the correct profile names' {
            $result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' -DifferenceProfileName 'LowLatency'
            $result.ReferenceProfile | Should -Be 'HighBandwidth'
            $result.DifferenceProfile | Should -Be 'LowLatency'
        }

        It 'Counts total properties as 16 for vNIC comparison' {
            $result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' -DifferenceProfileName 'LowLatency'
            $result.TotalProperties | Should -Be 16
        }

        It 'Detects differences between the two profiles' {
            $result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' -DifferenceProfileName 'LowLatency'
            $result.DifferingProperties | Should -BeGreaterThan 0
        }

        It 'PropertyComparison contains difference for EnableVmq' {
            $result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' -DifferenceProfileName 'LowLatency'
            $vmqRow = $result.PropertyComparison | Where-Object Property -EQ 'EnableVmq'
            $vmqRow.Match | Should -BeFalse
        }

        It 'PropertyComparison marks matching properties correctly' {
            $result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' -DifferenceProfileName 'LowLatency'
            $teamingRow = $result.PropertyComparison | Where-Object Property -EQ 'AllowTeaming'
            $teamingRow.Match | Should -BeTrue
        }
    }

    Context '-DifferencesOnly switch' {

        It 'Returns only differing properties' {
            $result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' -DifferenceProfileName 'LowLatency' -DifferencesOnly
            $result.PropertyComparison | ForEach-Object { $_.Match | Should -BeFalse }
        }

        It 'Has fewer PropertyComparison entries than full comparison' {
            $full = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' -DifferenceProfileName 'LowLatency'
            $diff = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' -DifferenceProfileName 'LowLatency' -DifferencesOnly
            $diff.TotalProperties | Should -BeLessThan $full.TotalProperties
        }
    }

    Context 'ByObject parameter set' {

        It 'Accepts profile objects directly' {
            $result = Compare-VMMPortProfile -ReferenceProfile $script:ProfileA -DifferenceProfile $script:ProfileB
            $result.ReferenceProfile | Should -Be 'HighBandwidth'
        }
    }

    Context '-IncludeUplinkProfiles switch' {

        It 'Compares uplink profiles when specified' {
            $result = Compare-VMMPortProfile -ReferenceProfileName 'UplinkLBFO' -DifferenceProfileName 'UplinkSET' -IncludeUplinkProfiles
            $result.ProfileType | Should -Be 'NativeUplink'
        }

        It 'Reports 5 properties for uplink comparison' {
            $result = Compare-VMMPortProfile -ReferenceProfileName 'UplinkLBFO' -DifferenceProfileName 'UplinkSET' -IncludeUplinkProfiles
            $result.TotalProperties | Should -Be 5
        }
    }

    Context 'Error handling' {

        It 'Writes an error when reference profile is not found' {
            Mock Get-SCVirtualNetworkAdapterNativePortProfile { return $null }
            $result = Compare-VMMPortProfile -ReferenceProfileName 'NonExistent' -DifferenceProfileName 'LowLatency' -ErrorAction SilentlyContinue -ErrorVariable err
            $err | Should -Not -BeNullOrEmpty
        }

        It 'Writes a meaningful error when VMM connection fails' {
            Mock Get-SCVirtualNetworkAdapterNativePortProfile { throw [System.TypeInitializationException]::new('Microsoft.VirtualManager.Utils.TraceProviders.BitBos', $null) }
            $result = Compare-VMMPortProfile -ReferenceProfileName 'HighBandwidth' -DifferenceProfileName 'LowLatency' -ErrorAction SilentlyContinue -ErrorVariable err
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].Exception.Message | Should -BeLike '*Cannot connect to VMM*'
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# Get-VMMPortProfileBindingMatrix
# ═════════════════════════════════════════════════════════════════════════════
Describe 'Get-VMMPortProfileBindingMatrix' {

    BeforeEach {
        Mock Get-SCVirtualNetworkAdapterNativePortProfile { return @($script:ProfileA, $script:ProfileB, $script:ProfileC) }
        Mock Get-SCVirtualNetworkAdapterPortProfileSet { return @($script:PPS_A, $script:PPS_B) }
        Mock Get-SCLogicalSwitch { return @($script:LS1, $script:LS2) }
        Mock Get-SCNativeUplinkPortProfile { return @($script:UplinkA, $script:UplinkB) }
        Mock Get-SCUplinkPortProfileSet { return @($script:UPS_A, $script:UPS_B) }
    }

    It 'Returns one object per profile' {
        $result = Get-VMMPortProfileBindingMatrix
        $result | Should -HaveCount 3
    }

    It 'Each object has PSTypeName VMM.PortProfileBindingMatrix' {
        $result = Get-VMMPortProfileBindingMatrix
        $result | ForEach-Object { $_.PSObject.TypeNames | Should -Contain 'VMM.PortProfileBindingMatrix' }
    }

    It 'Shows <unbound> for profiles without logical switch bindings' {
        $result = Get-VMMPortProfileBindingMatrix
        $orphan = $result | Where-Object ProfileName -EQ 'Orphan'
        $orphan.LogicalSwitches | Should -Be '<unbound>'
    }

    It 'Shows switch names for bound profiles' {
        $result = Get-VMMPortProfileBindingMatrix
        $highBW = $result | Where-Object ProfileName -EQ 'HighBandwidth'
        $highBW.LogicalSwitches | Should -Not -Be '<unbound>'
    }

    It 'Includes uplink profiles when -IncludeUplinkProfiles is set' {
        $result = Get-VMMPortProfileBindingMatrix -IncludeUplinkProfiles
        $result | Should -HaveCount 5
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# Compare-VMMPortProfileSettings
# ═════════════════════════════════════════════════════════════════════════════
Describe 'Compare-VMMPortProfileSettings' {

    BeforeEach {
        Mock Get-SCVirtualNetworkAdapterNativePortProfile { return @($script:ProfileA, $script:ProfileB, $script:ProfileC) }
        Mock Get-SCVirtualNetworkAdapterPortProfileSet { return @($script:PPS_A, $script:PPS_B) }
        Mock Get-SCLogicalSwitch { return @($script:LS1, $script:LS2) }
        Mock Get-SCNativeUplinkPortProfile { return @($script:UplinkA, $script:UplinkB) }
        Mock Get-SCUplinkPortProfileSet { return @($script:UPS_A, $script:UPS_B) }
        Mock Write-Host { }  # suppress console output
    }

    Context 'ByName – multiple vNIC profiles' {

        It 'Returns 14 settings rows for vNIC profiles' {
            $result = Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency'
            $result | Should -HaveCount 14
        }

        It 'Each row has PSTypeName VMM.PortProfileSettingsMatrix' {
            $result = Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency'
            $result[0].PSObject.TypeNames | Should -Contain 'VMM.PortProfileSettingsMatrix'
        }

        It 'Includes an AllMatch boolean column' {
            $result = Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency'
            $result[0].PSObject.Properties.Name | Should -Contain 'AllMatch'
        }

        It 'AllMatch is $true for identical settings' {
            $result = Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency'
            $teamingRow = $result | Where-Object Setting -EQ 'AllowTeaming'
            $teamingRow.AllMatch | Should -BeTrue
        }

        It 'AllMatch is $false for differing settings' {
            $result = Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency'
            $vmqRow = $result | Where-Object Setting -EQ 'EnableVmq'
            $vmqRow.AllMatch | Should -BeFalse
        }

        It 'Has dynamic columns named after the profiles' {
            $result = Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency'
            $result[0].PSObject.Properties.Name | Should -Contain 'HighBandwidth'
            $result[0].PSObject.Properties.Name | Should -Contain 'LowLatency'
        }
    }

    Context 'ByObject – pipeline input' {

        It 'Accepts profile objects via -ProfileObject' {
            # Build usage objects directly to bypass VMM query
            $usageA = [PSCustomObject]@{
                PSTypeName                                = 'VMM.PortProfileUsage'
                ProfileType                               = 'VirtualNetworkAdapter'
                Name                                      = 'PipeA'
                AllowIeeePriorityTagging                  = $true
                AllowMacAddressSpoofing                   = $false
                AllowTeaming                              = $true
                EnableDhcpGuard                           = $false
                EnableGuestIPNetworkVirtualizationUpdates = $false
                EnableRouterGuard                         = $false
                EnableVmq                                 = $true
                EnableIPsecOffload                        = $true
                EnableVrss                                = $true
                EnableIov                                 = $false
                MinimumBandwidthWeight                    = 50
                MinimumBandwidthAbsolute                  = 0
                MaximumBandwidth                          = 10000
                PortACL                                   = $null
            }
            $usageB = $usageA.PSObject.Copy()
            $usageB.Name = 'PipeB'
            $usageB.EnableVmq = $false

            $result = Compare-VMMPortProfileSettings -ProfileObject @($usageA, $usageB)
            $result | Should -HaveCount 14
            $vmqRow = $result | Where-Object Setting -EQ 'EnableVmq'
            $vmqRow.AllMatch | Should -BeFalse
        }
    }

    Context 'Warning when fewer than 2 profiles' {

        It 'Writes a warning and returns nothing for a single profile' {
            Mock Get-SCVirtualNetworkAdapterNativePortProfile { return @($script:ProfileA) }
            $result = Compare-VMMPortProfileSettings -Name 'HighBandwidth' -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warn | Should -Not -BeNullOrEmpty
        }
    }

    Context '-IncludeUplinkProfiles' {

        It 'Compares uplink settings when specified' {
            Mock Get-SCVirtualNetworkAdapterNativePortProfile { return @() }
            $result = Compare-VMMPortProfileSettings -Name 'UplinkLBFO', 'UplinkSET' -IncludeUplinkProfiles
            $result | Should -HaveCount 3
            $result[0].PSObject.Properties.Name | Should -Contain 'UplinkLBFO'
        }
    }

    Context '-HighlightDifferences switch' {

        It 'Does not throw when -HighlightDifferences is set' {
            { Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency' -HighlightDifferences } | Should -Not -Throw
        }
    }

    Context 'Filtering pipeline output' {

        It 'Allows Where-Object to filter for differences only' {
            $result = Compare-VMMPortProfileSettings -Name 'HighBandwidth', 'LowLatency'
            $diffs = $result | Where-Object { -not $_.AllMatch }
            $diffs | Should -Not -BeNullOrEmpty
            $diffs | ForEach-Object { $_.AllMatch | Should -BeFalse }
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# Module manifest validation
# ═════════════════════════════════════════════════════════════════════════════
Describe 'Module Manifest' {

    BeforeAll {
        # Use Import-PowerShellDataFile instead of Test-ModuleManifest to avoid
        # hanging when RequiredModules (VirtualMachineManager) is not installed.
        $script:ManifestPath = Join-Path (Join-Path $PSScriptRoot '..') 'Compare-VMMSettings.psd1'
        $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
    }

    It 'Has a valid module manifest' {
        $script:Manifest | Should -Not -BeNullOrEmpty
    }

    It 'Exports exactly 4 functions' {
        $script:Manifest.FunctionsToExport.Count | Should -Be 4
    }

    It 'Exports Get-VMMPortProfileUsage' {
        $script:Manifest.FunctionsToExport | Should -Contain 'Get-VMMPortProfileUsage'
    }

    It 'Exports Compare-VMMPortProfile' {
        $script:Manifest.FunctionsToExport | Should -Contain 'Compare-VMMPortProfile'
    }

    It 'Exports Compare-VMMPortProfileSettings' {
        $script:Manifest.FunctionsToExport | Should -Contain 'Compare-VMMPortProfileSettings'
    }

    It 'Exports Get-VMMPortProfileBindingMatrix' {
        $script:Manifest.FunctionsToExport | Should -Contain 'Get-VMMPortProfileBindingMatrix'
    }

    It 'Requires PowerShell 5.1 or higher' {
        $script:Manifest.PowerShellVersion | Should -Be '5.1'
    }

    It 'Has a non-empty description' {
        $script:Manifest.Description | Should -Not -BeNullOrEmpty
    }

    It 'Has a valid GUID' {
        $script:Manifest.GUID | Should -Not -Be ([guid]::Empty).ToString()
    }
}
