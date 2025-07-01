# DNS-Module.psm1
# Provides reusable DNS lookup/check functions for decom scripts
function Get-DNSStatus {
    param([string]$FQDN)
    try {
        $dnsResult = Resolve-DnsName -Name $FQDN -ErrorAction Stop | Where-Object { $_.QueryType -eq 'A' } | Select-Object -ExpandProperty IPAddress
        return $dnsResult
    } catch {
        return 'Not in DNS'
    }
}
Export-ModuleMember -Function Get-DNSStatus
