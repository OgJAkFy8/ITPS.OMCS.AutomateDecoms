# AD-Module.psm1
# Provides reusable Active Directory lookup/check functions for decom scripts
function Get-ADComputerStatus {
    param([string]$ComputerName)
    try {
        $adObject = Get-ADComputer -Identity $ComputerName -ErrorAction Stop
        return $adObject.DistinguishedName
    } catch {
        return 'Not found in AD'
    }
}
Export-ModuleMember -Function Get-ADComputerStatus
