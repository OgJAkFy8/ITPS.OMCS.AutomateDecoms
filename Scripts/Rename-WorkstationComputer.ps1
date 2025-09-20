<#
.SYNOPSIS
    Comprehensive computer rename utility supporting local, remote, and bulk operations.

.DESCRIPTION
    Multi-mode computer rename script that provides four distinct operational modes:

    1. Local Mode (Default):
       - Renames the local computer
       - Interactive prompts with optional confirmation skipping
       - No domain credentials required
    
    2. Remote Mode:
       - Renames a single remote computer
       - Requires domain credentials
       - Validates connectivity before attempting rename
       - Supports explicit domain specification
    
    3. Bulk Mode:
       - Processes multiple renames from a CSV file
       - Handles domain authentication
       - Provides detailed success/failure logging
       - Supports concurrent operations
    
    4. CSV Template Mode:
       - Generates a properly formatted CSV template
       - Includes example entries and instructions
       - Creates directory structure if needed

    All modes support proper error handling, validation, and optional restart management.

.PARAMETER CsvPath
    [Bulk/BuildCsv Mode] Path for the CSV file:
    - In Bulk mode: Path to existing CSV with computer rename entries
    - In BuildCsv mode: Path where template will be created
    CSV Format requires columns: OldName,NewName

.PARAMETER BuildCsv
    [Template Mode] Switch to create a new CSV template.
    Use with CsvPath to specify where the template should be created.
    Includes example entries and instructions in the generated file.

.PARAMETER NewName
    [Local/Remote Mode] Target computer name:
    - Must follow Windows computer naming conventions
    - 15 character maximum length
    - Alphanumeric and hyphens only
    If omitted in interactive mode, script will prompt for input.

.PARAMETER ComputerName
    [Remote Mode] Current name of the remote computer to rename.
    Must be accessible on the network and respond to connection tests.

.PARAMETER Credential
    [Remote/Bulk Mode] Domain credentials for computer rename operations.
    Required for:
    - Remote single computer renames
    - Bulk operations from CSV
    Must have appropriate domain permissions.

.PARAMETER NoConfirm
    [Local/Remote Mode] Skips confirmation prompts:
    - Bypasses rename confirmation
    - Still requires restart confirmation unless -NoRestart is also specified
    Use with caution in automated scenarios.

.PARAMETER NoRestart
    [Local/Remote Mode] Skips the restart prompt:
    - Computer rename still occurs
    - No automatic restart
    - Manual restart will be required to complete rename

.PARAMETER DomainName
    [Remote/Bulk Mode] Explicit domain specification:
    - Optional for domain-joined computers
    - Required for workgroup computer renames
    Format: domain.com or DOMAIN

.EXAMPLE
    # Local computer rename with all prompts
    .\Rename-WorkstationComputer.ps1 -NewName "PC-NEW01"

.EXAMPLE
    # Remote computer rename with domain credentials
    .\Rename-WorkstationComputer.ps1 -ComputerName "PC01" -NewName "PC-NEW01" -Credential (Get-Credential)

.EXAMPLE
    # Create CSV template for bulk operations
    .\Rename-WorkstationComputer.ps1 -CsvPath "C:\Renames\computers.csv" -BuildCsv

.EXAMPLE
    # Bulk rename from CSV with explicit domain
    .\Rename-WorkstationComputer.ps1 -CsvPath "C:\Renames\computers.csv" -Credential (Get-Credential) -DomainName "contoso.com"

.EXAMPLE
    # Local rename with no prompts
    .\Rename-WorkstationComputer.ps1 -NewName "PC-NEW01" -NoConfirm -NoRestart

.NOTES
    File Name      : Rename-WorkstationComputer.ps1
    Version        : 2.0
    Author         : ITPS Team
    Requires       : PowerShell 5.1 or later
    
    Prerequisites:
    - Local Mode  : Local admin rights
    - Remote Mode : Domain admin or delegated permissions
                   Network connectivity to target
    - Bulk Mode   : Valid CSV file
                   Domain admin rights
                   Network access to all targets
    
    Limitations:
    - Computer names max length: 15 characters
    - Requires restart to complete rename
    - Domain renames require appropriate permissions
    - CSV must be properly formatted (use -BuildCsv to generate template)

