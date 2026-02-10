@{

    # Script module associated with this manifest
    RootModule        = 'Compare-VMMSettings.psm1'

    # Version number of this module
    ModuleVersion     = '1.4.0'

    # Unique identifier for this module
    GUID              = 'a3f7c8e1-4b2d-4e9a-b6f0-1d2e3f4a5b6c'

    # Author of this module
    Author            = 'Jan Tiedemann'

    # Company or vendor of this module
    CompanyName       = ''

    # Copyright statement
    Copyright         = '(c) 2026 Jan Tiedemann. This project is licensed under the MIT License.
'

    # Description of the functionality provided by this module
    Description       = @'
Compare and report on VMM (System Center Virtual Machine Manager) Port Profile
settings and their bindings across the fabric. Helps identify where port profiles
are used, which logical switches reference them, and how two profiles differ.

By default only virtual network adapter (vNIC) port profiles are processed.
Use the -IncludeUplinkProfiles switch on any function to also include native
uplink port profiles.
'@

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @('VirtualMachineManager')

    # Functions to export from this module — only public functions are listed
    FunctionsToExport = @(
        'Get-VMMPortProfileUsage'
        'Compare-VMMPortProfile'
        'Compare-VMMPortProfileSettings'
        'Get-VMMPortProfileBindingMatrix'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    # Private data passed to the module specified in RootModule
    PrivateData       = @{

        PSData = @{

            # Tags applied to this module to aid in module discovery
            Tags         = @('VMM', 'SCVMM', 'Hyper-V', 'PortProfile', 'NetworkProfile', 'Comparison')

            # A URL to the license for this module
            LicenseUri   = ''

            # A URL to the main website for this project
            ProjectUri   = ''

            # Release notes for this module
            ReleaseNotes = @'
## 1.2.0 (2026-02-09)
- Console output now renders proper pipe-bordered ASCII tables
- Added emoji-safe status markers: Unicode on PS 7.x, ASCII fallback on PS 5.1
- Added Format-ConsoleTable private helper for consistent table rendering

## 1.1.0 (2026-02-09)
- Added Compare-VMMPortProfileSettings: Multi-profile key-settings matrix comparison
- Added -HighlightDifferences switch for console-highlighted drift detection
- Supports pipeline input from Get-VMMPortProfileUsage

## 1.0.0 (2026-02-09)
- Initial release
- Get-VMMPortProfileUsage: Retrieve port profiles with binding information
- Compare-VMMPortProfile: Side-by-side comparison of two port profiles
- Get-VMMPortProfileBindingMatrix: Cross-reference matrix of profiles to logical switches
- Uplink profiles excluded by default; opt-in via -IncludeUplinkProfiles
'@

        }

    }

}
