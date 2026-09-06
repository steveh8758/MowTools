# ============================================================
# Functions 版本
# ============================================================

$script:MowFunctionsVersion = "1.0.0"

# ============================================================
# Functions
#  -> 名稱以底線開頭，不對外公開。
# ============================================================

# ============================================================
# Port 相關
# ============================================================

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
        Select-Object `
            -ExpandProperty OwningProcess `
            -Unique

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