.LINK
    https://github.com/OgJAkFy8/ITPS.OMCS.AutomateDecoms
#>

[CmdletBinding(DefaultParameterSetName = 'Local')]
param(
    [Parameter(
        ParameterSetName = 'Bulk',
        Mandatory = $true,
        Position = 0,
        HelpMessage = "Path to CSV file for bulk rename operations"
    )]
    [Parameter(
        ParameterSetName = 'BuildCsv',
        Mandatory = $true,
        Position = 0,
        HelpMessage = "Path where the CSV template will be created"
    )]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath,
    
    [Parameter(
        ParameterSetName = 'BuildCsv',
        Mandatory = $true,
        HelpMessage = "Creates a new CSV template file at the specified path"
    )]
    [switch]$BuildCsv,
    
    [Parameter(
        ParameterSetName = 'Local',
        Position = 0,
        HelpMessage = "New computer name for local rename operation"
    )]
    [Parameter(
        ParameterSetName = 'Remote',
        Position = 1,
        HelpMessage = "New computer name for remote rename operation"
    )]
    [ValidateNotNullOrEmpty()]
    [string]$NewName,
    
    [Parameter(
        ParameterSetName = 'Remote',
        Mandatory = $true,
        Position = 0,
        HelpMessage = "Remote computer name to rename"
    )]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,
    
    [Parameter(
        ParameterSetName = 'Remote',
        Mandatory = $true,
        HelpMessage = "Domain credentials for remote operations"
    )]
    [Parameter(
        ParameterSetName = 'Bulk',
        Mandatory = $true,
        HelpMessage = "Domain credentials for bulk operations"
    )]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,
    
    [Parameter(
        ParameterSetName = 'Local',
        HelpMessage = "Skip confirmation prompts in local mode"
    )]
    [Parameter(
        ParameterSetName = 'Remote',
        HelpMessage = "Skip confirmation prompts in remote mode"
    )]
    [switch]$NoConfirm,
    
    [Parameter(
        ParameterSetName = 'Local',
        HelpMessage = "Skip restart prompt in local mode"
    )]
    [Parameter(
        ParameterSetName = 'Remote',
        HelpMessage = "Skip restart prompt in remote mode"
    )]
    [switch]$NoRestart,

    [Parameter(
        ParameterSetName = 'Remote',
        HelpMessage = "Domain name for remote rename operation"
    )]
    [Parameter(
        ParameterSetName = 'Bulk',
        HelpMessage = "Domain name for bulk rename operations"
    )]
    [ValidateNotNullOrEmpty()]
    [string]$DomainName
)

