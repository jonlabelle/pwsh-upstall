#requires -RunAsAdministrator

<#
    .SYNOPSIS
        Install, upgrade, or uninstall Microsoft PowerShell on Windows from GitHub Releases.

    .DESCRIPTION
        PowerShell Desktop script to install, upgrade, or uninstall Microsoft PowerShell (Core) on Windows
        using official MSI packages from GitHub Releases. Supports both x86_64 and ARM64 architectures.

        IMPORTANT: Run this script from Windows PowerShell (powershell.exe), not PowerShell Core (pwsh.exe),
        to avoid process-in-use errors when upgrading an existing PowerShell Core installation.

    .PARAMETER Tag
        Select release by semver/tag:
        - v7      => latest 7.x.x (major track)
        - v7.5    => latest 7.5.x (minor track)
        - v7.5.4  => specific patch release
        - other tags (e.g., preview) are resolved exactly
        If omitted (or set to 'latest'), installs the latest stable release.
        Prereleases are supported only via explicit exact tag.

    .PARAMETER OutDir
        Save the downloaded MSI installer to the specified directory. If omitted, uses a temporary directory.

    .PARAMETER Keep
        Retain the MSI installer after installation. By default, the installer is deleted unless -OutDir is specified.

    .PARAMETER Force
        Reinstall even if the target version is already installed.

    .PARAMETER Check
        Only check if the installed version is up to date with the latest available release.

    .PARAMETER Uninstall
        Remove PowerShell using the MSI uninstall string from the Windows registry.

    .PARAMETER SkipChecksum
        Skip SHA256 checksum verification (not recommended).

    .PARAMETER WhatIf
        Preview actions without making any changes to the system.

    .EXAMPLE
        powershell -File .\pwsh-upstall-windows.ps1
        Install the latest stable PowerShell release.

    .EXAMPLE
        powershell -File .\pwsh-upstall-windows.ps1 -Tag v7
        Install the latest PowerShell release in major line 7.x.

    .EXAMPLE
        powershell -File .\pwsh-upstall-windows.ps1 -Tag v7.5
        Install the latest PowerShell release in minor line 7.5.x.

    .EXAMPLE
        powershell -File .\pwsh-upstall-windows.ps1 -Tag v7.5.4
        Install specific PowerShell patch release 7.5.4.

    .EXAMPLE
        powershell -File .\pwsh-upstall-windows.ps1 -Force
        Reinstall the latest version even if already installed.

    .EXAMPLE
        powershell -File .\pwsh-upstall-windows.ps1 -Check
        Check if PowerShell is up to date.

    .EXAMPLE
        powershell -File .\pwsh-upstall-windows.ps1 -Uninstall
        Uninstall PowerShell from the system.

    .EXAMPLE
        powershell -File .\pwsh-upstall-windows.ps1 -WhatIf
        Preview what would happen without making any changes.

    .NOTES
        Filename: pwsh-upstall-windows.ps1

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
        Prereleases are supported only via explicit exact tag
        (default/latest/major/minor selection is stable-only).

        Author: Jon LaBelle
        Source: https://github.com/jonlabelle/pwsh-upstall/blob/main/pwsh-upstall-windows.ps1

    .LINK
        https://github.com/PowerShell/PowerShell/releases

    .LINK
        https://github.com/jonlabelle/pwsh-upstall/blob/main/pwsh-upstall-windows.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Tag,
    [string]$OutDir,
    [switch]$Keep,
    [switch]$Force,
    [switch]$Check,
    [switch]$Uninstall,
    [switch]$SkipChecksum
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoOwner = 'PowerShell'
$repoName = 'PowerShell'
$apiBase = "https://api.github.com/repos/$repoOwner/$repoName"

