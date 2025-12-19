#requires -RunAsAdministrator

<# upstall-pwsh-windows.ps1
   Update/install/uninstall Microsoft PowerShell (Core) on Windows from GitHub Releases.

   Usage examples:
     pwsh -File .\upstall-pwsh-windows.ps1
     pwsh -File .\upstall-pwsh-windows.ps1 -Tag v7.5.4
     pwsh -File .\upstall-pwsh-windows.ps1 -Force
     pwsh -File .\upstall-pwsh-windows.ps1 -Uninstall
     pwsh -File .\upstall-pwsh-windows.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Tag,
    [string]$OutDir,
    [switch]$KeepInstaller,
    [switch]$Force,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoOwner = 'PowerShell'
$repoName = 'PowerShell'
$apiBase = "https://api.github.com/repos/$repoOwner/$repoName"

function Get-OsArch
{
    switch ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)
    {
        'X64' { 'x64'; break }
        'Arm64' { 'arm64'; break }
        default { throw "Unsupported architecture: $PSItem" }
    }
}

function Get-PwshUninstallInfo
{
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($root in $roots)
    {
        if (-not (Test-Path $root)) { continue }
        foreach ($item in Get-ChildItem $root)
        {
            $p = Get-ItemProperty $item.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $p) { continue }
            if (($p.DisplayName -match '^PowerShell 7') -or ($p.DisplayName -match '^PowerShell\b' -and $p.DisplayName -match 'x64|arm64|7'))
            {
                if ($p.UninstallString)
                {
                    return [PSCustomObject]@{
                        DisplayName = $p.DisplayName
                        UninstallString = $p.UninstallString
                    }
                }
            }
        }
    }
    return $null
}

function Get-Release
{
    param([string]$TagName)
    $url = if ($TagName) { "$apiBase/releases/tags/$TagName" } else { "$apiBase/releases/latest" }
    Write-Verbose "Fetching release metadata: $url"
    Invoke-RestMethod -Uri $url -UseBasicParsing
}

function Select-Asset
{
    param(
        $Release,
        [string]$Arch
    )

    $suffix = "win-$Arch.msi"
    $candidates = @($Release.assets | Where-Object { $_.browser_download_url -like "*$suffix" })
    if (-not $candidates)
    {
        throw "Could not find a $suffix asset in release [$($Release.tag_name)]."
    }

    $candidates |
    Sort-Object -Descending -Property @{
        Expression = {
            $w = 0
            if ($_.name -match 'preview') { $w -= 10 }
            if ($_.name -match 'rc') { $w -= 5 }
            if ($_.name -match "^PowerShell-.*-$suffix$") { $w += 5 }
            $w
        }
    } |
    Select-Object -First 1
}

function Get-InstalledPwshVersion
{
    try
    {
        if (Get-Command pwsh -ErrorAction SilentlyContinue)
        {
            return (& pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null)
        }
    }
    catch { }
    return $null
}

$arch = Get-OsArch
Write-Verbose "Detected architecture: $arch"

if ($Uninstall)
{
    $info = Get-PwshUninstallInfo
    if (-not $info)
    {
        Write-Host 'No PowerShell install found via MSI uninstall entries.' -ForegroundColor Yellow
        return
    }
    Write-Host "Found PowerShell install: $($info.DisplayName)"
    if ($PSCmdlet.ShouldProcess($info.DisplayName, "Uninstall via $($info.UninstallString)"))
    {
        # Extract executable and arguments
        $exe = $info.UninstallString
        $uninstallArgs = $null
        if ($exe -match '^\s*"?([^"\s]+\.exe)"?\s+(.*)$')
        {
            $exe = $matches[1]
            $uninstallArgs = $matches[2]
        }
        Start-Process -FilePath $exe -ArgumentList $uninstallArgs -Wait
    }
    return
}

$release = Get-Release -TagName $Tag
$asset = Select-Asset -Release $release -Arch $arch
$releaseTag = $release.tag_name
$targetVersion = $releaseTag.TrimStart('v')

Write-Host "Selected PowerShell release: $releaseTag"
Write-Host "Selected installer: $($asset.name)"
Write-Host "Download URL: $($asset.browser_download_url)"

if (-not $Force)
{
    $installed = Get-InstalledPwshVersion
    if ($installed -and $targetVersion -and $installed -eq $targetVersion)
    {
        Write-Host "PowerShell $installed is already installed; use -Force to reinstall." -ForegroundColor Yellow
        return
    }
}

$dlDir = if ($OutDir)
{
    $OutDir
}
else
{
    Join-Path $env:TEMP ('upstall-pwsh-' + [guid]::NewGuid())
}

if (-not $PSCmdlet.ShouldProcess($dlDir, 'Create download directory')) { return }
New-Item -ItemType Directory -Force -Path $dlDir | Out-Null

$installerPath = Join-Path $dlDir $asset.name
if ($PSCmdlet.ShouldProcess($installerPath, 'Download installer'))
{
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installerPath
}

$msiArgs = "/i `"$installerPath`" /qn /norestart"
$needsElevation = -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($needsElevation)
{
    Write-Warning 'Installation requires elevation; please run this script from an elevated PowerShell session.'
}

if ($PSCmdlet.ShouldProcess("msiexec.exe $msiArgs", "Install/upgrade PowerShell $targetVersion"))
{
    Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait
}

if (-not $KeepInstaller -and -not $OutDir)
{
    if ($PSCmdlet.ShouldProcess($dlDir, 'Clean up downloaded installer'))
    {
        Remove-Item -Recurse -Force $dlDir
    }
}

Write-Host 'Done. Verify with: pwsh -v'