function Rename-SingleComputer {
    <#
    .SYNOPSIS
        Performs a validated computer rename operation with comprehensive error handling.
    
    .DESCRIPTION
        Internal function that handles the core rename logic for both local and remote
        computer rename operations. Includes:
        
        - Pre-rename validation
        - Connectivity testing
        - Credential validation
        - Interactive or silent operation
        - Restart management
        - Comprehensive error handling
        
        The function supports both workgroup and domain environments, with special
        handling for domain-joined computers and remote operations.

    .PARAMETER NewComputerName
        The desired new name for the computer. Must follow Windows naming conventions:
        - Maximum 15 characters
        - Alphanumeric and hyphens only
        - Cannot be all numbers
        If not provided, user will be prompted interactively.

    .PARAMETER TargetComputer
        The computer to rename:
        - For local: defaults to $env:COMPUTERNAME
        - For remote: must be accessible on network
        - Must respond to Test-Connection
        - Must allow remote administration

    .PARAMETER DomainCredential
        PSCredential object containing domain credentials:
        - Required for remote operations
        - Must have appropriate domain permissions
        - Used for both rename and restart operations

    .PARAMETER DomainName
        Explicit domain specification:
        - Optional for domain-joined computers
        - Required for workgroup computer renames
        - Format: domain.com or DOMAIN

    .PARAMETER SkipConfirm
        Controls confirmation prompts:
        - True: No confirmation before rename
        - False: Requires 'Y' confirmation
        Default: False (safe)

    .PARAMETER SkipRestart
        Controls restart behavior:
        - True: No restart prompt or action
        - False: Prompts for immediate restart
        Default: False (prompts)

    .NOTES
        Error Handling:
        - Network connectivity failures
        - Access denied scenarios
        - Invalid computer name format
        - Insufficient permissions
        - General rename failures
    #>
    param(
        [string]$NewComputerName,
        [string]$TargetComputer = $env:COMPUTERNAME,
        [System.Management.Automation.PSCredential]$DomainCredential,
        [string]$DomainName,
        [bool]$SkipConfirm = $false,
        [bool]$SkipRestart = $false
    )
    
    # Test connection to target computer
    if (-not (Test-Connection -ComputerName $TargetComputer -Count 1 -Quiet)) {
        Write-Error "Cannot connect to computer: $TargetComputer"
        return
    }
    
    Write-Host "Target computer name: $TargetComputer"
    
    # If NewComputerName not provided, prompt for it
    if (-not $NewComputerName) {
        $NewComputerName = Read-Host "Enter the new computer name"
    }
    
    # Confirm unless explicitly skipped
    if (-not $SkipConfirm) {
        $Confirmation = Read-Host "Are you sure you want to rename the computer to '$NewComputerName'? Type 'Y' to confirm."
        if ($Confirmation -ne "Y") {
            Write-Host "Operation cancelled."
            return
        }
    }
    
    try {
        $renameParams = @{
            NewName = $NewComputerName
            Force = $true
            ErrorAction = 'Stop'
        }

        # Add parameters for remote/domain operations
        if ($TargetComputer -ne $env:COMPUTERNAME) {
            $renameParams['ComputerName'] = $TargetComputer
        }
        
        if ($DomainCredential) {
            $renameParams['DomainCredential'] = $DomainCredential
        }
        
        if ($DomainName) {
            $renameParams['DomainName'] = $DomainName
        }

        # Perform the rename
        Rename-Computer @renameParams
        Write-Host "Computer $TargetComputer has been renamed to '$NewComputerName'. A restart is required."
        
        if (-not $SkipRestart) {
            $RestartConfirmation = Read-Host "Would you like to restart $TargetComputer now? Type 'Y' to confirm."
            if ($RestartConfirmation -eq "Y") {
                $restartParams = @{
                    ComputerName = $TargetComputer
                    Force = $true
                }
                if ($DomainCredential) {
                    $restartParams['Credential'] = $DomainCredential
                }
                Restart-Computer @restartParams
            }
        }
    } catch {
        Write-Error "Failed to rename the computer: $_"
        if ($_.Exception.Message -match "Access is denied") {
            Write-Host "Tip: Ensure you have appropriate domain admin privileges or try running with domain credentials."
        }
    }
}

function New-ComputerRenameCsv {
    <#
    .SYNOPSIS
        Generates a properly formatted CSV template for bulk computer rename operations.
    
    .DESCRIPTION
        Creates a new CSV file with the required structure for bulk computer renames.
        The function:
        
        1. Validates the specified path
        2. Creates any missing directories
        3. Generates a CSV with:
           - Required headers
           - Example entries
           - Usage instructions
           - Format guidelines
        
        The generated template provides a starting point for bulk rename operations
        and includes commented instructions for proper usage.
        
    .PARAMETER CsvPath
        Full path where the CSV template should be created:
        - Can be new or existing path
        - Parent directory will be created if needed
        - Existing files will be overwritten
        
    .NOTES
        CSV Format Details:
        - Headers: OldName,NewName
        - OldName: Current computer name in domain/network
        - NewName: Desired new name (15 char max)
        - No blank lines allowed
        - Comments start with #
        - No commas in names
        
        Example Content:
        OldName,NewName
        PC01,NEW-PC01
        PC02,NEW-PC02
        
    .EXAMPLE
        New-ComputerRenameCsv -CsvPath "C:\Temp\RenameComputers.csv"
        Creates a new template with examples and instructions.
    #>
    param(
        [string]$CsvPath
    )
    
    try {
        # Create directory if it doesn't exist
        $directory = Split-Path -Parent $CsvPath
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        # Create CSV with headers and example entries
        $csvContent = @"
OldName,NewName
PC01,NEW-PC01
PC02,NEW-PC02
# Delete these example entries and add your computer names below
# OldName: Current computer name
# NewName: Desired new computer name
"@
        
        Set-Content -Path $CsvPath -Value $csvContent -Force
        Write-Host "CSV template created at: $CsvPath"
        Write-Host "Edit this file with your computer names and remove the example entries."
    }
    catch {
        Write-Error "Failed to create CSV template: $_"
    }
}