function Write-Info
{
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Warn
{
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Success
{
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

if ($Check -and ($Tag -or $OutDir -or $Keep -or $Force -or $Uninstall -or $SkipChecksum))
{
    Write-Error 'The -Check option cannot be combined with install/uninstall options.'
    exit 1
}

function Test-NetworkConnectivity
{
    # Skip network check in WhatIf mode to allow preview without connectivity
    if ($WhatIfPreference)
    {
        return $true
    }

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
    $arch = $env:PROCESSOR_ARCHITECTURE
    switch ($arch)
    {
        'AMD64' { return 'x64' }
        'x86_64' { return 'x64' }
        'ARM64' { return 'arm64' }
        default { throw "Unsupported architecture: $arch" }
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

function Invoke-GitHubApi
{
    param([Parameter(Mandatory = $true)][string]$Url)

    Write-Verbose "Fetching release metadata: $Url"
    $params = @{
        Uri = $Url
        UseBasicParsing = $true
    }

    # Use GitHub token if available (avoids rate limiting in CI environments)
    if ($env:GITHUB_TOKEN)
    {
        $params['Headers'] = @{ Authorization = "Bearer $env:GITHUB_TOKEN" }
    }

    Invoke-RestMethod @params
}

function Get-SemVerSelectorParts
{
    param([string]$Selector)

    if (-not $Selector)
    {
        return $null
    }

    $normalized = $Selector.Trim().TrimStart('v', 'V')
    if ($normalized -notmatch '^\d+(\.\d+){0,2}$')
    {
        return $null
    }

    return @($normalized.Split('.'))
}

function Get-SemVerRelease
{
    param(
        [string[]]$SelectorParts,
        [string]$Arch
    )

    $suffix = "win-$Arch.msi"
    $selectorText = $SelectorParts -join '.'
    $releases = @(Invoke-GitHubApi -Url "$apiBase/releases?per_page=100")
    $matching = @()

    foreach ($release in $releases)
    {
        if ($release.draft -or $release.prerelease)
        {
            continue
        }

        $tag = [string]$release.tag_name
        $tagMatch = [regex]::Match($tag, '^v?(\d+)\.(\d+)\.(\d+)$')
        if (-not $tagMatch.Success)
        {
            continue
        }

        $major = [int]$tagMatch.Groups[1].Value
        $minor = [int]$tagMatch.Groups[2].Value
        $patch = [int]$tagMatch.Groups[3].Value

        if ($SelectorParts.Count -eq 1)
        {
            if ($major -ne [int]$SelectorParts[0]) { continue }
        }
        elseif ($SelectorParts.Count -eq 2)
        {
            if ($major -ne [int]$SelectorParts[0] -or $minor -ne [int]$SelectorParts[1]) { continue }
        }
        else
        {
            continue
        }

        $hasAsset = @($release.assets | Where-Object { $_.browser_download_url -like "*$suffix" }).Count -gt 0
        if (-not $hasAsset)
        {
            continue
        }

        $matching += [PSCustomObject]@{
            Release = $release
            Version = [Version]"$major.$minor.$patch"
        }
    }

    if (-not $matching)
    {
        throw "Could not find a stable release matching selector [$selectorText] with a $suffix asset."
    }

    return ($matching | Sort-Object -Property Version -Descending | Select-Object -First 1).Release
}

function Get-Release
{
    param(
        [string]$TagName,
        [string]$Arch
    )

    if (-not $TagName -or $TagName -match '^(?i)latest$')
    {
        return Invoke-GitHubApi -Url "$apiBase/releases/latest"
    }

    $selectorParts = Get-SemVerSelectorParts -Selector $TagName
    if ($selectorParts -and ($selectorParts.Count -eq 1 -or $selectorParts.Count -eq 2))
    {
        Write-Verbose "Resolving semver selector: $TagName"
        return Get-SemVerRelease -SelectorParts $selectorParts -Arch $Arch
    }

    if ($selectorParts -and $selectorParts.Count -eq 3)
    {
        $normalizedTag = 'v' + ($selectorParts -join '.')
        return Invoke-GitHubApi -Url "$apiBase/releases/tags/$normalizedTag"
    }

    return Invoke-GitHubApi -Url "$apiBase/releases/tags/$TagName"
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

if ($Check)
{
    Write-Info 'Checking network connectivity...'
    if (-not (Test-NetworkConnectivity))
    {
        exit 1
    }

    $release = Get-Release -TagName $null -Arch $arch
    $null = Select-Asset -Release $release -Arch $arch

    $releaseTag = $release.tag_name
    $latestVersion = $releaseTag.TrimStart('v')

    if (-not $latestVersion)
    {
        Write-Error 'Could not determine latest PowerShell release tag.'
        exit 1
    }

    $installed = Get-InstalledPwshVersion
    if (-not $installed)
    {
        Write-Warn "PowerShell is not installed. Latest available: $latestVersion"
        exit 2
    }

    $cmp = Compare-SemanticVersion -Version1 $installed -Version2 $latestVersion
    if ($cmp -eq 0)
    {
        Write-Success "PowerShell $installed is up to date (latest: $latestVersion)."
        exit 0
    }
    elseif ($cmp -lt 0)
    {
        Write-Warn "Update available: installed $installed -> latest $latestVersion."
        exit 1
    }
    else
    {
        Write-Warn "Installed version $installed is newer than latest release $latestVersion."
        exit 0
    }
}

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
            Write-Warning '  powershell -File .\pwsh-upstall-windows.ps1'
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
        Write-Warn 'No PowerShell install found via MSI uninstall entries.'
        return
    }
    Write-Info "Found PowerShell install: $($info.DisplayName)"
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

        # Check for user-specific directories that may need manual cleanup
        $userDirs = @()
        $docsPath = Join-Path $env:USERPROFILE 'Documents\PowerShell'
        $localPath = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerShell'
        $roamingPath = Join-Path $env:APPDATA 'Microsoft\PowerShell'

        if (Test-Path $docsPath) { $userDirs += $docsPath }
        if (Test-Path $localPath) { $userDirs += $localPath }
        if (Test-Path $roamingPath) { $userDirs += $roamingPath }

        if ($userDirs.Count -gt 0)
        {
            Write-Host ''
            Write-Warn 'Note: The following user-specific directories still exist and may be removed manually:'
            foreach ($dir in $userDirs)
            {
                Write-Warn "  $dir"
            }
            Write-Info 'To remove them, run: Remove-Item -Recurse -Force ~\Documents\PowerShell, $env:LOCALAPPDATA\Microsoft\PowerShell, $env:APPDATA\Microsoft\PowerShell'
        }
    }
    return
}

Write-Info 'Checking network connectivity...'
if (-not (Test-NetworkConnectivity))
{
    exit 1
}

$release = Get-Release -TagName $Tag -Arch $arch
$assetInfo = Select-Asset -Release $release -Arch $arch
$asset = $assetInfo.Asset
$shaAsset = $assetInfo.ShaAsset
$releaseTag = $release.tag_name
$targetVersion = $releaseTag.TrimStart('v')

Write-Info "Selected PowerShell release: $releaseTag"
Write-Info "Selected installer: $($asset.name)"
Write-Info "Download URL: $($asset.browser_download_url)"

$dlDir = if ($OutDir)
{
    $OutDir
}
else
{
    Join-Path $env:TEMP ('pwsh-upstall-' + [guid]::NewGuid())
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
            Write-Warn "PowerShell $installed is already installed; use -Force to reinstall."
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
        Write-Info 'Downloading checksum file...'
        if ($PSCmdlet.ShouldProcess($shaPath, 'Download SHA256 checksum'))
        {
            Invoke-WebRequest -Uri $shaAsset.browser_download_url -OutFile $shaPath
        }

        Write-Info 'Verifying SHA256 checksum...'
        $expectedSha = (Get-Content $shaPath -Raw).Split()[0]
        $actualSha = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash

        if ($expectedSha -ne $actualSha)
        {
            Write-Error 'SHA256 checksum verification failed!'
            Write-Error "  Expected: $expectedSha"
            Write-Error "  Got:      $actualSha"
            exit 1
        }
        Write-Success 'SHA256 checksum verified successfully'
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
        Write-Success "PowerShell $targetVersion installed successfully"
    }
}
finally
{
    if (-not $Keep -and -not $OutDir)
    {
        if ($PSCmdlet.ShouldProcess($dlDir, 'Clean up downloaded installer'))
        {
            Remove-Item -Recurse -Force $dlDir -ErrorAction SilentlyContinue
        }
    }
}

Write-Success 'Done. Verify with: pwsh -v'
