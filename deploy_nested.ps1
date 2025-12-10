<#
deploy_nested.ps1

Usage: run this from the repository root to push the current working tree
into the remote repository under a top-level folder named `GuildUI`.

This script will:
- create a temporary directory
- copy repo files into `<tmp>/GuildUI/` (excluding .git)
- initialize a git repository there and push (force) to `origin/main`

IMPORTANT: the script will perform a force-push to `origin/main`.
Be sure you want to replace the remote branch.
#>

param(
  [string]$RemoteName = 'origin',
  [string]$Branch = 'main'
)

Write-Host "Preparing to deploy repository into folder 'GuildUI' on remote '$RemoteName/$Branch'..."

if (-not (Test-Path -Path .git)) {
  Write-Error "This script must be run from the repository root (where .git is located)."
  exit 1
}

$remoteUrl = git remote get-url $RemoteName 2>$null
if (-not $remoteUrl) {
  Write-Error "Remote '$RemoteName' not found. Add a remote named '$RemoteName' or pass the URL manually."
  exit 1
}

$tmp = Join-Path -Path $env:TEMP -ChildPath ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tmp | Out-Null
$dest = Join-Path -Path $tmp -ChildPath 'GuildUI'
New-Item -ItemType Directory -Path $dest | Out-Null

Write-Host "Copying files to temporary folder: $dest"

# Copy everything except .git
Get-ChildItem -Path . -Force | Where-Object { $_.Name -ne '.git' -and $_.Name -ne $tmp } | ForEach-Object {
  $target = Join-Path -Path $dest -ChildPath $_.Name
  if ($_.PSIsContainer) {
    Copy-Item -Path $_.FullName -Destination $target -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Copy-Item -Path $_.FullName -Destination $target -Force -ErrorAction SilentlyContinue
  }
}

Push-Location $tmp
try {
  git init
  git remote add $RemoteName $remoteUrl
  git checkout -b $Branch
  git add .
  git commit -m "Deploy: nested under GuildUI/ [automated]" 2>$null
  Write-Host "Force-pushing to $remoteUrl#$Branch"
  git push -u $RemoteName $Branch --force
} finally {
  Pop-Location
}

Write-Host "Deployment complete. Temporary folder: $tmp"