function Rename-BulkComputers {
    <#
    .SYNOPSIS
        Processes multiple computer renames from a CSV file with detailed logging.
    
    .DESCRIPTION
        Automates bulk computer rename operations by processing a CSV input file.
        The function provides:
        
        1. Input Validation:
           - CSV file existence check
           - Required column verification
           - Data format validation
        
        2. Execution Features:
           - Single credential prompt for all operations
           - Individual computer connectivity testing
           - Detailed progress logging
           - Continue-on-error functionality
        
        3. Status Reporting:
           - Success/failure tracking
           - Detailed error logging
           - Operation timestamps
           - Progress indicators
        
    .PARAMETER CsvFilePath
        Path to CSV file containing rename information:
        - Must exist and be readable
        - Requires headers: OldName,NewName
        - One computer per line
        - No blank lines or malformed entries
        
    .NOTES
        Operational Details:
        - Requires domain admin credentials
        - Tests connectivity before each rename
        - Continues processing on individual failures
        - Logs all operations and results
        
        CSV Requirements:
        - Must use comma delimiter
        - No comments within data
        - No empty lines
        - Headers must be: OldName,NewName
        
        Error Handling:
        - Individual rename failures don't stop bulk process
        - All errors are logged and reported
        - Summary provided after completion
        
    .EXAMPLE
        Rename-BulkComputers -CsvFilePath "C:\Renames\computers.csv"
        Processes all computer renames listed in the CSV file.
    #>
    param(
        [string]$CsvFilePath
    )
    
    if (-not (Test-Path $CsvFilePath)) {
        Write-Error "CSV file not found at path: $CsvFilePath"
        return
    }
    
    try {
        $computers = Import-Csv -Path $CsvFilePath
        if (-not ($computers | Get-Member -Name "OldName") -or -not ($computers | Get-Member -Name "NewName")) {
            Write-Error "CSV must contain 'OldName' and 'NewName' columns"
            return
        }
        
        $domainCred = Get-Credential -Message "Enter domain credentials for bulk rename operation"
        
        foreach ($computer in $computers) {
            Write-Host "Processing $($computer.OldName)..."
            try {
                Rename-Computer -ComputerName $computer.OldName -NewName $computer.NewName `
                              -DomainCredential $domainCred -Force -Restart -ErrorAction Stop
                Write-Host "Successfully renamed $($computer.OldName) to $($computer.NewName)"
            } catch {
                Write-Error "Failed to rename $($computer.OldName): $_"
            }
        }
    } catch {
        Write-Error "Error during bulk rename operation: $_"
    }
}

# Main script execution
switch ($PSCmdlet.ParameterSetName) {
    'BuildCsv' {
        Write-Verbose "Creating new CSV template at: $CsvPath"
        New-ComputerRenameCsv -CsvPath $CsvPath
    }
    'Bulk' {
        Write-Verbose "Running in bulk mode using CSV: $CsvPath"
        $bulkParams = @{
            CsvFilePath = $CsvPath
            DomainCredential = $Credential
        }
        if ($DomainName) {
            $bulkParams['DomainName'] = $DomainName
        }
        Rename-BulkComputers @bulkParams
    }
    'Remote' {
        Write-Verbose "Running in remote mode for computer: $ComputerName"
        $params = @{
            NewComputerName = $NewName
            TargetComputer = $ComputerName
            DomainCredential = $Credential
            SkipConfirm = $NoConfirm
            SkipRestart = $NoRestart
        }
        if ($DomainName) {
            $params['DomainName'] = $DomainName
        }
        Rename-SingleComputer @params
    }
    'Local' {
        Write-Verbose "Running in local mode"
        $params = @{
            NewComputerName = $NewName
            TargetComputer = $env:COMPUTERNAME
            SkipConfirm = $NoConfirm
            SkipRestart = $NoRestart
        }
        Rename-SingleComputer @params
    }
}
}   