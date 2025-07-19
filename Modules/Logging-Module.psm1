# Logging-Module.psm1
# Provides a simple logging function for decom scripts and server lifecycle events
function Write-ServerLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName,
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$LogFolder = "$((Split-Path (Get-Location) -Parent)\OutputFolder\ServerLogs)"
    )
    if (-not (Test-Path $LogFolder)) {
        $null = New-Item -Path $LogFolder -ItemType Directory
    }
    $logPath = Join-Path -Path $LogFolder -ChildPath ("$ServerName.log")
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -Path $logPath -Value ("[$timestamp] $Message")
}
Export-ModuleMember -Function Write-ServerLog
