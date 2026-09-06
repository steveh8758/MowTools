# ============================================================
# MowTools 入口設定
# ============================================================

$Prefix = "mt"
$CommandSeparator = "."

$RepositoryRawUrl = "https://raw.githubusercontent.com/steveh8758/MowTools/main/ps1"

$BootstrapUrl = "$RepositoryRawUrl/mow_funcs.ps1"
$LoaderUrl = "$RepositoryRawUrl/mow_funcs/loader.ps1"
$FunctionsUrl = "$RepositoryRawUrl/mow_funcs/functions.ps1"


# ============================================================
# 啟動 MowTools
# 正常情況下不需要修改以下內容
# ============================================================

try {
    $separator = "?"

    if ($LoaderUrl.Contains("?")) {
        $separator = "&"
    }

    $loaderRequestUrl = (
        $LoaderUrl +
        $separator +
        "_=" +
        (Get-Date -Format "yyyyMMddHHmmssfff")
    )

    $loaderSource = Invoke-RestMethod `
        -Uri $loaderRequestUrl `
        -ErrorAction Stop

    $loaderScript = [scriptblock]::Create(
        [string]$loaderSource
    )

    & $loaderScript `
        -Prefix $Prefix `
        -CommandSeparator $CommandSeparator `
        -BootstrapUrl $BootstrapUrl `
        -LoaderUrl $LoaderUrl `
        -FunctionsUrl $FunctionsUrl
}
catch {
    Write-Host "Failed to start MowTools: $($_.Exception.Message)" `
        -ForegroundColor Red
}
