# Update Property Address from CSV
# This script reads a CSV file and updates existing Land Registry Check records
# with property address data (uses FIRST set of tenancy columns)

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

# Import CSV and extract only the columns we need
$csvData = Import-Csv -Path $CsvPath

Write-Host "Found $($csvData.Count) rows in CSV" -ForegroundColor Cyan

# Build a simplified CSV with just the address fields
# Use the FIRST set of tenancy columns (without leading spaces)
$simplifiedRows = @("Landlord ID,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode")

foreach ($row in $csvData) {
    $landlordId = $row.'Landlord ID'
    $firstLine = $row.'Tenancy First Line'
    $town = $row.'Tenancy Town'
    $county = $row.'Tenancy County'
    $postcode = $row.'Tenancy Postcode'

    # Skip rows without landlord ID
    if ([string]::IsNullOrWhiteSpace($landlordId)) { continue }

    # Clean up the values - remove any quotes and escape single quotes
    $landlordId = $landlordId -replace '"', '' -replace "'", "\'"
    $firstLine = if ($firstLine) { $firstLine -replace '"', '' -replace "'", "\'" } else { '' }
    $town = if ($town) { $town -replace '"', '' -replace "'", "\'" } else { '' }
    $county = if ($county) { $county -replace '"', '' -replace "'", "\'" } else { '' }
    $postcode = if ($postcode) { $postcode -replace '"', '' -replace "'", "\'" } else { '' }

    $simplifiedRows += "$landlordId,$firstLine,$town,$county,$postcode"
}

$csvContent = $simplifiedRows -join '\n'

Write-Host "Processed $($simplifiedRows.Count - 1) landlord records" -ForegroundColor Cyan

# Create temporary Apex file (without BOM)
$apexCode = @"
String csvContent = '$csvContent';
String result = LandRegistryCSVParser.updateAddressFromCSV(csvContent);
System.debug(LoggingLevel.INFO, '=== UPDATE RESULT ===');
System.debug(LoggingLevel.INFO, result);
"@

$tempApexFile = [System.IO.Path]::GetTempFileName() + ".apex"
# Write without BOM
[System.IO.File]::WriteAllText($tempApexFile, $apexCode, (New-Object System.Text.UTF8Encoding $false))

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
