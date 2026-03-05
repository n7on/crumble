<#
.SYNOPSIS
    Generates a GDPR cookie compliance report from scan results.

.DESCRIPTION
    Processes scan results JSON and generates an HTML report, optionally converting to PDF.

.PARAMETER ResultsPath
    Path to the scan results JSON file.

.PARAMETER OutputPath
    Path where the report will be written. Use .html or .pdf extension.

.PARAMETER Browser
    Pup browser instance for PDF generation. Required if OutputPath is .pdf.

.EXAMPLE
    ./New-CrumbleReport.ps1 -ResultsPath ./scan-results.json -OutputPath ./report.html

.EXAMPLE
    $browser = Start-PupBrowser -Headless
    ./New-CrumbleReport.ps1 -ResultsPath ./scan-results.json -OutputPath ./report.pdf -Browser $browser
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ResultsPath,
    
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    
    [Parameter(Mandatory = $false)]
    [string]$ScanName = "GDPR Compliance Scan",
    
    [Parameter(Mandatory = $false)]
    [string]$ScanDescription = "",
    
    [Parameter(Mandatory = $false)]
    $Browser
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$TemplatePath = Join-Path $RootDir 'templates/report-template.html'

# Determine output format
$extension = [System.IO.Path]::GetExtension($OutputPath).ToLower()
$isPdf = $extension -eq '.pdf'

if ($isPdf -and -not $Browser) {
    throw "Browser parameter is required for PDF output. Use: Start-PupBrowser -Headless"
}

#region Process Scan Results

Write-Verbose "Loading scan results from: $ResultsPath"
$results = Get-Content -Path $ResultsPath -Raw | ConvertFrom-Json

# Statistics
$total = $results.Count
$errors = ($results | Where-Object { $null -ne $_.Error }).Count
$scanned = $total - $errors
$withCookieViolations = ($results | Where-Object { $_.HasPreConsentTrackingCookies }).Count
$withTrackerViolations = ($results | Where-Object { $_.HasPreConsentTrackers }).Count
$withAnyViolation = ($results | Where-Object { $_.HasPreConsentTrackingCookies -or $_.HasPreConsentTrackers }).Count
$compliant = $scanned - $withAnyViolation
$complianceRate = if ($scanned -gt 0) { [math]::Round(($compliant / $scanned) * 100, 1) } else { 0 }

# Categorize sites
$violatingSites = $results | 
    Where-Object { $_.HasPreConsentTrackingCookies -or $_.HasPreConsentTrackers } | 
    Sort-Object -Property @{Expression = { $_.KnownTrackersBeforeConsent }; Descending = $true } |
    ForEach-Object {
        [PSCustomObject]@{
            Url                = $_.Url
            TrackingCookies    = $_.TrackingCookiesBeforeConsent
            KnownTrackers      = $_.KnownTrackersBeforeConsent
            ThirdPartyRequests = $_.ThirdPartyRequestsBefore
            TrackerViolations  = $_.PreConsentTrackerViolations | ForEach-Object { 
                [PSCustomObject]@{ Tracker = $_.KnownTracker; Url = $_.Url }
            }
            CookieViolations   = $_.PreConsentCookieViolations | ForEach-Object { 
                [PSCustomObject]@{ Name = $_.Name; Category = $_.Category }
            }
        }
    }

$compliantSites = $results | 
    Where-Object { -not $_.HasPreConsentTrackingCookies -and -not $_.HasPreConsentTrackers -and $null -eq $_.Error } |
    ForEach-Object {
        [PSCustomObject]@{
            Url           = $_.Url
            CookiesBefore = $_.CookiesBeforeConsent
            CookiesAfter  = $_.CookiesAfterConsent
        }
    }

$failedSites = $results | 
    Where-Object { $null -ne $_.Error } |
    ForEach-Object {
        [PSCustomObject]@{
            Url   = $_.Url
            Error = $_.Error -replace '[\r\n]', ' '
        }
    }

# Aggregate trackers
$topTrackers = $results | 
    ForEach-Object { $_.PreConsentTrackerViolations } | 
    Where-Object { $_ } |
    ForEach-Object { $_.KnownTracker } |
    Group-Object | 
    Sort-Object Count -Descending |
    Select-Object -First 15 |
    ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Count = $_.Count } }

