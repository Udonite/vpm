<#
    Udonite supporter listing setup.

        irm https://udonite.github.io/vpm/install.ps1 | iex

    Adds the private Udonite listing to the VRChat Creator Companion. Contains no
    secrets: your token is only ever sent to GitHub, and is stored by the
    Companion on your own machine.
#>

$ErrorActionPreference = "Stop"

$listingUrl = "https://raw.githubusercontent.com/Udonite/vpm-supporters/main/index.json"
$vccRoot    = Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion"
$settings   = Join-Path $vccRoot "settings.json"
$reposDir   = Join-Path $vccRoot "Repos"

Write-Host ""
Write-Host "  Udonite setup" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $settings)) {
    Write-Host "  The VRChat Creator Companion is not installed yet." -ForegroundColor Red
    Write-Host "  Get it from https://vrchat.com/home/download, open it once, then run this again."
    Write-Host ""
    return
}

# The Companion rewrites its settings when it closes, which would undo this.
# Wait for it rather than making the user start over.
while (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "*Creator*Companion*" }) {
    Write-Host "  Please close the VRChat Creator Companion, then press Enter." -ForegroundColor Yellow
    Read-Host | Out-Null
}

$token = $env:UDONITE_TOKEN
if (-not $token) {
    Write-Host "  Paste your token and press Enter. Nothing will appear as you paste."
    Write-Host ""
    $secure = Read-Host "  Token" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
$token = $token.Trim()

# Check the token before touching anything on disk, so a bad one cannot leave a
# half-configured Companion behind.
Write-Host ""
Write-Host "  Checking your token..." -NoNewline
try {
    $response = Invoke-WebRequest -Uri $listingUrl -UseBasicParsing -Headers @{
        Authorization = "Bearer $token"
        Accept        = "application/octet-stream"
    }
} catch {
    Write-Host " no" -ForegroundColor Red
    Write-Host ""
    Write-Host "  That token does not work. Two things to check:"
    Write-Host "    1. Accept the invitation first: https://github.com/Udonite/vpm-supporters/invitations"
    Write-Host "    2. Use the GitHub account you subscribed with, and check the token has not expired."
    Write-Host ""
    return
}
Write-Host " ok" -ForegroundColor Green

$listing = $response.Content | ConvertFrom-Json
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$auth = [pscustomobject]@{ Authorization = "Bearer $token"; Accept = "application/octet-stream" }

Write-Host "  Adding the listing..." -NoNewline

# The cache file wraps the listing rather than being it. Writing the bare
# index.json makes the Companion report the listing as unreachable.
$md5 = New-Object Security.Cryptography.MD5CryptoServiceProvider
$hash = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($listingUrl))) -replace '-', '').Substring(0, 8).ToLower()
if (-not (Test-Path $reposDir)) { New-Item -ItemType Directory -Force $reposDir | Out-Null }
$localPath = Join-Path $reposDir "$($listing.id)-$hash.json"
[IO.File]::WriteAllText($localPath, ([pscustomobject]@{ headers = $auth; repo = $listing } | ConvertTo-Json -Depth 64), $utf8NoBom)

Copy-Item $settings "$settings.udonite-backup" -Force
$config = Get-Content $settings -Raw | ConvertFrom-Json

$entry = [pscustomobject]@{
    localPath = $localPath
    url       = $listingUrl
    name      = $listing.name
    id        = $listing.id
    headers   = $auth
}

$kept = @()
if ($config.PSObject.Properties['userRepos'] -and $config.userRepos) {
    $kept = @($config.userRepos | Where-Object { $_.id -ne $listing.id -and $_.url -ne $listingUrl })
}

if ($config.PSObject.Properties['userRepos']) {
    $config.userRepos = @($kept + $entry)
} else {
    $config | Add-Member -NotePropertyName userRepos -NotePropertyValue @($entry)
}

# Depth matters: the default of 2 flattens the Companion's nested settings into
# strings and corrupts the file.
[IO.File]::WriteAllText($settings, ($config | ConvertTo-Json -Depth 64), $utf8NoBom)
Write-Host " ok" -ForegroundColor Green

Write-Host ""
Write-Host "  Done." -ForegroundColor Green
Write-Host ""
Write-Host "  Last step: open the Creator Companion, go to Settings then Packages,"
Write-Host "  and tick 'Udonite Supporters'."
Write-Host ""
