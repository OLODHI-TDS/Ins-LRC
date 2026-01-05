# Extract VBA code from Excel file
param(
    [Parameter(Mandatory=$true)]
    [string]$ExcelPath
)

if (-not (Test-Path $ExcelPath)) {
    Write-Error "File not found: $ExcelPath"
    exit 1
}

$excel = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    $workbook = $excel.Workbooks.Open($ExcelPath)

    Write-Host "=== VBA Project Components ===" -ForegroundColor Cyan

    $vbProject = $workbook.VBProject

    foreach ($component in $vbProject.VBComponents) {
        $name = $component.Name
        $type = switch ($component.Type) {
            1 { "Standard Module" }
            2 { "Class Module" }
            3 { "UserForm" }
            100 { "Document" }
            default { "Unknown ($($component.Type))" }
        }

        Write-Host "`n--- $name ($type) ---" -ForegroundColor Yellow

        $codeModule = $component.CodeModule
        if ($codeModule.CountOfLines -gt 0) {
            $code = $codeModule.Lines(1, $codeModule.CountOfLines)
            Write-Host $code
        } else {
            Write-Host "(No code)"
        }
    }

    $workbook.Close($false)
}
catch {
    Write-Error "Error: $_"
}
finally {
    if ($excel) {
        $excel.Quit()
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    }
}
