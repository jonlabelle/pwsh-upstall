#requires -RunAsAdministrator

<#
    .SYNOPSIS
        Install, upgrade, or uninstall Microsoft PowerShell on Windows from GitHub Releases.

    .DESCRIPTION
        PowerShell script to install, upgrade, or uninstall Microsoft PowerShell (Core) on Windows
        using official MSI packages from GitHub Releases. Supports both x86_64 and ARM64 architectures.

        IMPORTANT: Run this script from Windows PowerShell (powershell.exe), not PowerShell Core (pwsh.exe),
        to avoid process-in-use errors when upgrading an existing PowerShell Core installation.

    .PARAMETER Tag
        Install a specific GitHub release tag (e.g., v7.5.4). If omitted, installs the latest stable release.

    .PARAMETER OutDir
        Save the downloaded MSI installer to the specified directory. If omitted, uses a temporary directory.

    .PARAMETER KeepInstaller
        Retain the MSI installer after installation. By default, the installer is deleted unless -OutDir is specified.

    .PARAMETER Force
        Reinstall even if the target version is already installed.

    .PARAMETER Uninstall
        Remove PowerShell using the MSI uninstall string from the Windows registry.

    .PARAMETER SkipChecksum
        Skip SHA256 checksum verification (not recommended).

    .PARAMETER WhatIf
        Preview actions without making any changes to the system.

    .EXAMPLE
        powershell -File .\upstall-pwsh-windows.ps1
        Install the latest stable PowerShell release.

    .EXAMPLE
        powershell -File .\upstall-pwsh-windows.ps1 -Tag v7.5.4
        Install PowerShell version 7.5.4.

    .EXAMPLE
        powershell -File .\upstall-pwsh-windows.ps1 -Force
        Reinstall the latest version even if already installed.

    .EXAMPLE
        powershell -File .\upstall-pwsh-windows.ps1 -Uninstall
        Uninstall PowerShell from the system.

    .EXAMPLE
        powershell -File .\upstall-pwsh-windows.ps1 -WhatIf
        Preview what would happen without making any changes.

    .NOTES
        Filename: upstall-pwsh-windows.ps1

        Requirements:
        - Windows PowerShell 5.1+ with Administrator privileges
        - Internet connectivity to GitHub API
        - Sufficient disk space (~500MB recommended)

        The script automatically:
        - Detects system architecture (x64 or ARM64)
        - Downloads MSI installer from GitHub Releases
        - Verifies SHA256 checksums
        - Performs silent installation with msiexec
        - Validates disk space before installation
        - Uses semantic version comparison to detect upgrades

        Default behavior downloads the latest stable release (not preview/RC).

        Author: Jon LaBelle
        Source: https://github.com/jonlabelle/pwsh-upstall/blob/main/upstall-pwsh-windows.ps1

    .LINK
        https://github.com/PowerShell/PowerShell/releases

    .LINK
        https://github.com/jonlabelle/pwsh-upstall/blob/main/upstall-pwsh-windows.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Tag,
    [string]$OutDir,
    [switch]$KeepInstaller,
    [switch]$Force,
    [switch]$Uninstall,
    [switch]$SkipChecksum
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoOwner = 'PowerShell'
$repoName = 'PowerShell'
$apiBase = "https://api.github.com/repos/$repoOwner/$repoName"

function Test-NetworkConnectivity
{
    try
    {
        $null = Invoke-RestMethod -Uri 'https://api.github.com' -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        return $true
    }
    catch
    {
        Write-Error 'Cannot reach GitHub API. Check your internet connection.'
        return $false
    }
}

