param(
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [Parameter(Mandatory = $true)]
    [Pup.Transport.PupBrowser]$Browser,
    [Parameter(Mandatory = $false)]
    [string[]]$ConsentSteps
)
Write-Verbose "Testing $Url with consent steps: $($ConsentSteps -join ', ')"
$Page = $Browser | New-PupPage -Url $Url -WaitForLoad
$Domain = [Uri]$page.Url
# Before consent
$Cookies = @{Before = ($page | Get-PupCookie); After = $null}
$Network = @{Before = ($page | Get-PupNetwork); After = $null}

# Detect and click consent banner
foreach ($ConsentStep in $ConsentSteps) {
    Write-Verbose "clicking consent step: $ConsentStep"
    $Page | Find-PupElements -Text $ConsentStep | Invoke-PupElementClick
}

# Click around a bit to trigger more network requests and cookies
$Links = $Page | Find-PupElements -Selector 'a[href^="/"]' `
    | Get-PupElementAttribute -Name 'href' `
    | ForEach-Object { $Domain.Scheme + "://" + $Domain.Host + $_ } `
    | Select-Object -First 3 

$Links | ForEach-Object { $Page = $Page | Move-PupPage -Url $_ -WaitForLoad} 

# $Links
# After consent
$Cookies.After = $Page | Get-PupCookie
$Network.After = $Page | Get-PupNetwork

Write-Verbose "Cookies before consent: $($Cookies.Before.Count), after consent: $($Cookies.After.Count)"
Write-Verbose "Network requests before consent: $($Network.Before.Count), after consent: $($Network.After.Count)"

$Page | Remove-PupPage