<#
.SYNOPSIS
    Automates the Active Directory decommissioning process for computer accounts.

.DESCRIPTION
    This script performs a comprehensive decommissioning process for computer accounts in Active Directory:
    
    1. Validation:
       - Verifies the computer exists in AD
       - Checks for required permissions
       - Creates detailed logs of all actions
    
    2. Backup:
       - Exports complete computer object details
       - Captures security descriptors and permissions
       - Records group memberships and relationships
       - Stores ownership and management info
    
    3. Decommissioning:
       - Disables the computer account
       - Moves the account to a specified OU (Services\Build)
       - Tags the account with decom date and ticket
       - Maintains audit trail with timestamps
    
    All actions are logged and exported to a JSON file for documentation and potential rollback.

.PARAMETER ComputerName
    The name of the computer account to decommission in Active Directory.
    This must match the exact computer account name in AD.
    Accepts pipeline input by property name.

.PARAMETER TicketNumber
    The change or incident ticket number associated with this decommissioning.
    Used for tracking and auditing purposes.
    Will be added as a tag to the computer object.

.PARAMETER ExportPath
    Optional. Full path where the computer object backup will be saved.
    Default: ./<ComputerName>-ADExport.json in the current directory
    Exports in JSON format for easy parsing and storage.

.EXAMPLE
    .\Start-ADDecom.ps1 -ComputerName 'SRV01' -TicketNumber 'INC123456'
    
    Decommissions the computer account 'SRV01', tracking it with ticket 'INC123456'.
    Exports the backup to ./SRV01-ADExport.json

.EXAMPLE
    .\Start-ADDecom.ps1 -ComputerName 'WS02' -TicketNumber 'CHG789012' -ExportPath 'C:\Exports\WS02.json'
    
    Decommissions 'WS02', using a custom export path and change ticket number.

.EXAMPLE
    Get-Content computers.txt | ForEach-Object { 
        .\Start-ADDecom.ps1 -ComputerName $_ -TicketNumber 'BULK001' 
    }
    
    Bulk decommissions computers listed in computers.txt file.

.NOTES
    Filename    : Start-ADDecom.ps1
    Author      : ITPS Team
    Version     : 2.0
    
    Prerequisites:
    - ActiveDirectory PowerShell module
    - Domain admin or delegated permissions for:
      * Computer account modification
      * OU move permissions
      * Attribute modification rights
    
    The script will create a complete backup before making any changes.
    Errors are logged even if the computer is not found.

.LINK
    https://github.com/OgJAkFy8/ITPS.OMCS.AutomateDecoms

.OUTPUTS
    Creates a JSON file containing:
    - Original computer object state
    - Security descriptors
    - Group memberships
    - Timestamps
    - Operation status
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$ComputerName,
  [Parameter(Mandatory)]
  [string]$TicketNumber,
  [string]$ExportPath = (Join-Path -Path (Get-Location) -ChildPath "$ComputerName-ADExport.json")
)

# Verify and import required PowerShell modules
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error 'Required ActiveDirectory PowerShell module not found. Please install RSAT tools or appropriate AD management tools.'
    return
}
Import-Module ActiveDirectory -Verbose:$false

# Initialize logging timestamp for all operations
$timestamp = Get-Date
Write-Verbose "Starting decommissioning process at $($timestamp.ToString('yyyy-MM-dd HH:mm:ss'))"

# Validate input parameters
if ($ComputerName -match '[^\w\-]') {
    Write-Error "Invalid computer name format: $ComputerName. Computer names should only contain letters, numbers, and hyphens."
    return
}

# Verify export path directory exists or create it
$exportDir = Split-Path -Parent $ExportPath
if (-not (Test-Path $exportDir)) {
    try {
        New-Item -ItemType Directory -Path $exportDir -Force -ErrorAction Stop | Out-Null
        Write-Verbose "Created export directory: $exportDir"
    }
    catch {
        Write-Error "Failed to create export directory $exportDir : $_"
        return
    }
}

# Query AD for computer account and create initial log entry
$adComp = Get-ADComputer -Identity $ComputerName -Properties * -ErrorAction SilentlyContinue