function Test-DiskSpace
{
    param(
        [string]$Path,
        [int]$RequiredMB = 500
    )

    try
    {
        $drive = [System.IO.Path]::GetPathRoot($Path)
        $driveInfo = Get-PSDrive -Name $drive.TrimEnd(':\') -ErrorAction Stop
        $availableMB = [math]::Round($driveInfo.Free / 1MB)

        Write-Verbose "Disk space check: ${availableMB}MB available on $drive"

        if ($availableMB -lt $RequiredMB)
        {
            Write-Error "Insufficient disk space. Required: ${RequiredMB}MB, Available: ${availableMB}MB"
            return $false
        }
        return $true
    }
    catch
    {
        Write-Warning "Could not determine disk space: $_"
        return $true
    }
}

function Compare-SemanticVersion
{
    param(
        [string]$Version1,
        [string]$Version2
    )

    try
    {
        $v1 = [version]($Version1 -replace '^v', '')
        $v2 = [version]($Version2 -replace '^v', '')

        if ($v1 -eq $v2) { return 0 }
        if ($v1 -lt $v2) { return -1 }
        return 1
    }
    catch
    {
        # Fallback to string comparison
        return [string]::Compare($Version1, $Version2)
    }
}

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

    $selected = $candidates |
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

    # Find corresponding SHA256 file
    $shaName = $selected.name + '.sha256'
    $shaAsset = $Release.assets | Where-Object { $_.name -eq $shaName } | Select-Object -First 1

    return [PSCustomObject]@{
        Asset = $selected
        ShaAsset = $shaAsset
    }
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

# Warn if running from pwsh (PowerShell Core) when trying to upgrade
if (-not $Uninstall)
{
    $currentShell = (Get-Process -Id $PID).ProcessName
    if ($currentShell -eq 'pwsh')
    {
        $installedVersion = Get-InstalledPwshVersion
        if ($installedVersion)
        {
            Write-Warning 'You are running this script from PowerShell Core (pwsh.exe).'
            Write-Warning "The MSI installer may fail with 'process in use' errors when upgrading."
            Write-Warning 'For best results, run this script from Windows PowerShell (powershell.exe):'
            Write-Warning '  powershell -File .\upstall-pwsh-windows.ps1'
            Write-Host ''
            Start-Sleep -Seconds 3
        }
    }
}

if ($Uninstall)
{
    $info = Get-PwshUninstallInfo
    if (-not $info -or -not $info.DisplayName -or -not $info.UninstallString)
    {
        Write-Host 'No PowerShell install found via MSI uninstall entries.' -ForegroundColor Yellow
        return
    }
    Write-Host "Found PowerShell install: $($info.DisplayName)"
    if ($PSCmdlet.ShouldProcess($info.DisplayName, "Uninstall via $($info.UninstallString)"))
    {
        $exe = $info.UninstallString
        $uninstallArgs = $null
        if ($exe -match '^\s*"?([^"\s]+\.exe)"?\s+(.*)$')
        {
            $exe = $matches[1]
            $uninstallArgs = $matches[2]
        }
        # Add quiet mode flags for automated uninstall
        if ($exe -match 'msiexec' -and $uninstallArgs -notmatch '/q[nrb]?')
        {
            $uninstallArgs += ' /qn /norestart'
        }
        $proc = Start-Process -FilePath $exe -ArgumentList $uninstallArgs -Wait -PassThru
        if ($proc.ExitCode -ne 0)
        {
            Write-Error "Uninstall failed with exit code: $($proc.ExitCode)"
            exit $proc.ExitCode
        }
    }
    return
}

Write-Host 'Checking network connectivity...'
if (-not (Test-NetworkConnectivity))
{
    exit 1
}

$release = Get-Release -TagName $Tag
$assetInfo = Select-Asset -Release $release -Arch $arch
$asset = $assetInfo.Asset
$shaAsset = $assetInfo.ShaAsset
$releaseTag = $release.tag_name
$targetVersion = $releaseTag.TrimStart('v')

Write-Host "Selected PowerShell release: $releaseTag"
Write-Host "Selected installer: $($asset.name)"
Write-Host "Download URL: $($asset.browser_download_url)"

$dlDir = if ($OutDir)
{
    $OutDir
}
else
{
    Join-Path $env:TEMP ('upstall-pwsh-' + [guid]::NewGuid())
}

if (-not $PSCmdlet.ShouldProcess($dlDir, 'Create download directory')) { return }

if (-not $Force)
{
    $installed = Get-InstalledPwshVersion
    if ($installed -and $targetVersion)
    {
        $cmp = Compare-SemanticVersion -Version1 $installed -Version2 $targetVersion
        if ($cmp -eq 0)
        {
            Write-Host "PowerShell $installed is already installed; use -Force to reinstall." -ForegroundColor Yellow
            return
        }
    }
}

if (-not (Test-DiskSpace -Path $env:ProgramFiles -RequiredMB 500))
{
    exit 1
}
New-Item -ItemType Directory -Force -Path $dlDir | Out-Null

try
{
    $installerPath = Join-Path $dlDir $asset.name

    if (Test-Path $installerPath)
    {
        Write-Verbose "Removing existing incomplete download: $installerPath"
        Remove-Item -Force $installerPath
    }

    if ($PSCmdlet.ShouldProcess($installerPath, 'Download installer'))
    {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installerPath
    }

    # Verify SHA256 checksum
    if (-not $SkipChecksum -and $shaAsset)
    {
        $shaPath = "$installerPath.sha256"
        Write-Host 'Downloading checksum file...'
        if ($PSCmdlet.ShouldProcess($shaPath, 'Download SHA256 checksum'))
        {
            Invoke-WebRequest -Uri $shaAsset.browser_download_url -OutFile $shaPath
        }

        Write-Host 'Verifying SHA256 checksum...'
        $expectedSha = (Get-Content $shaPath -Raw).Split()[0]
        $actualSha = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash

        if ($expectedSha -ne $actualSha)
        {
            Write-Error 'SHA256 checksum verification failed!'
            Write-Error "  Expected: $expectedSha"
            Write-Error "  Got:      $actualSha"
            exit 1
        }
        Write-Host 'SHA256 checksum verified successfully'
        Remove-Item -Force $shaPath
    }
    elseif (-not $SkipChecksum)
    {
        Write-Warning 'SHA256 file not found, skipping checksum verification'
    }

    $msiArgs = "/i `"$installerPath`" /qn /norestart"

    if ($PSCmdlet.ShouldProcess("msiexec.exe $msiArgs", "Install/upgrade PowerShell $targetVersion"))
    {
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
        if ($proc.ExitCode -ne 0)
        {
            Write-Error "MSI installation failed with exit code: $($proc.ExitCode)"
            exit $proc.ExitCode
        }
        Write-Host "PowerShell $targetVersion installed successfully"
    }
}
finally
{
    if (-not $KeepInstaller -and -not $OutDir)
    {
        if ($PSCmdlet.ShouldProcess($dlDir, 'Clean up downloaded installer'))
        {
            Remove-Item -Recurse -Force $dlDir -ErrorAction SilentlyContinue
        }
    }
}

Write-Host 'Done. Verify with: pwsh -v'
