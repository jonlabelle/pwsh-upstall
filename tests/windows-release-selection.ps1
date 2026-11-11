$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '../pwsh-upstall-windows.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0)
{
    throw "Failed to parse $scriptPath : $($parseErrors -join '; ')"
}

# Load the nested release helpers without invoking the installer.
foreach ($name in @('Remove-VersionPrefix', 'Invoke-GitHubApi', 'Get-SemVerSelectorParts', 'Get-SemVerRelease', 'Get-Release', 'Select-Asset'))
{
    $definition = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true)
    if (-not $definition)
    {
        throw "Function not found: $name"
    }
    . ([scriptblock]::Create($definition.Extent.Text))
}

function Get-GitHubToken { return $null }

function Invoke-CompatRestMethod
{
    param([hashtable]$Parameters)

    if ($Parameters.Uri -eq "$apiBase/releases?per_page=100")
    {
        # Invoke-RestMethod emits a top-level JSON array as one pipeline object.
        Write-Output -NoEnumerate $script:releaseFixture
        return
    }

    foreach ($release in $script:releaseFixture)
    {
        if ($Parameters.Uri -eq "$apiBase/releases/tags/$($release.tag_name)")
        {
            return $release
        }
    }

    throw "Unexpected API request: $($Parameters.Uri)"
}

function New-TestRelease
{
    param(
        [string]$Tag,
        [string]$Arch,
        [string]$Extension,
        [bool]$Draft = $false,
        [bool]$Prerelease = $false
    )

    $name = "PowerShell-$($Tag.TrimStart('v'))-win-$Arch.$Extension"
    return [PSCustomObject]@{
        tag_name = $Tag
        draft = $Draft
        prerelease = $Prerelease
        assets = @(
            [PSCustomObject]@{
                name = $name
                browser_download_url = "https://example.test/$name"
            }
        )
    }
}

function Assert-SelectedRelease
{
    param([string]$Selector, [string]$Arch, [string]$ExpectedTag, [string]$ExpectedType)

    $release = Get-Release -TagName $Selector -Arch $Arch
    if ($release.tag_name -ne $ExpectedTag)
    {
        throw "Selector [$Selector] for [$Arch] chose [$($release.tag_name)] instead of [$ExpectedTag]."
    }

    $asset = Select-Asset -Release $release -Arch $Arch
    if ($asset.InstallerType -ne $ExpectedType)
    {
        throw "Selector [$Selector] chose [$($asset.InstallerType)] instead of [$ExpectedType]."
    }
}

$apiBase = 'https://api.github.com/repos/PowerShell/PowerShell'
$script:releaseFixture = @(
    New-TestRelease -Tag 'v7.6.9' -Arch 'x64' -Extension 'msi'
    New-TestRelease -Tag 'v7.6.10' -Arch 'x64' -Extension 'msi'
    New-TestRelease -Tag 'v7.7.0' -Arch 'x64' -Extension 'zip'
    New-TestRelease -Tag 'v7.8.0' -Arch 'arm64' -Extension 'zip'
    New-TestRelease -Tag 'v7.9.0' -Arch 'x64' -Extension 'zip' -Draft $true
    New-TestRelease -Tag 'v7.10.0' -Arch 'x64' -Extension 'zip' -Prerelease $true
    New-TestRelease -Tag 'v7.11.0-preview.1' -Arch 'x64' -Extension 'zip' -Prerelease $true
)

Assert-SelectedRelease -Selector 'v7.6' -Arch 'x64' -ExpectedTag 'v7.6.10' -ExpectedType 'msi'
Assert-SelectedRelease -Selector 'v7' -Arch 'x64' -ExpectedTag 'v7.7.0' -ExpectedType 'zip'
Assert-SelectedRelease -Selector 'v7' -Arch 'arm64' -ExpectedTag 'v7.8.0' -ExpectedType 'zip'
Assert-SelectedRelease -Selector 'v7.7.0' -Arch 'x64' -ExpectedTag 'v7.7.0' -ExpectedType 'zip'
Assert-SelectedRelease -Selector 'v7.11.0-preview.1' -Arch 'x64' -ExpectedTag 'v7.11.0-preview.1' -ExpectedType 'zip'

$script:releaseFixture = @(New-TestRelease -Tag 'v7.7.0' -Arch 'x64' -Extension 'zip')
Assert-SelectedRelease -Selector 'v7.7' -Arch 'x64' -ExpectedTag 'v7.7.0' -ExpectedType 'zip'

$script:releaseFixture = @()
$missingReleaseError = $null
try
{
    $null = Get-Release -TagName 'v7.6' -Arch 'x64'
}
catch
{
    $missingReleaseError = $_.Exception.Message
}
if ($missingReleaseError -notlike 'Could not find a stable release matching selector*')
{
    throw "Expected a missing release error, got: $missingReleaseError"
}

Write-Host 'Windows release selector tests passed.'
