$ErrorActionPreference = 'Stop'
$ssisSolution = Join-Path $PSScriptRoot 'DiamondSSISLearning.sln'
$ssisPackage = Join-Path $PSScriptRoot 'Diamond_SSIS_Learning.dtsx'

function Invoke-VisualStudioAction([scriptblock]$Action) {
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try { return & $Action }
        catch [System.Runtime.InteropServices.COMException] {
            if ($_.Exception.HResult -notin @(-2147418111, -2147417846)) { throw }
            Start-Sleep -Seconds 2
        }
    }
    throw 'Visual Studio is busy. Complete any first-launch screen, then open DiamondSSISLearning.sln.'
}

$ssisDte = New-Object -ComObject VisualStudio.DTE.17.0
Invoke-VisualStudioAction { $ssisDte.MainWindow.Visible = $true }
Invoke-VisualStudioAction { $ssisDte.Solution.Open($ssisSolution) }
$ssisProject = Invoke-VisualStudioAction { $ssisDte.Solution.Projects.Item(1) }
$ssisItem = $null
foreach ($item in $ssisProject.ProjectItems) {
    if ($item.Name -eq 'Diamond_SSIS_Learning.dtsx') { $ssisItem = $item; break }
}
if (-not $ssisItem) {
    $ssisItem = Invoke-VisualStudioAction { $ssisProject.ProjectItems.AddFromFile($ssisPackage) }
}
Invoke-VisualStudioAction { $ssisDte.ExecuteCommand('File.SaveAll') }
$ssisWindow = Invoke-VisualStudioAction { $ssisItem.Open('{7651A703-06E5-11D1-8EBD-00A0C90F26EA}') }
Invoke-VisualStudioAction { $ssisWindow.Activate() }
Write-Output "Opened $ssisSolution with package $($ssisItem.Name)."
