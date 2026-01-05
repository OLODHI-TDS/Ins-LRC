$csv = Import-Csv 'C:\Users\Omar.Lodhi\OneDrive - The Dispute Service\Projects\Land Reg API\Original Process\landlord-compliance-checks-landlord-report-under-member-2026-01-02-10_23-57.csv'
$duddy = $csv | Where-Object { $_.Name -like '*Duddy*' }
Write-Host "=== Duddy Record ===" -ForegroundColor Cyan
Write-Host "Tenancy First Line: [$($duddy.'Tenancy First Line')]"
Write-Host "Tenancy Town: [$($duddy.'Tenancy Town')]"
Write-Host "Tenancy County: [$($duddy.'Tenancy County')]"
Write-Host "Tenancy Postcode: [$($duddy.'Tenancy Postcode')]"
