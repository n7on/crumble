<img src="templates/crumble.png" alt="Crumble" width="200">

GDPR cookie compliance scanner for websites. Detects tracking cookies and third-party trackers that load **before** user consent.

## Features

- Detects pre-consent tracking cookies (Google Analytics, Facebook, etc.)
- Identifies known tracker domains contacted before consent
- Generates HTML and PDF compliance reports
- Automated weekly scans via GitHub Actions

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/n7on/crumble.git
   cd crumble
   ```

2. **Install the Pup module**
   ```powershell
   Install-Module -Name Pup -Scope CurrentUser
   Install-PupBrowser -BrowserType Chrome
   ```

3. **Create a scan file in `scans/`**
   ```json
   // scans/my-company.json
   {
     "Name": "My Company Sites",
     "Description": "GDPR compliance scan for company websites",
     "Sites": [
       {
         "Url": "https://example.com",
         "ConsentSteps": ["Accept all cookies"]
       },
       {
         "Url": "https://another-site.com",
         "ConsentSteps": ["Accept"]
       }
     ]
   }
   ```

4. **Run a scan**
   ```powershell
   Import-Module Pup
   $browser = Start-PupBrowser -Headless
   
   $scan = Get-Content ./scans/my-company.json | ConvertFrom-Json
   $results = foreach ($site in $scan.Sites) {
       ./scripts/Test-GdprCompliance.ps1 -Url $site.Url -Browser $browser -ConsentSteps $site.ConsentSteps
   }
   
   $results | ConvertTo-Json -Depth 10 | Set-Content ./scan-results.json
   ./scripts/New-CrumbleReport.ps1 -ResultsPath ./scan-results.json -OutputPath ./report.html -ScanName $scan.Name -ScanDescription $scan.Description
   
   $browser | Stop-PupBrowser
   ```

## GitHub Actions

The included workflow runs weekly and uploads reports as artifacts. To use it:

1. Add your scan files to the `scans/` folder
2. Enable GitHub Actions in your repo settings
3. Manually trigger via **Actions** → **GDPR Cookie Compliance Scan** → **Run workflow**
4. Select which scan file to use (defaults to `swedish-municipalities.json`)

## Configuration

### ConsentSteps

The `ConsentSteps` array contains button text to click for accepting cookies. Common examples:

- `"Accept all cookies"` / `"Accept all"`
- `"Godkänn alla kakor"` (Swedish)
- `"Akzeptieren"` (German)
- `"Accepter"` (French)

### Known Trackers

The scanner detects requests to known tracking domains including Google Analytics, Facebook, HotJar, Microsoft Clarity, and more. See `scripts/Test-GdprCompliance.ps1` for the full list.

## Example: Scraping Sites

```powershell
# Scrape municipality URLs from a listing page
$browser = Start-PupBrowser -Headless
$page = $browser | New-PupPage -Url https://skr.se/kommunerochregioner/kommunerlista.8288.html 
$sites = $page | Find-PupElements -Selector ".lp-link-list a" | ForEach-Object {
    [PSCustomObject]@{
        Url = ($_ | Get-PupElementAttribute -Name 'href')
        ConsentSteps = @("Godkänn alla kakor")
    }
}

@{
    Name = "Swedish Municipalities"
    Description = "Official websites of all 290 Swedish municipalities"
    Sites = $sites
} | ConvertTo-Json -Depth 10 | Set-Content scans/swedish-municipalities.json

$browser | Stop-PupBrowser
```

## License

MIT