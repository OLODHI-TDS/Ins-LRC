# Update Email/Phone from CSV
# This script reads a CSV file and updates existing Land Registry Check records
# with email and phone data

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,

    [Parameter(Mandatory=$false)]
    [string]$TargetOrg = "omardev"
)

# Check if file exists
if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}

Write-Host "Reading CSV file: $CsvPath" -ForegroundColor Cyan

# Read CSV content
$csvContent = Get-Content -Path $CsvPath -Raw

# Escape special characters for Apex string
$csvContent = $csvContent -replace "'", "\'"
$csvContent = $csvContent -replace "`r`n", "\n"
$csvContent = $csvContent -replace "`n", "\n"

# Create temporary Apex file
$apexCode = @"
String csvContent = '$csvContent';
String result = LandRegistryCSVParser.updateEmailPhoneFromCSV(csvContent);
System.debug(LoggingLevel.INFO, '=== UPDATE RESULT ===');
System.debug(LoggingLevel.INFO, result);
"@

$tempApexFile = [System.IO.Path]::GetTempFileName() + ".apex"
$apexCode | Out-File -FilePath $tempApexFile -Encoding UTF8

Write-Host "Executing Apex against org: $TargetOrg" -ForegroundColor Cyan

# Execute via SFDX
try {
    $output = sf apex run --file $tempApexFile --target-org $TargetOrg 2>&1

    # Display output
    Write-Host "`n=== Execution Output ===" -ForegroundColor Green
    $output | ForEach-Object {
        if ($_ -match "UPDATE RESULT|Update Complete|CSV rows|Records updated|Records matched|not found") {
            Write-Host $_ -ForegroundColor Yellow
        } else {
            Write-Host $_
        }
    }
}
catch {
    Write-Error "Error executing Apex: $_"
}
finally {
    # Cleanup temp file
    if (Test-Path $tempApexFile) {
        Remove-Item $tempApexFile -Force
    }
}

Write-Host "`nDone!" -ForegroundColor Green
