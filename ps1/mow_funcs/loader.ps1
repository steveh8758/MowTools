param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Prefix,

    [Parameter(Mandatory = $true)]
    [string]$BootstrapUrl,

    [Parameter(Mandatory = $true)]
    [string]$LoaderUrl,

    [Parameter(Mandatory = $true)]
    [string]$FunctionsUrl
)


# ============================================================
# Loader 版本
# ============================================================

$MowLoaderVersion = "1.0.0"


# ============================================================
# Console Helpers
# ============================================================

$consoleHelpers = {

    function _mow_write {
        param(
            [string]$Message,
            [ConsoleColor]$Color,
            [switch]$NoNewline
        )

        Write-Host `
            $Message `
            -ForegroundColor $Color `
            -NoNewline:$NoNewline
    }


    function _mow_write_success {
        param(
            [string]$Message,
            [switch]$NoNewline
        )

        _mow_write `
            -Message $Message `
            -Color Green `
            -NoNewline:$NoNewline
    }


    function _mow_write_info {
        param(
            [string]$Message,
            [switch]$NoNewline
        )

        _mow_write `
            -Message $Message `
            -Color Cyan `
            -NoNewline:$NoNewline
    }


    function _mow_write_warning {
        param(
            [string]$Message,
            [switch]$NoNewline
        )

        _mow_write `
            -Message $Message `
            -Color Yellow `
            -NoNewline:$NoNewline
    }


    function _mow_write_error {
        param(
            [string]$Message,
            [switch]$NoNewline
        )

        _mow_write `
            -Message $Message `
            -Color Red `
            -NoNewline:$NoNewline
    }


    function _mow_write_label {
        param(
            [string]$Label,
            [string]$Value
        )

        _mow_write_info `
            -Message $Label `
            -NoNewline

        Write-Host $Value
    }
}


# 載入 Console Helpers 給 Loader 使用
. $consoleHelpers


# ============================================================
# 檢查 Prefix
# ============================================================

if (
    -not [string]::IsNullOrWhiteSpace($Prefix) -and
    $Prefix -notmatch '^[A-Za-z0-9_]+$'
) {
    Write-Host "Invalid prefix: $Prefix"
    return
}


# ============================================================
# 下載 Functions
# ============================================================

try {
    $separator = "?"

    if ($FunctionsUrl.Contains("?")) {
        $separator = "&"
    }

    $functionsRequestUrl = (
        $FunctionsUrl +
        $separator +
        "_=" +
        (Get-Date -Format "yyyyMMddHHmmssfff")
    )

    $functionsSource = Invoke-RestMethod `
        -Uri $functionsRequestUrl `
        -ErrorAction Stop

    # 先檢查 Functions 語法，避免錯誤版本取代目前版本
    [scriptblock]::Create(
        [string]$functionsSource
    ) | Out-Null
}
catch {
    Write-Host "Failed to load MowTools functions: $($_.Exception.Message)"
    return
}


# ============================================================
# 建立新版 MowTools Module
# 建立失敗時，不會移除目前已載入的舊版
# ============================================================

try {
    $newModule = New-Module `
        -Name "MowTools" `
        -ArgumentList @(
            $Prefix,
            $MowLoaderVersion,
            $BootstrapUrl,
            $LoaderUrl,
            $FunctionsUrl,
            [string]$functionsSource
        ) `
        -ScriptBlock {

        param(
            [string]$Prefix,
            [string]$LoaderVersion,
            [string]$BootstrapUrl,
            [string]$LoaderUrl,
            [string]$FunctionsUrl,
            [string]$FunctionsSource
        )

        $script:MowPrefix = $Prefix
        $script:MowLoaderVersion = $LoaderVersion
        $script:MowBootstrapUrl = $BootstrapUrl
        $script:MowLoaderUrl = $LoaderUrl
        $script:MowFunctionsUrl = $FunctionsUrl
        $script:MowFunctionsVersion = "unknown"


        # ========================================================
        # 記錄載入前已有的 Function
        # ========================================================

        $functionsBefore = @(
            Get-ChildItem Function:\ |
                Select-Object -ExpandProperty Name
        )


        # ========================================================
        # 載入使用者 Functions
        # ========================================================

        $functionsScript = [scriptblock]::Create(
            $FunctionsSource
        )

        . $functionsScript


        # ========================================================
        # 自動找出 Functions 檔案新增的公開 Function
        # 底線開頭的 Function 視為內部使用，不會公開
        # ========================================================

        $functionsAfter = @(
            Get-ChildItem Function:\ |
                Select-Object -ExpandProperty Name
        )

        $toolFunctions = @(
            $functionsAfter |
                Where-Object {
                    ($_ -notin $functionsBefore) -and
                    (-not $_.StartsWith("_"))
                }
        )


        # ========================================================
        # 檢查保留名稱
        # ========================================================

        $reservedNames = @(
            "ver",
            "reload",
            "clear"
        )

        foreach ($name in $toolFunctions) {
            if ($name -in $reservedNames) {
                throw "'$name' is reserved by MowTools."
            }
        }


        # ========================================================
        # MowTools 內建管理功能
        # ========================================================

        function _mow_ver {
            $prefixText = "<none>"

            if (-not [string]::IsNullOrWhiteSpace($script:MowPrefix)) {
                $prefixText = "$($script:MowPrefix)-"
            }

            Write-Host "MowTools"
            Write-Host "Loader    : $script:MowLoaderVersion"
            Write-Host "Functions : $script:MowFunctionsVersion"
            Write-Host "Prefix    : $prefixText"
        }


        function _mow_reload {
            Write-Host "Reloading MowTools..."

            try {
                $separator = "?"

                if ($script:MowBootstrapUrl.Contains("?")) {
                    $separator = "&"
                }

                $bootstrapRequestUrl = (
                    $script:MowBootstrapUrl +
                    $separator +
                    "_=" +
                    (Get-Date -Format "yyyyMMddHHmmssfff")
                )

                $bootstrapSource = Invoke-RestMethod `
                    -Uri $bootstrapRequestUrl `
                    -ErrorAction Stop

                $bootstrapScript = [scriptblock]::Create(
                    [string]$bootstrapSource
                )

                & $bootstrapScript
            }
            catch {
                Write-Host "Reload failed: $($_.Exception.Message)"
            }
        }


        function _mow_clear {
            Write-Host "MowTools unloaded."

            Remove-Module `
                -Name "MowTools" `
                -Force `
                -ErrorAction SilentlyContinue
        }


        # ========================================================
        # 建立公開命令
        # Prefix 空白時保留原名稱，有 Prefix 時自動加上前綴
        # ========================================================

        $publicFunctions = @()

        foreach ($name in $toolFunctions) {
            if ([string]::IsNullOrWhiteSpace($Prefix)) {
                $publicFunctions += $name
                continue
            }

            $publicName = "$Prefix-$name"

            $scriptBlock = (
                Get-Item "Function:\$name"
            ).ScriptBlock

            Set-Item `
                -Path "Function:\$publicName" `
                -Value $scriptBlock

            $publicFunctions += $publicName
        }


        # ========================================================
        # 建立管理命令
        # ========================================================

        $managementCommands = @{
            "ver" = "_mow_ver"
            "reload" = "_mow_reload"
            "clear" = "_mow_clear"
        }

        foreach ($name in $managementCommands.Keys) {
            if ([string]::IsNullOrWhiteSpace($Prefix)) {
                $publicName = $name
            }
            else {
                $publicName = "$Prefix-$name"
            }

            $targetName = $managementCommands[$name]

            $scriptBlock = (
                Get-Item "Function:\$targetName"
            ).ScriptBlock

            Set-Item `
                -Path "Function:\$publicName" `
                -Value $scriptBlock

            $publicFunctions += $publicName
        }


        # ========================================================
        # 只公開 MowTools 對外命令
        # ========================================================

        Export-ModuleMember `
            -Function $publicFunctions
    } `
    -ErrorAction Stop
}
catch {
    Write-Host "Failed to create MowTools: $($_.Exception.Message)"
    return
}


# ============================================================
# 新版建立成功後才移除舊版
# ============================================================

Remove-Module `
    -Name "MowTools" `
    -Force `
    -ErrorAction SilentlyContinue


# ============================================================
# 載入新版
# ============================================================

try {
    $newModule |
        Import-Module `
            -Global `
            -Force `
            -DisableNameChecking `
            -ErrorAction Stop
}
catch {
    Write-Host "Failed to import MowTools: $($_.Exception.Message)"
    return
}


# ============================================================
# 顯示載入結果
# ============================================================

if ([string]::IsNullOrWhiteSpace($Prefix)) {
    Write-Host "MowTools loaded."
}
else {
    Write-Host "MowTools loaded. Prefix: $Prefix-"
}
