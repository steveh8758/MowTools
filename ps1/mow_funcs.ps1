# === Port 相關 ===

function fp([int]$Port) {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, OwningProcess,
        @{Name="ProcessName"; Expression={
            (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
        }},
        @{Name="CommandLine"; Expression={
            (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.OwningProcess)").CommandLine
        }} |
        Format-Table -AutoSize -Wrap
}

function kp([int]$Port) {
    $pids = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique

    if (-not $pids) {
        Write-Host "Port $Port is free."
        return
    }

    foreach ($processId in $pids) {
        Stop-Process -Id $processId -Force
        Write-Host "Killed PID $processId on port $Port."
    }
}