# Aggregate cookies
$topCookies = $results | 
    ForEach-Object { $_.PreConsentCookieViolations } | 
    Where-Object { $_ } |
    ForEach-Object { $_.Name } |
    Group-Object | 
    Sort-Object Count -Descending |
    Select-Object -First 15 |
    ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Count = $_.Count } }

# Aggregate third-party domains
$topThirdPartyDomains = $results | 
    ForEach-Object { $_.ThirdPartyDomainsBefore } | 
    Where-Object { $_ } |
    Group-Object | 
    Sort-Object Count -Descending |
    Select-Object -First 15 |
    ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Count = $_.Count } }

#endregion

#region Render HTML

Write-Verbose "Rendering HTML report..."
$html = Get-Content -Path $TemplatePath -Raw

# Embed logo as base64
$logoPath = Join-Path $RootDir 'templates/crumble.png'
if (Test-Path $logoPath) {
    $logoBytes = [System.IO.File]::ReadAllBytes($logoPath)
    $logoBase64 = "data:image/png;base64," + [Convert]::ToBase64String($logoBytes)
    $html = $html -replace '{{LogoBase64}}', $logoBase64
}

$scanDate = Get-Date -Format 'yyyy-MM-dd'
$scanTime = Get-Date -Format 'HH:mm:ss'

# Metadata
$html = $html -replace '{{ScanName}}', $ScanName
$html = $html -replace '{{ScanDescription}}', $ScanDescription

# Statistics
$html = $html -replace '{{ScanDate}}', $scanDate
$html = $html -replace '{{ScanTime}}', $scanTime
$html = $html -replace '{{TotalScanned}}', $scanned
$html = $html -replace '{{ComplianceRate}}', $complianceRate
$html = $html -replace '{{WithViolations}}', $withAnyViolation
$html = $html -replace '{{WithTrackers}}', $withTrackerViolations
$html = $html -replace '{{WithCookies}}', $withCookieViolations
$html = $html -replace '{{Errors}}', $errors

$violationClass = if ($withAnyViolation -gt 0) { 'warning' } else { 'success' }
$html = $html -replace '{{ViolationCardClass}}', $violationClass

# Violations section
if (-not $violatingSites -or $violatingSites.Count -eq 0) {
    $violationsContent = @'
<div class="empty-state">
    <div class="icon">✓</div>
    <p><strong>No violations detected!</strong></p>
    <p>All scanned sites appear to be GDPR compliant regarding pre-consent tracking.</p>
</div>
'@
} else {
    $violationsTable = $violatingSites | Select-Object @(
        @{ Name = 'Site'; Expression = { $_.Url } }
        @{ Name = 'Tracking Cookies'; Expression = { $_.TrackingCookies } }
        @{ Name = 'Known Trackers'; Expression = { $_.KnownTrackers } }
        @{ Name = '3rd Party Requests'; Expression = { $_.ThirdPartyRequests } }
    ) | ConvertTo-Html -Fragment
    
    $detailsHtml = ""
    foreach ($site in ($violatingSites | Select-Object -First 10)) {
        $trackersList = ""
        if ($site.TrackerViolations -and $site.TrackerViolations.Count -gt 0) {
            $items = ($site.TrackerViolations | ForEach-Object { "<li><strong>$($_.Tracker)</strong><br><code>$($_.Url)</code></li>" }) -join "`n"
            $trackersList = "<p><strong>Trackers contacted before consent:</strong></p><ul>$items</ul>"
        }
        
        $cookiesList = ""
        if ($site.CookieViolations -and $site.CookieViolations.Count -gt 0) {
            $items = ($site.CookieViolations | ForEach-Object { "<li><code>$($_.Name)</code> ($($_.Category))</li>" }) -join "`n"
            $cookiesList = "<p><strong>Tracking cookies set before consent:</strong></p><ul>$items</ul>"
        }
        
        $detailsHtml += @"
<div class="violation-detail">
    <h4>$($site.Url)</h4>
    $trackersList
    $cookiesList
</div>
"@
    }
    
    $moreNote = if ($violatingSites.Count -gt 10) { "<p><em>Showing top 10 of $($violatingSites.Count) violating sites.</em></p>" } else { "" }
    
    $violationsContent = @"
<h3>Sites with Pre-Consent Violations</h3>
<p>The following sites set tracking cookies or contacted trackers <strong>before</strong> user consent:</p>
$violationsTable

<h3>Detailed Breakdown</h3>
$detailsHtml
$moreNote
"@
}
$html = $html -replace '{{ViolationsContent}}', $violationsContent

