# Logging-Module.psm1
# Provides a simple logging function for decom scripts
function Write-DecomLog {
    param(
        [string]$Path,
        [string]$Message
    )
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -Path $Path -Value ("[$timestamp] $Message")
}
Export-ModuleMember -Function Write-DecomLog
