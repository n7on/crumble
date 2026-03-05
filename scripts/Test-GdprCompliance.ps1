param(
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [Parameter(Mandatory = $true)]
    [Pup.Transport.PupBrowser]$Browser,
    [Parameter(Mandatory = $false)]
    [string[]]$ConsentSteps
)

# Known trackers and analytics domains (partial matches)
$KnownTrackers = @(
    'google-analytics.com',
    'googletagmanager.com',
    'doubleclick.net',
    'facebook.net',
    'facebook.com/tr',
    'connect.facebook',
    'analytics.google.com',
    'hotjar.com',
    'clarity.ms',
    'fullstory.com',
    'mixpanel.com',
    'segment.com',
    'amplitude.com',
    'heap.io',
    'mouseflow.com',
    'crazyegg.com',
    'optimizely.com',
    'pingdom.net',
    'newrelic.com',
    'linkedin.com/px',
    'ads.linkedin.com',
    'twitter.com/i/adsct',
    'tiktok.com',
    'snapchat.com/scevent',
    'bing.com/bat',
    'adform.net',
    'criteo.com',
    'outbrain.com',
    'taboola.com',
    'matomo',
    'piwik'
)

# Helper function to check if a URL is a third-party request
function Test-ThirdPartyRequest {
    param([string]$RequestUrl, [string]$SiteDomain)
    try {
        $requestHost = ([Uri]$RequestUrl).Host
        # Compare base domains (handles subdomains)
        $siteBase = ($SiteDomain -split '\.')[-2..-1] -join '.'
        $requestBase = ($requestHost -split '\.')[-2..-1] -join '.'
        return $siteBase -ne $requestBase
    } catch {
        return $true
    }
}

# Helper function to identify known trackers
function Get-TrackerMatch {
    param([string]$RequestUrl)
    foreach ($tracker in $KnownTrackers) {
        if ($RequestUrl -match [regex]::Escape($tracker)) {
            return $tracker
        }
    }
    return $null
}

# Helper function to categorize cookies
function Get-CookieCategory {
    param($Cookie)
    $name = $Cookie.Name.ToLower()
    
    # Check functional/session patterns FIRST (these are usually legitimate)
    if ($name -match '^(jsessionid|phpsessid|asp\.net_sessionid|session_id|sessionid)$') { return 'Functional' }
    if ($name -match 'session|csrf|xsrf|token|auth') { return 'Functional' }
    if ($name -match 'consent|cookie.*accept|gdpr|cc_') { return 'Consent' }
    
    # Known tracking/analytics cookie patterns
    $trackingPatterns = @('^_ga$', '^_gid$', '^_gat', '_fbp', '_fbc', '^fr$', '_hjid', '_hj', '_clck', '_clsk', '^mp_', 'amplitude', 'optimizely', '^ajs_')
    $adPatterns = @('_gcl', '^IDE$', '^test_cookie$', '^NID$', '^DSID$', '_uetsid', 'li_fat_id', '^bcookie$')
    
    foreach ($pattern in $trackingPatterns) {
        if ($name -match $pattern) { return 'Analytics/Tracking' }
    }
    foreach ($pattern in $adPatterns) {
        if ($name -match $pattern) { return 'Advertising' }
    }
    
    return 'Unknown'
}

Write-Verbose "Testing $Url with consent steps: $($ConsentSteps -join ', ')"
$Page = $Browser | New-PupPage -Url $Url -WaitForLoad
$Domain = [Uri]$Page.Url
$SiteDomain = $Domain.Host

# Before consent
$Cookies = @{Before = ($Page | Get-PupCookie); After = $null}
$Network = @{Before = ($Page | Get-PupNetwork); After = $null}

# Detect and click consent banner
foreach ($ConsentStep in $ConsentSteps) {
    Write-Verbose "Clicking consent step: $ConsentStep"
    $ElementSteps = $Page | Find-PupElements -Text $ConsentStep -Visible
    if ($ElementSteps.Count -eq 0) {
        Write-Warning "Consent step '$ConsentStep' not found on the page!"
    } elseif($ElementSteps.Count -gt 1) {
        Write-Warning "Multiple elements found for consent step '$ConsentStep'. Clicking the first one."
        $ElementSteps[0] | Invoke-PupElementClick
    } else {
        $ElementSteps | Invoke-PupElementClick
    }
}

