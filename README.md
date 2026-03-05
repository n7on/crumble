# Crumble



## Setup


```powershell
$page = $browser | New-PupPage -Url https://skr.se/kommunerochregioner/kommunerlista.8288.html 
$page | find-PupElements -Selector ".lp-link-list a" |% {[PSObject] @{Url=($_ | Get-PupElementAttribute -Name 'href'); ConsentSteps=@("Godkänn alla kakor")}} | ConvertTo-Json | Set-Content sites.json
```