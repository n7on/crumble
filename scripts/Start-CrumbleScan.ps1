<#
.SYNOPSIS
    Runs a GDPR compliance scan and generates reports.

.DESCRIPTION
    Loads a scan configuration, tests each site for pre-consent tracking,
    and generates HTML and optionally PDF reports.

.PARAMETER ScanPath
    Path to the scan JSON file (e.g., configs/my-company.json).

.PARAMETER OutputPath
    Path for the output report. Defaults to ./report.html.

.PARAMETER Pdf
    Also generate a PDF report alongside HTML.

.PARAMETER Limit
    Maximum number of sites to scan (0 = all).

.EXAMPLE
    ./Start-CrumbleScan.ps1 -ScanPath ./configs/swedish-municipalities.json

.EXAMPLE
    ./Start-CrumbleScan.ps1 -ScanPath ./configs/my-company.json -Pdf -Limit 10
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ScanPath,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "./report.html",
    
    [Parameter(Mandatory = $false)]
    [switch]$Pdf,
    
    [Parameter(Mandatory = $false)]
    [int]$Limit = 0
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load scan configuration
Write-Host "Loading scan from: $ScanPath"
$scan = Get-Content -Path $ScanPath | ConvertFrom-Json
$sites = $scan.Sites

if ($Limit -gt 0) {
    $sites = $sites | Select-Object -First $Limit
}

Write-Host "Scanning '$($scan.Name)': $($sites.Count) sites..."

# Start browser
Import-Module Pup
$browser = Start-PupBrowser -Headless

try {
    # Run scans
    $results = @()
    foreach ($site in $sites) {
        Write-Host "Scanning: $($site.Url)"
        try {
            $result = & "$ScriptDir/Test-GdprCompliance.ps1" -Url $site.Url -Browser $browser -ConsentSteps $site.ConsentSteps
            $results += $result
        } catch {
            Write-Warning "Failed to scan $($site.Url): $_"
            $results += [PSCustomObject]@{
                Url = $site.Url
                Error = $_.Exception.Message
                TestedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            }
        }
    }

    # Save results JSON
    $outputDir = Split-Path -Parent $OutputPath
    if (-not $outputDir) { $outputDir = "." }
    $resultsPath = Join-Path $outputDir "report.json"
    $results | ConvertTo-Json -Depth 10 | Out-File -Path $resultsPath
    Write-Host "Results saved to: $resultsPath"

    # Generate HTML report
    & "$ScriptDir/New-CrumbleReport.ps1" -ResultsPath $resultsPath -OutputPath $OutputPath -ScanName $scan.Name -ScanDescription $scan.Description
    Write-Host "HTML report: $OutputPath"

    # Generate PDF if requested
    if ($Pdf) {
        $pdfPath = Join-Path $outputDir "report.pdf"
        & "$ScriptDir/New-CrumbleReport.ps1" -ResultsPath $resultsPath -OutputPath $pdfPath -ScanName $scan.Name -ScanDescription $scan.Description -Browser $browser
        Write-Host "PDF report: $pdfPath"
    }
} finally {
    $browser | Stop-PupBrowser
}

Write-Host "Scan complete!"
