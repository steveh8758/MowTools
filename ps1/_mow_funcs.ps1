# ============================================================
# MowTools
# 臨時 PowerShell 工具箱
# ============================================================

$Prefix = "mt"
$Version = "1.0.0"
$SourceUrl = "https://steveh.pages.dev/raw/ps/tools"


# ============================================================
# 移除已存在的舊版模組
# ============================================================

Remove-Module MowTools -Force -ErrorAction SilentlyContinue


# ============================================================
# 建立 MowTools 動態模組
# ============================================================

$module = New-Module `
    -Name MowTools `
    -ArgumentList $Prefix, $Version, $SourceUrl `
    -ScriptBlock {

    param(
        [string]$Prefix,
        [string]$Version,
        [string]$SourceUrl
    )

    $script:Version = $Version
    $script:SourceUrl = $SourceUrl


    # ========================================================
    # 記錄模組原本已存在的 Function
    # ========================================================

    $functionsBefore = @(
        Get-ChildItem Function:\ |
            Select-Object -ExpandProperty Name
    )


    # ========================================================
    # Port 相關
    # ========================================================

    function fp([int]$Port) {
        $conn = Get-NetTCPConnection `
            -LocalPort $Port `
            -State Listen `
            -ErrorAction SilentlyContinue

        if (-not $conn) {
            Write-Host "Port $Port is free."
            return
        }

        $conn |
            Select-Object `
                LocalAddress,
                LocalPort,
                OwningProcess,
                @{
                    Name = "ProcessName"
                    Expression = {
                        (
                            Get-Process `
                                -Id $_.OwningProcess `
                                -ErrorAction SilentlyContinue
                        ).ProcessName
                    }
                },
                @{
                    Name = "CommandLine"
                    Expression = {
                        (
                            Get-CimInstance `
                                Win32_Process `
                                -Filter "ProcessId = $($_.OwningProcess)"
                        ).CommandLine
                    }
                } |
            Format-Table -AutoSize -Wrap
    }


    function kp([int]$Port) {
        $processIds = Get-NetTCPConnection `
            -LocalPort $Port `
            -State Listen `
            -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique

        if (-not $processIds) {
            Write-Host "Port $Port is free."
            return
        }

        foreach ($processId in $processIds) {
            try {
                Stop-Process `
                    -Id $processId `
                    -Force `
                    -ErrorAction Stop

                Write-Host "Killed PID $processId on port $Port."
            }
            catch {
                Write-Host "Failed to kill PID $processId : $($_.Exception.Message)"
            }
        }
    }


    # ========================================================
    # MowTools 管理
    # ========================================================

    function ver {
        Write-Host "MowTools v$script:Version"
    }


    function reload {
        Write-Host "Reloading MowTools..."

        try {
            # 先下載新版，避免網路失敗後舊版已經被移除
            $source = Invoke-RestMethod `
                $script:SourceUrl `
                -ErrorAction Stop

            # 先檢查 PowerShell 語法是否合法
            $newScript = [scriptblock]::Create($source)
        }
        catch {
            Write-Host "Reload failed: $($_.Exception.Message)"
            return
        }

        # 下載及語法檢查成功後才移除目前版本
        Remove-Module MowTools `
            -Force `
            -ErrorAction SilentlyContinue

        try {
            & $newScript
        }
        catch {
            Write-Host "Reload failed: $($_.Exception.Message)"
        }
    }


    function clear {
        Write-Host "MowTools unloaded."

        Remove-Module MowTools `
            -Force `
            -ErrorAction SilentlyContinue
    }


    # ========================================================
    # 以下為內部 Function
    # Function 名稱以底線開頭時，不會對外公開
    # ========================================================

    function _isPublicFunction([string]$Name) {
        return -not $Name.StartsWith("_")
    }


    # ========================================================
    # 自動尋找本次新增的 Function
    # ========================================================

    $functionsAfter = @(
        Get-ChildItem Function:\ |
            Select-Object -ExpandProperty Name
    )

    $commands = @(
        $functionsAfter |
            Where-Object {
                ($_ -notin $functionsBefore) -and
                (_isPublicFunction $_)
            }
    )


    # ========================================================
    # 根據 Prefix 自動建立公開命令
    # ========================================================

    if ([string]::IsNullOrWhiteSpace($Prefix)) {

        # Prefix 為空時，直接匯出原始 Function
        Export-ModuleMember -Function $commands
    }
    else {

        # Prefix 存在時，自動建立 Alias
        $aliases = @()

        foreach ($command in $commands) {
            $aliasName = "$Prefix-$command"

            Set-Alias `
                -Name $aliasName `
                -Value $command `
                -Scope Script

            $aliases += $aliasName
        }

        # 對外只公開帶 Prefix 的 Alias
        Export-ModuleMember -Alias $aliases
    }
}


# ============================================================
# 將 MowTools 載入目前 PowerShell Session
# ============================================================

$module |
    Import-Module `
        -Global `
        -Force


# ============================================================
# 顯示載入資訊
# ============================================================

if ([string]::IsNullOrWhiteSpace($Prefix)) {
    Write-Host "MowTools v$Version loaded."
}
else {
    Write-Host "MowTools v$Version loaded. Prefix: $Prefix-"
}