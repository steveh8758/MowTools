$ErrorActionPreference = "Stop"

# ============================================================
# Configuration
# ============================================================

$NodeVersion = "18.17.0"
$YarnVersion = "1.22.4"

$ProjectUrl = "https://github.com/steveh8758/GitCracken-zh_TW/raw/main/Data/GitkrakenCrack.zip"

# Custom Yarn command.
$Step7Script = "gitcracken"
$Step7Args = @("patcher")


# ============================================================
# Paths
# ============================================================

$TempRoot = Join-Path $env:TEMP "MOW_GitCracken"

$NodeZip = Join-Path $TempRoot "node.zip"
$NodeDir = Join-Path $TempRoot "node"
$NodeRoot = Join-Path $NodeDir "node-v$NodeVersion-win-x64"

$ProjectZip = Join-Path $TempRoot "GitCracken.zip"
$ProjectDir = Join-Path $TempRoot "GitCracken\GitCracken"

$Step7Dir = Join-Path `
    $TempRoot `
    "GitCracken\GitCracken\GitCracken"

$NpmPrefix = Join-Path $TempRoot "npm-global"
$NpmCache = Join-Path $TempRoot "npm-cache"
$YarnCache = Join-Path $TempRoot "yarn-cache"

$NpmCmd = Join-Path $NodeRoot "npm.cmd"
$YarnCmd = Join-Path $NpmPrefix "yarn.cmd"

$OriginalPath = $env:PATH
$OriginalLocation = (Get-Location).Path


# ============================================================
# Helper functions
# ============================================================

function Write-Step {
    param(
        [Parameter(Mandatory)]
        [int] $Current,

        [Parameter(Mandatory)]
        [int] $Total,

        [Parameter(Mandatory)]
        [string] $Message
    )

    Write-Host ""
    Write-Host "[$Current/$Total] $Message" -ForegroundColor Cyan
}


function Write-Info {
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    Write-Host $Message -ForegroundColor DarkGray
}


function Write-Success {
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    Write-Host $Message -ForegroundColor Green
}


function Invoke-Yarn {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    & $YarnCmd @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Yarn command failed: yarn $($Arguments -join ' ')"
    }
}


# ============================================================
# Main
# ============================================================

