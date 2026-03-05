# Contributing to Crumble

## Development Setup

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

## Project Structure

```
crumble/
├── configs/                    # Scan configuration files
│   └── swedish-municipalities.json
├── scripts/
│   ├── Start-CrumbleScan.ps1   # Main entry point
│   ├── Test-GdprCompliance.ps1 # Per-site scanner
│   └── New-CrumbleReport.ps1   # Report generator
├── templates/
│   └── report-template.html    # HTML report template
└── .github/workflows/
    └── gdpr-scan.yml           # Automated scanning
```

## Configuration Format

Create scan configuration files in the `configs/` folder:

```json
{
  "Name": "My Company Sites",
  "Description": "GDPR compliance scan for company websites",
  "Sites": [
    {
      "Url": "https://example.com",
      "ConsentSteps": ["Accept all cookies"]
    }
  ]
}
```

### ConsentSteps

The `ConsentSteps` array contains button text to click for accepting cookies. Common examples:

- `"Accept all cookies"` / `"Accept all"`
- `"Godkänn alla kakor"` (Swedish)
- `"Akzeptieren"` (German)
- `"Accepter"` (French)

## Running Scans Locally

```powershell
# Basic scan
./scripts/Start-CrumbleScan.ps1 -ScanPath ./configs/my-company.json

# With PDF output
./scripts/Start-CrumbleScan.ps1 -ScanPath ./configs/my-company.json -Pdf

# Limit to first 10 sites (useful for testing)
./scripts/Start-CrumbleScan.ps1 -ScanPath ./configs/my-company.json -Pdf -Limit 10
```

## GitHub Actions

The workflow runs weekly and scans **all configs** in the `configs/` folder:

1. Add your scan files to the `configs/` folder
2. Enable GitHub Actions in your repo settings
3. Go to **Actions** → **GDPR Compliance Scan** → **Run workflow**

Each config gets its own report page at `https://n7on.github.io/crumble/{config-name}/`

## Adding New Trackers

Known trackers are defined in `scripts/Test-GdprCompliance.ps1`. To add new tracking domains, update the `$KnownTrackers` hashtable:

```powershell
$KnownTrackers = @{
    'google-analytics.com' = 'Google Analytics'
    'facebook.net'         = 'Facebook'
    # Add new trackers here
}
```

## Scraping Sites Programmatically

Example: Scrape URLs from a listing page:

```powershell
$browser = Start-PupBrowser -Headless
$page = $browser | New-PupPage -Url https://example.com/site-list

$sites = $page | Find-PupElements -Selector "a.site-link" | ForEach-Object {
    [PSCustomObject]@{
        Url = ($_ | Get-PupElementAttribute -Name 'href')
        ConsentSteps = @("Accept all cookies")
    }
}

@{
    Name = "My Sites"
    Description = "Description of the sites being scanned"
    Sites = $sites
} | ConvertTo-Json -Depth 10 | Set-Content configs/my-sites.json

$browser | Stop-PupBrowser
```
