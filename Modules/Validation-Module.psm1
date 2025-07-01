# Validation-Module.psm1
# Provides reusable validation functions for decom scripts
function Test-VMInFolder {
    param(
        [object]$VM,
        [string]$ExpectedFolder
    )
    $folderPath = $VM.Folder.Name
    $folder = $VM.Folder
    while ($folder.Parent -and $folder.Parent -ne $folder) {
        $folder = $folder.Parent
        $folderPath = ("{0}/{1}" -f $folder.Name, $folderPath)
    }
    return $folderPath -like "*$ExpectedFolder*"
}
Export-ModuleMember -Function Test-VMInFolder