try {
    # ========================================================
    # 1. Prepare TEMP
    # ========================================================

    Write-Step 1 9 "Preparing temporary directory..."

    if (Test-Path $TempRoot) {
        Write-Host "Existing temporary directory detected." `
            -ForegroundColor Yellow

        Write-Info $TempRoot
        Write-Host "Existing downloads and caches will be reused." `
            -ForegroundColor Yellow
    }
    else {
        New-Item `
            -Path $TempRoot `
            -ItemType Directory `
            -Force | Out-Null

        Write-Success "Temporary directory created."
    }


    # ========================================================
    # 2. Prepare Node.js package
    # ========================================================

    Write-Step 2 9 "Preparing Node.js v$NodeVersion..."

    $NodeUrl = (
        "https://nodejs.org/dist/v{0}/node-v{0}-win-x64.zip" -f
        $NodeVersion
    )

    if (Test-Path $NpmCmd) {
        Write-Success "Existing portable Node.js found."
        Write-Info $NodeRoot
    }
    else {
        if (Test-Path $NodeZip) {
            Write-Host "Existing Node.js ZIP found." `
                -ForegroundColor Yellow

            Write-Info $NodeZip
        }
        else {
            Write-Host "Downloading Node.js..." `
                -ForegroundColor Yellow

            Invoke-WebRequest `
                -Uri $NodeUrl `
                -OutFile $NodeZip

            Write-Success "Node.js download complete."
        }
    }


    # ========================================================
    # 3. Prepare Node.js / npm / Yarn
    # ========================================================

    Write-Step 3 9 "Configuring Node.js, npm and Yarn..."

    if (-not (Test-Path $NpmCmd)) {
        if (Test-Path $NodeDir) {
            Remove-Item `
                -Path $NodeDir `
                -Recurse `
                -Force
        }

        Expand-Archive `
            -Path $NodeZip `
            -DestinationPath $NodeDir `
            -Force

        if (-not (Test-Path $NpmCmd)) {
            throw "npm.cmd not found after extraction: $NpmCmd"
        }

        Write-Success "Node.js extracted successfully."
    }

    # Configure temporary environment.
    $env:NPM_CONFIG_PREFIX = $NpmPrefix
    $env:NPM_CONFIG_CACHE = $NpmCache
    $env:YARN_CACHE_FOLDER = $YarnCache

    $env:PATH = (
        "$NodeRoot;" +
        "$NpmPrefix;" +
        "$OriginalPath"
    )

    Write-Host ""
    Write-Host "Node version:" -ForegroundColor DarkGray
    & "$NodeRoot\node.exe" --version

    # Check whether the requested Yarn version already exists.
    $InstallYarn = $true

    if (Test-Path $YarnCmd) {
        try {
            $ExistingYarnVersion = (
                & $YarnCmd --version 2>$null
            ).Trim()

            if ($ExistingYarnVersion -eq $YarnVersion) {
                $InstallYarn = $false

                Write-Success (
                    "Existing Yarn v$ExistingYarnVersion found."
                )
            }
            else {
                Write-Host (
                    "Existing Yarn version is " +
                    "$ExistingYarnVersion; " +
                    "v$YarnVersion is required."
                ) -ForegroundColor Yellow
            }
        }
        catch {
            $InstallYarn = $true
        }
    }

    if ($InstallYarn) {
        Write-Host ""
        Write-Host "Installing Yarn v$YarnVersion..." `
            -ForegroundColor Yellow

        & $NpmCmd install `
            --global `
            "yarn@$YarnVersion"

        if ($LASTEXITCODE -ne 0) {
            throw "Unable to install Yarn."
        }

        Write-Success "Yarn installation complete."
    }

    Write-Host ""
    Write-Host "Yarn version:" -ForegroundColor DarkGray
    & $YarnCmd --version


    # ========================================================
    # 4. Prepare project ZIP
    # ========================================================

    Write-Step 4 9 "Preparing project ZIP..."

    if (Test-Path $ProjectZip) {
        Write-Success "Existing project ZIP found."
        Write-Info $ProjectZip
    }
    else {
        Write-Host "Downloading project..." `
            -ForegroundColor Yellow

        Invoke-WebRequest `
            -Uri $ProjectUrl `
            -OutFile $ProjectZip

        Write-Success "Project download complete."
    }


    # ========================================================
    # 5. Re-extract project
    # ========================================================

    Write-Step 5 9 "Re-extracting project..."

    if (Test-Path $ProjectDir) {
        Write-Host "Removing existing extracted project..." `
            -ForegroundColor Yellow

        try {
            Remove-Item `
                -Path $ProjectDir `
                -Recurse `
                -Force
        }
        catch {
            throw (
                "Unable to remove existing project directory: " +
                "$ProjectDir`n" +
                "The directory may be in use by another process."
            )
        }

        if (Test-Path $ProjectDir) {
            throw "Project directory still exists: $ProjectDir"
        }

        Write-Success "Existing project removed."
    }

    New-Item `
        -Path $ProjectDir `
        -ItemType Directory `
        -Force | Out-Null

    Expand-Archive `
        -Path $ProjectZip `
        -DestinationPath $ProjectDir `
        -Force

    Write-Success "Project extracted successfully."


    # ========================================================
    # Locate package.json
    # ========================================================

    $PackageJson = Get-ChildItem `
        -Path $ProjectDir `
        -Filter "package.json" `
        -File `
        -Recurse |
        Select-Object -First 1

    if (-not $PackageJson) {
        throw (
            "package.json was not found " +
            "in the downloaded project."
        )
    }

    $WorkingDir = $PackageJson.Directory.FullName

    Write-Host ""
    Write-Host "Project directory:" -ForegroundColor DarkGray
    Write-Host $WorkingDir -ForegroundColor Gray

    Set-Location $WorkingDir


    # ========================================================
    # 6. yarn install
    # ========================================================

    Write-Step 6 9 "Running yarn install..."

    Invoke-Yarn @("install")

    Write-Success "yarn install completed."


    # ========================================================
    # 7. yarn build
    # ========================================================

    Write-Step 7 9 "Running yarn build..."

    Invoke-Yarn @("build")

    Write-Success "yarn build completed."


    # ========================================================
    # 8. Custom Yarn command
    # ========================================================

    Write-Step 8 9 "Running custom Yarn command..."

    if ($Step7Script) {
        if (-not (Test-Path $Step7Dir)) {
            throw "Custom command directory not found: $Step7Dir"
        }

        Write-Host "Working directory:" `
            -ForegroundColor DarkGray

        Write-Host $Step7Dir `
            -ForegroundColor Gray

        Push-Location $Step7Dir

        try {
            $YarnArgs = @($Step7Script) + $Step7Args

            Write-Host ""
            Write-Host (
                "Running: yarn " +
                ($YarnArgs -join " ")
            ) -ForegroundColor Yellow

            Write-Host ""

            Invoke-Yarn $YarnArgs
        }
        finally {
            Pop-Location
        }

        Write-Success "Custom Yarn command completed."
    }
    else {
        Write-Host "No custom Yarn command configured." `
            -ForegroundColor Yellow
    }


    # ========================================================
    # Finished
    # ========================================================

    Write-Host ""
    Write-Host "========================================" `
        -ForegroundColor Green

    Write-Host " All commands completed successfully." `
        -ForegroundColor Green

    Write-Host "========================================" `
        -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "========================================" `
        -ForegroundColor Red

    Write-Host " ERROR" `
        -ForegroundColor Red

    Write-Host "========================================" `
        -ForegroundColor Red

    Write-Host ""
    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    Write-Host ""
    Write-Host (
        "Temporary files are available for inspection."
    ) -ForegroundColor Yellow
}
finally {
    # ========================================================
    # Restore environment
    # ========================================================

    try {
        Set-Location $OriginalLocation
    }
    catch {
        # Ignore location restoration errors.
    }

    $env:PATH = $OriginalPath

    Remove-Item Env:NPM_CONFIG_PREFIX `
        -ErrorAction SilentlyContinue

    Remove-Item Env:NPM_CONFIG_CACHE `
        -ErrorAction SilentlyContinue

    Remove-Item Env:YARN_CACHE_FOLDER `
        -ErrorAction SilentlyContinue


    # ========================================================
    # 9. Cleanup
    # ========================================================

    if (Test-Path $TempRoot) {
        Write-Step 9 9 "Temporary file cleanup..."

        Write-Host "Temporary directory:" `
            -ForegroundColor DarkGray

        Write-Host $TempRoot `
            -ForegroundColor Gray

        Write-Host ""

        $Confirm = Read-Host (
            "Delete all temporary files? [y/N]"
        )

        if ($Confirm -match '^[Yy]$') {
            Write-Host ""
            Write-Host "Removing temporary files..." `
                -ForegroundColor Yellow

            try {
                Remove-Item `
                    -Path $TempRoot `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop
            }
            catch {
                Write-Host ""
                Write-Host (
                    "Some temporary files could not be removed."
                ) -ForegroundColor Red

                Write-Host $TempRoot `
                    -ForegroundColor Yellow
            }

            if (Test-Path $TempRoot) {
                Write-Host ""
                Write-Host (
                    "Temporary directory still exists."
                ) -ForegroundColor Yellow
            }
            else {
                Write-Host ""
                Write-Success "Cleanup complete."
            }
        }
        else {
            Write-Host ""
            Write-Host "Cleanup skipped." `
                -ForegroundColor Yellow

            Write-Host "Temporary files kept at:" `
                -ForegroundColor DarkGray

            Write-Host $TempRoot `
                -ForegroundColor Gray
        }
    }
}