$csv = Import-Csv 'C:\Users\Omar.Lodhi\OneDrive - The Dispute Service\Projects\Land Reg API\Original Process\landlord-compliance-checks-landlord-report-under-member-2026-01-02-10_23-57.csv'

Write-Host "=== Sample Addresses from CSV ===" -ForegroundColor Cyan
Write-Host ""

$addresses = $csv | Select-Object -ExpandProperty 'Tenancy First Line' | Where-Object { $_ -ne '' } | Select-Object -Unique

# Show first 50 unique addresses
$addresses | Select-Object -First 50 | ForEach-Object {
    Write-Host "[$_]"
}

Write-Host ""
Write-Host "=== Total unique addresses: $($addresses.Count) ===" -ForegroundColor Yellow