# Tracker analysis tables
$trackersTable = if ($topTrackers.Count -gt 0) {
    $topTrackers | Select-Object @(
        @{ Name = 'Tracker Domain'; Expression = { $_.Name } }
        @{ Name = 'Sites Affected'; Expression = { $_.Count } }
    ) | ConvertTo-Html -Fragment
} else { '<p class="empty-state">No pre-consent trackers detected.</p>' }

$cookiesTable = if ($topCookies.Count -gt 0) {
    $topCookies | Select-Object @(
        @{ Name = 'Cookie Name'; Expression = { $_.Name } }
        @{ Name = 'Sites Affected'; Expression = { $_.Count } }
    ) | ConvertTo-Html -Fragment
} else { '<p class="empty-state">No pre-consent tracking cookies detected.</p>' }

$thirdPartyTable = if ($topThirdPartyDomains.Count -gt 0) {
    $topThirdPartyDomains | Select-Object @(
        @{ Name = 'Domain'; Expression = { $_.Name } }
        @{ Name = 'Sites'; Expression = { $_.Count } }
    ) | ConvertTo-Html -Fragment
} else { '<p class="empty-state">No third-party domains detected.</p>' }

$html = $html -replace '{{TrackersTable}}', $trackersTable
$html = $html -replace '{{CookiesTable}}', $cookiesTable
$html = $html -replace '{{ThirdPartyTable}}', $thirdPartyTable

# Compliant sites
$compliantContent = if ($compliantSites.Count -gt 0) {
    $compliantTable = $compliantSites | Select-Object @(
        @{ Name = 'Site'; Expression = { $_.Url } }
        @{ Name = 'Cookies Before'; Expression = { $_.CookiesBefore } }
        @{ Name = 'Cookies After'; Expression = { $_.CookiesAfter } }
    ) | ConvertTo-Html -Fragment
    @"
<p><strong>$($compliantSites.Count) sites</strong> showed no pre-consent tracking violations:</p>
$compliantTable
"@
} else { '<p class="empty-state">No compliant sites in this scan.</p>' }

$html = $html -replace '{{CompliantContent}}', $compliantContent

# Errors section
$errorsSection = if ($failedSites.Count -gt 0) {
    $errorsTable = $failedSites | Select-Object @(
        @{ Name = 'Site'; Expression = { $_.Url } }
        @{ Name = 'Error'; Expression = { $_.Error.Substring(0, [Math]::Min($_.Error.Length, 100)) } }
    ) | ConvertTo-Html -Fragment
    @"
<section id="errors">
    <h2>Scan Errors</h2>
    <p><strong>$($failedSites.Count) sites</strong> could not be scanned:</p>
    $errorsTable
</section>
"@
} else { "" }

$html = $html -replace '{{ErrorsSection}}', $errorsSection

#endregion

#region Output

# Ensure output directory exists
$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

if ($isPdf) {
    $tempHtml = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.html'
    $html | Out-File -Path $tempHtml -Encoding utf8
    
    Write-Verbose "Generating PDF with Pup..."
    $page = $Browser | New-PupPage -Url "file://$tempHtml" -WaitForLoad
    $page | Export-PupPdf -FilePath $OutputPath
    $page | Remove-PupPage
    
    Remove-Item $tempHtml -ErrorAction SilentlyContinue
    Write-Verbose "PDF written to: $OutputPath"
} else {
    $html | Out-File -Path $OutputPath -Encoding utf8
    Write-Verbose "HTML written to: $OutputPath"
}

# Summary
Write-Host "Report generated: $OutputPath"
Write-Host "  Total sites: $total"
Write-Host "  Scanned: $scanned"
Write-Host "  Violations: $withAnyViolation"
Write-Host "  Compliance rate: $complianceRate%"

#endregion
