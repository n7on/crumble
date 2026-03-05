# Crumble

[![GDPR Compliance Scan](https://github.com/n7on/crumble/actions/workflows/gdpr-scan.yml/badge.svg)](https://github.com/n7on/crumble/actions/workflows/gdpr-scan.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-blue.svg)](https://github.com/PowerShell/PowerShell)

**Automated GDPR compliance scanner** that detects tracking cookies and third-party trackers loading before user consent.

**[📊 View Reports](https://n7on.github.io/crumble/)**

## The Problem

Under GDPR and the ePrivacy Directive, websites must obtain user consent **before** setting tracking cookies or contacting advertising/analytics services. Many websites violate this by loading trackers immediately on page load, before any consent interaction.

## What Crumble Does

Crumble visits websites in a headless browser and:

1. **Captures pre-consent state** — Records all cookies and network requests before clicking anything
2. **Simulates consent** — Clicks the cookie consent banner
3. **Analyzes violations** — Identifies tracking cookies and known tracker domains contacted before consent was given
4. **Generates reports** — Produces detailed HTML and PDF compliance reports

## Detected Trackers

- **Analytics**: Google Analytics, Hotjar, Microsoft Clarity, Amplitude, Optimizely
- **Advertising**: Google Ads, Facebook Pixel, LinkedIn Insight, Twitter Pixel
- **Session Recording**: FullStory, LogRocket, Smartlook
- **And more** — see the full list in `scripts/Test-GdprCompliance.ps1`

## Quick Start

```powershell
# Install dependencies
Install-Module -Name Pup -Scope CurrentUser
Install-PupBrowser -BrowserType Chrome

# Run a scan
./scripts/Start-CrumbleScan.ps1 -ScanPath ./configs/swedish-municipalities.json -Pdf
```

## Reports

Crumble generates professional compliance reports showing:

- Overall compliance rate
- Sites with pre-consent violations
- Specific trackers and cookies detected
- Detailed breakdown per site

## Use Cases

- **Public sector audits** — Scan government or municipal websites for compliance
- **Agency compliance checks** — Verify client websites before launch
- **Competitive analysis** — Benchmark compliance across an industry
- **Continuous monitoring** — Automated weekly scans via GitHub Actions

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, configuration format, and how to add custom trackers.

## License

MIT