# Click around a bit to trigger more network requests and cookies
$Links = $Page | Find-PupElements -Selector 'a[href^="/"]' `
    | Get-PupElementAttribute -Name 'href' `
    | ForEach-Object { $Domain.Scheme + "://" + $Domain.Host + $_ } `
    | Select-Object -First 3 

$Links | ForEach-Object { $Page = $Page | Move-PupPage -Url $_ -WaitForLoad }

# After consent
$Cookies.After = $Page | Get-PupCookie
$Network.After = $Page | Get-PupNetwork

$Page | Remove-PupPage

# === ANALYSIS ===

# Analyze pre-consent cookies
$PreConsentCookieAnalysis = $Cookies.Before | ForEach-Object {
    [PSCustomObject]@{
        Name       = $_.Name
        Domain     = $_.Domain
        Category   = Get-CookieCategory $_
        IsThirdParty = $_.Domain -notmatch [regex]::Escape($SiteDomain)
        Expires    = $_.Expires
        HttpOnly   = $_.HttpOnly
        Secure     = $_.Secure
    }
}

# Flag problematic pre-consent cookies (tracking/ads before consent = violation)
$PreConsentViolations = $PreConsentCookieAnalysis | Where-Object { 
    $_.Category -in @('Analytics/Tracking', 'Advertising') 
}

# Analyze pre-consent network requests
$PreConsentNetworkAnalysis = $Network.Before | ForEach-Object {
    $tracker = Get-TrackerMatch $_.Url
    [PSCustomObject]@{
        Url          = $_.Url
        Method       = $_.Method
        ResourceType = $_.ResourceType
        IsThirdParty = Test-ThirdPartyRequest $_.Url $SiteDomain
        KnownTracker = $tracker
        Domain       = ([Uri]$_.Url).Host
    }
} | Where-Object { $_.IsThirdParty }

# Identify tracking requests before consent (violations)
$PreConsentTrackerViolations = $PreConsentNetworkAnalysis | Where-Object { $null -ne $_.KnownTracker }

# Get unique third-party domains contacted before consent
$ThirdPartyDomainsBefore = $PreConsentNetworkAnalysis | Select-Object -ExpandProperty Domain -Unique

# Summary statistics
$Analysis = [PSCustomObject]@{
    Url                          = $Url
    TestedAt                     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    
    # Cookie stats
    CookiesBeforeConsent         = $Cookies.Before.Count
    CookiesAfterConsent          = $Cookies.After.Count
    TrackingCookiesBeforeConsent = ($PreConsentViolations | Measure-Object).Count
    
    # Network stats  
    RequestsBeforeConsent        = $Network.Before.Count
    RequestsAfterConsent         = $Network.After.Count
    ThirdPartyRequestsBefore     = ($PreConsentNetworkAnalysis | Measure-Object).Count
    KnownTrackersBeforeConsent   = ($PreConsentTrackerViolations | Measure-Object).Count
    
    # Violation flags
    HasPreConsentTrackingCookies = ($PreConsentViolations | Measure-Object).Count -gt 0
    HasPreConsentTrackers        = ($PreConsentTrackerViolations | Measure-Object).Count -gt 0
    
    # Detailed data
    PreConsentCookieViolations   = $PreConsentViolations
    PreConsentTrackerViolations  = $PreConsentTrackerViolations
    ThirdPartyDomainsBefore      = $ThirdPartyDomainsBefore
    AllPreConsentCookies         = $PreConsentCookieAnalysis
    AllThirdPartyRequests        = $PreConsentNetworkAnalysis
}

# Output warnings
if ($Analysis.HasPreConsentTrackingCookies) {
    Write-Warning "VIOLATION: $($Analysis.TrackingCookiesBeforeConsent) tracking cookie(s) set BEFORE consent!"
    $PreConsentViolations | ForEach-Object { Write-Warning "  - $($_.Name) ($($_.Category)) on $($_.Domain)" }
}

if ($Analysis.HasPreConsentTrackers) {
    Write-Warning "VIOLATION: $($Analysis.KnownTrackersBeforeConsent) known tracker(s) contacted BEFORE consent!"
    $PreConsentTrackerViolations | ForEach-Object { Write-Warning "  - $($_.KnownTracker): $($_.Url)" }
}

Write-Verbose "Cookies before consent: $($Cookies.Before.Count), after consent: $($Cookies.After.Count)"
Write-Verbose "Network requests before consent: $($Network.Before.Count), after consent: $($Network.After.Count)"
Write-Verbose "Third-party domains before consent: $($ThirdPartyDomainsBefore.Count)"

# Return analysis object
$Analysis