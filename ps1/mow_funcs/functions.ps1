# ============================================================
# Functions 版本
# ============================================================

$script:MowFunctionsVersion = "1.0.0"

# ============================================================
# Console 顏色
# ============================================================
# success = Green, info = Cyan, warning = Yellow, error = Red
#
# _mow_write_success "Done."
# _mow_write_info "Loading..."
# _mow_write_warning "Warning."
# _mow_write_error "Failed."
#
# Use -NoNewline to continue output on the same line.

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
        _mow_write_success `
            -Message "Port $Port is free."

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
        _mow_write_success `
            -Message "Port $Port is free."

        return
    }

    foreach ($processId in $processIds) {
        try {
            Stop-Process `
                -Id $processId `
                -Force `
                -ErrorAction Stop

            _mow_write_success `
                -Message "Killed PID $processId on port $Port."
        }
        catch {
            _mow_write_error `
                -Message "Failed to kill PID $processId : " `
                -NoNewline

            Write-Host $_.Exception.Message
        }
    }
}