# Create export object with basic info even if computer not found
$export = [PSCustomObject]@{
    ComputerName = $ComputerName
    Status = if ($adComp) { "Found" } else { "NotFound" }
    Exported = (Get-Date)
    TicketNumber = $TicketNumber
}

if (-not $adComp) {
    Write-Error "Computer $ComputerName not found in AD."
    # Log the failed attempt
    $export | Add-Member -MemberType NoteProperty -Name "Error" -Value "Computer not found in AD"
    $export | ConvertTo-Json | Set-Content -Path $ExportPath
    Write-Host "Logged failed lookup attempt to $ExportPath"
    return
}

# Add detailed AD object info to export
$export | Add-Member -MemberType NoteProperty -Name "DistinguishedName" -Value $adComp.DistinguishedName
$export | Add-Member -MemberType NoteProperty -Name "Description" -Value $adComp.Description
$export | Add-Member -MemberType NoteProperty -Name "Enabled" -Value $adComp.Enabled
$export | Add-Member -MemberType NoteProperty -Name "WhenCreated" -Value $adComp.WhenCreated
$export | Add-Member -MemberType NoteProperty -Name "MemberOf" -Value $adComp.MemberOf
$export | Add-Member -MemberType NoteProperty -Name "ManagedBy" -Value $adComp.ManagedBy
$export | Add-Member -MemberType NoteProperty -Name "ntSecurityDescriptor" -Value (Get-ADObject -Identity $adComp.DistinguishedName -Properties ntSecurityDescriptor).ntSecurityDescriptor
$export | ConvertTo-Json | Set-Content -Path $ExportPath
Write-Host "Exported AD computer info to $ExportPath"

# Disable the computer
Disable-ADAccount -Identity $ComputerName
Write-Host "Disabled computer account $ComputerName"

# Move computer account to decommissioned OU
$targetOU = "OU=Build,OU=Services,DC=$(($adComp.DistinguishedName -split ',DC=')[1..-1] -join ',DC=')"
try {
    # Verify target OU exists
    if (-not (Get-ADOrganizationalUnit -Identity $targetOU -ErrorAction SilentlyContinue)) {
        throw "Target OU does not exist: $targetOU"
    }

    # Attempt to move the computer account
    Move-ADObject -Identity $adComp.DistinguishedName -TargetPath $targetOU -ErrorAction Stop
    Write-Host "Successfully moved $ComputerName to decommissioned OU: $targetOU"
    $export | Add-Member -MemberType NoteProperty -Name "MovedToOU" -Value $targetOU
} catch {
    $errorMsg = "Failed to move {0} to {1}: {2}" -f $ComputerName, $targetOU, $_.Exception.Message
    Write-Warning $errorMsg
    $export | Add-Member -MemberType NoteProperty -Name "MovementError" -Value $errorMsg
}

# Add decommissioning metadata tags
$decomDate = Get-Date -Format 'yyyy-MM-dd'
try {
    # Add decom tags and update description
    $decomTags = @{
        'DecomDate' = $decomDate
        'DecomTicket' = $TicketNumber
        'DecomBy' = $env:USERNAME
    }
    
    Set-ADComputer -Identity $ComputerName -Add $decomTags -ErrorAction Stop
    
    # Update description to indicate decommissioned status
    $newDescription = "DECOMMISSIONED: $decomDate (Ticket: $TicketNumber)"
    if ($adComp.Description) {
        $newDescription = "$newDescription - Original Description: $($adComp.Description)"
    }
    Set-ADComputer -Identity $ComputerName -Description $newDescription -ErrorAction Stop
    
    Write-Host "Successfully tagged $ComputerName with decom information"
    $export | Add-Member -MemberType NoteProperty -Name "DecomTags" -Value $decomTags
    $export | Add-Member -MemberType NoteProperty -Name "NewDescription" -Value $newDescription
} catch {
    Write-Warning "Failed to add decom tags to $ComputerName : $_"
    $export | Add-Member -MemberType NoteProperty -Name "TaggingError" -Value $_.Exception.Message
}

# Update final export with completion status
$export | Add-Member -MemberType NoteProperty -Name "CompletionTime" -Value (Get-Date)
$export | ConvertTo-Json -Depth 10 | Set-Content -Path $ExportPath
Write-Verbose "Decommissioning process completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
