$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "SilentlyContinue"
$WarningPreference = "SilentlyContinue"

function Get-SafeData {
    param([scriptblock]$Command)

    try {
        return & $Command
    }
    catch {
        return [ordered]@{
            error = $_.Exception.Message
        }
    }
}

function Get-PciId {
    param(
        [string]$HardwareId,
        [string]$Key
    )

    if ($HardwareId -match "$Key`_([0-9A-Fa-f]{4})") {
        return $Matches[1].ToUpper()
    }

    return $null
}

function Get-GpuChipVendor {
    param([string]$VendorId)

    $vendors = @{
        "10DE" = "NVIDIA"
        "1002" = "AMD"
        "8086" = "Intel"
        "1414" = "Microsoft"
        "15AD" = "VMware"
        "102B" = "Matrox"
        "17CB" = "Qualcomm"
    }

    if (-not $VendorId) {
        return $null
    }

    return $vendors[$VendorId]
}

function Get-GpuBoardVendor {
    param([string]$VendorId)

    # PCI subsystem vendor IDs commonly seen on graphics cards / OEM systems.
    $vendors = @{
        "1043" = "ASUS"
        "1462" = "MSI"
        "1458" = "GIGABYTE"
        "19DA" = "ZOTAC"
        "1569" = "PALIT"
        "3842" = "EVGA"
        "196E" = "PNY"
        "1DA2" = "SAPPHIRE"
        "1EAE" = "XFX"
        "174B" = "SAPPHIRE / PC Partner"
        "1028" = "Dell"
        "103C" = "HP"
        "17AA" = "Lenovo"
        "104D" = "Sony"
        "1179" = "Toshiba"
        "144D" = "Samsung"
        "106B" = "Apple"
        "10DE" = "NVIDIA"
        "1002" = "AMD"
        "8086" = "Intel"
    }

    if (-not $VendorId) {
        return $null
    }

    return $vendors[$VendorId]
}

function Get-DataError {
    param($Data)

    if (
        $Data -is [System.Collections.IDictionary] -and
        $Data.Contains("error")
    ) {
        return [string]$Data["error"]
    }

    return $null
}

function Format-Value {
    param(
        $Value,
        [string]$Fallback = "未知"
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $Fallback
    }

    return [string]$Value
}

function Format-Gb {
    param($Value)

    if ($null -eq $Value) {
        return "未知"
    }

    try {
        return ("{0:N2} GB" -f [double]$Value)
    }
    catch {
        return (Format-Value $Value)
    }
}

function Format-Mhz {
    param($Value)

    if ($null -eq $Value) {
        return "未知"
    }

    try {
        return ("{0:N0} MHz" -f [double]$Value)
    }
    catch {
        return (Format-Value $Value)
    }
}

function Convert-MonitorText {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }

    return (
        $Value |
            Where-Object { $_ -ne 0 } |
            ForEach-Object { [char]$_ }
    ) -join ""
}

function Convert-AdapterRamToGb {
    param($Bytes)

    if ($null -eq $Bytes) {
        return $null
    }

    try {
        return [math]::Round(([double]$Bytes / 1GB), 2)
    }
    catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# Collect all information in memory only.
# Every section is isolated: a failure is stored and execution continues.
# ---------------------------------------------------------------------------

$Report = [ordered]@{
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

$Report.system = Get-SafeData {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

    [ordered]@{
        manufacturer = $cs.Manufacturer
        model        = $cs.Model
        system_type  = $cs.SystemType
        total_ram_gb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    }
}

$Report.cpu = Get-SafeData {
    @(
        Get-CimInstance Win32_Processor -ErrorAction Stop |
            ForEach-Object {
                [ordered]@{
                    name               = $_.Name
                    manufacturer       = $_.Manufacturer
                    cores              = $_.NumberOfCores
                    logical_processors = $_.NumberOfLogicalProcessors
                    max_clock_mhz      = $_.MaxClockSpeed
                }
            }
    )
}

$Report.gpu = [ordered]@{}

$Report.gpu.basic = Get-SafeData {
    @(
        Get-CimInstance Win32_VideoController -ErrorAction Stop |
            ForEach-Object {
                $pnpId = [string]$_.PNPDeviceID
                $vendorId = Get-PciId $pnpId "VEN"

                [ordered]@{
                    name               = $_.Name
                    chip_vendor        = Get-GpuChipVendor $vendorId
                    pci_vendor_id      = $vendorId
                    driver_version     = $_.DriverVersion
                    driver_date        = $_.DriverDate
                    video_processor    = $_.VideoProcessor
                    video_mode         = $_.VideoModeDescription
                    adapter_ram_wmi_gb = Convert-AdapterRamToGb $_.AdapterRAM
                    pnp_device_id      = $pnpId
                }
            }
    )
}

$Report.gpu.pci = Get-SafeData {
    $result = @()

    $devices = @(
        Get-PnpDevice `
            -Class Display `
            -PresentOnly `
            -ErrorAction Stop
    )

    foreach ($device in $devices) {
        try {
            $property = Get-PnpDeviceProperty `
                -InstanceId $device.InstanceId `
                -KeyName "DEVPKEY_Device_HardwareIds" `
                -ErrorAction Stop

            $ids = @($property.Data)

            if (-not $ids.Count) {
                $result += [ordered]@{
                    name  = $device.FriendlyName
                    error = "找不到 Hardware ID。"
                }

                continue
            }

            $hardwareId = [string]$ids[0]
            $vendorId = Get-PciId $hardwareId "VEN"
            $deviceId = Get-PciId $hardwareId "DEV"
            $subsys = $null
            $subModel = $null
            $subVendor = $null

            if ($hardwareId -match "SUBSYS_([0-9A-Fa-f]{8})") {
                $subsys = $Matches[1].ToUpper()
                $subModel = $subsys.Substring(0, 4)
                $subVendor = $subsys.Substring(4, 4)
            }

            $result += [ordered]@{
                name             = $device.FriendlyName
                status           = $device.Status
                chip_vendor      = Get-GpuChipVendor $vendorId
                pci_vendor_id    = $vendorId
                pci_device_id    = $deviceId
                subsystem_id     = $subsys
                subsystem_model  = $subModel
                subsystem_vendor = $subVendor
                board_vendor     = Get-GpuBoardVendor $subVendor
                hardware_id      = $hardwareId
                instance_id      = $device.InstanceId
                all_hardware_ids = $ids
            }
        }
        catch {
            $result += [ordered]@{
                name  = $device.FriendlyName
                error = $_.Exception.Message
            }
        }
    }

    return $result
}

$Report.gpu.nvidia = Get-SafeData {
    $nvidiaSmi = Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue

    if (-not $nvidiaSmi) {
        return @()
    }

    $query = @(
        "name",
        "driver_version",
        "vbios_version",
        "memory.total",
        "pci.bus_id",
        "clocks.current.graphics",
        "clocks.current.memory",
        "clocks.max.graphics",
        "clocks.max.memory"
    ) -join ","

    $rows = @(
        & $nvidiaSmi.Source `
            "--query-gpu=$query" `
            "--format=csv,noheader,nounits" 2>$null
    )

    if ($LASTEXITCODE -ne 0) {
        throw "nvidia-smi 執行失敗，ExitCode=$LASTEXITCODE"
    }

    $result = @()

    foreach ($row in $rows) {
        $v = $row -split ",\s*"

        if ($v.Count -lt 9) {
            $result += [ordered]@{
                error = "nvidia-smi 回傳格式不完整：$row"
            }

            continue
        }

        $result += [ordered]@{
            name                 = $v[0]
            driver_version       = $v[1]
            vbios_version        = $v[2]
            memory_total_mb      = $v[3]
            pci_bus_id           = $v[4]
            current_graphics_mhz = $v[5]
            current_memory_mhz   = $v[6]
            max_graphics_mhz     = $v[7]
            max_memory_mhz       = $v[8]
        }
    }

    return $result
}

$Report.ram = Get-SafeData {
    @(
        Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop |
            ForEach-Object {
                [ordered]@{
                    manufacturer         = $_.Manufacturer
                    part_number          = if ($_.PartNumber) {
                        $_.PartNumber.Trim()
                    }
                    else {
                        $null
                    }
                    capacity_gb          = [math]::Round($_.Capacity / 1GB, 2)
                    speed_mhz            = $_.Speed
                    configured_clock_mhz = $_.ConfiguredClockSpeed
                }
            }
    )
}

$Report.motherboard = Get-SafeData {
    $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop

    [ordered]@{
        manufacturer = $board.Manufacturer
        product      = $board.Product
        version      = $board.Version
    }
}

$Report.bios = Get-SafeData {
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop

    [ordered]@{
        manufacturer = $bios.Manufacturer
        version      = $bios.SMBIOSBIOSVersion
        release_date = $bios.ReleaseDate
    }
}

$Report.storage = [ordered]@{}

$Report.storage.physical_disks = Get-SafeData {
    @(
        Get-PhysicalDisk -ErrorAction Stop |
            ForEach-Object {
                [ordered]@{
                    name               = $_.FriendlyName
                    media_type         = $_.MediaType
                    bus_type           = $_.BusType
                    size_gb            = [math]::Round($_.Size / 1GB, 2)
                    health_status      = $_.HealthStatus
                    operational_status = @($_.OperationalStatus)
                }
            }
    )
}

$Report.storage.drive_models = Get-SafeData {
    @(
        Get-CimInstance Win32_DiskDrive -ErrorAction Stop |
            ForEach-Object {
                [ordered]@{
                    model          = $_.Model
                    interface_type = $_.InterfaceType
                    media_type     = $_.MediaType
                    size_gb        = [math]::Round($_.Size / 1GB, 2)
                }
            }
    )
}

$Report.volumes = Get-SafeData {
    @(
        Get-Volume -ErrorAction Stop |
            Where-Object DriveLetter |
            Sort-Object DriveLetter |
            ForEach-Object {
                [ordered]@{
                    drive_letter = $_.DriveLetter
                    label        = $_.FileSystemLabel
                    file_system  = $_.FileSystem
                    size_gb      = [math]::Round($_.Size / 1GB, 2)
                    free_gb      = [math]::Round($_.SizeRemaining / 1GB, 2)
                }
            }
    )
}

$Report.monitors = Get-SafeData {
    @(
        Get-CimInstance `
            -Namespace root\wmi `
            -ClassName WmiMonitorID `
            -ErrorAction Stop |
            ForEach-Object {
                [ordered]@{
                    manufacturer = Convert-MonitorText $_.ManufacturerName
                    model        = Convert-MonitorText $_.UserFriendlyName
                }
            }
    )
}

$Report.windows = Get-SafeData {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop

    [ordered]@{
        name         = $os.Caption
        version      = $os.Version
        build_number = $os.BuildNumber
        architecture = $os.OSArchitecture
    }
}

$Report.battery = Get-SafeData {
    @(
        Get-CimInstance Win32_Battery -ErrorAction Stop |
            ForEach-Object {
                [ordered]@{
                    name                     = $_.Name
                    status                   = $_.Status
                    estimated_charge_percent = $_.EstimatedChargeRemaining
                }
            }
    )
}

# ---------------------------------------------------------------------------
# Build Traditional Chinese Markdown report.
# ---------------------------------------------------------------------------

$Lines = New-Object System.Collections.Generic.List[string]

function Add-Line {
    param([string]$Text = "")

    [void]$Lines.Add($Text)
}

function Add-SectionError {
    param($Data)

    $errorMessage = Get-DataError $Data

    if ($errorMessage) {
        Add-Line "- ⚠️ 取得資料時發生錯誤：$errorMessage"
        return $true
    }

    return $false
}

function Add-ItemError {
    param($Item)

    if (
        $Item -is [System.Collections.IDictionary] -and
        $Item.Contains("error")
    ) {
        Add-Line "  - ⚠️ 錯誤：$($Item.error)"
        return $true
    }

    return $false
}

Add-Line "# PC 硬體資訊中文解讀"
Add-Line ""
Add-Line "- 報告產生時間：$($Report.generated_at)"

Add-Line ""
Add-Line "## 快速摘要"

if (-not (Get-DataError $Report.cpu)) {
    $cpu = @($Report.cpu) | Select-Object -First 1

    if ($cpu) {
        Add-Line "- CPU：$(Format-Value $cpu.name)"
    }
}

if (-not (Get-DataError $Report.gpu.basic)) {
    foreach ($gpu in @($Report.gpu.basic)) {
        Add-Line (
            "- GPU：{0} ({1})" -f
            (Format-Value $gpu.name),
            (Format-Value $gpu.chip_vendor)
        )
    }
}

if (-not (Get-DataError $Report.ram)) {
    $ramModules = @($Report.ram)
    $ramTotal = 0.0

    foreach ($module in $ramModules) {
        if ($null -ne $module.capacity_gb) {
            $ramTotal += [double]$module.capacity_gb
        }
    }

    if ($ramTotal -gt 0) {
        Add-Line "- RAM：$(Format-Gb $ramTotal) / $($ramModules.Count) 條"
    }
}

if (-not (Get-DataError $Report.storage.physical_disks)) {
    foreach ($disk in @($Report.storage.physical_disks)) {
        Add-Line (
            "- 儲存裝置：{0} / {1} / {2}" -f
            (Format-Value $disk.name),
            (Format-Gb $disk.size_gb),
            (Format-Value $disk.bus_type)
        )
    }
}

if (-not (Get-DataError $Report.windows)) {
    Add-Line (
        "- 系統：{0} / {1}" -f
        (Format-Value $Report.windows.name),
        (Format-Value $Report.windows.architecture)
    )
}

Add-Line ""
Add-Line "## 電腦整體資訊"

if (-not (Add-SectionError $Report.system)) {
    Add-Line "- 製造商：$(Format-Value $Report.system.manufacturer)"
    Add-Line "- 型號：$(Format-Value $Report.system.model)"
    Add-Line "- 系統類型：$(Format-Value $Report.system.system_type)"
    Add-Line "- 系統記憶體總量：約 $(Format-Gb $Report.system.total_ram_gb)"
}

Add-Line ""
Add-Line "## 處理器 CPU"

if (-not (Add-SectionError $Report.cpu)) {
    $cpuIndex = 0

    foreach ($cpu in @($Report.cpu)) {
        $cpuIndex++

        Add-Line "- CPU $cpuIndex：$(Format-Value $cpu.name)"
        Add-Line "  - 製造商：$(Format-Value $cpu.manufacturer)"
        Add-Line "  - 實體核心：$(Format-Value $cpu.cores) 核"
        Add-Line "  - 邏輯處理器：$(Format-Value $cpu.logical_processors) 執行緒"
        Add-Line "  - WMI 標示最高時脈：$(Format-Mhz $cpu.max_clock_mhz)"
    }
}

Add-Line ""
Add-Line "## 顯示卡 GPU"

if (-not (Add-SectionError $Report.gpu.basic)) {
    $gpuIndex = 0

    foreach ($gpu in @($Report.gpu.basic)) {
        $gpuIndex++

        Add-Line "- 顯示卡 $gpuIndex：$(Format-Value $gpu.name)"
        Add-Line "  - GPU 廠牌：$(Format-Value $gpu.chip_vendor)"
        Add-Line "  - PCI Vendor ID：$(Format-Value $gpu.pci_vendor_id)"
        Add-Line "  - 驅動版本：$(Format-Value $gpu.driver_version)"
        Add-Line "  - 驅動日期：$(Format-Value $gpu.driver_date)"
        Add-Line "  - GPU 處理器：$(Format-Value $gpu.video_processor)"
        Add-Line "  - 目前影像模式：$(Format-Value $gpu.video_mode)"

        if ($null -ne $gpu.adapter_ram_wmi_gb) {
            Add-Line "  - WMI 回報顯示記憶體：$(Format-Gb $gpu.adapter_ram_wmi_gb)"
        }

        Add-Line "  - PNP Device ID：$(Format-Value $gpu.pnp_device_id)"
    }
}

Add-Line ""
Add-Line "### PCI / 顯示卡板卡識別"

if (-not (Add-SectionError $Report.gpu.pci)) {
    $gpuPciIndex = 0

    foreach ($gpu in @($Report.gpu.pci)) {
        $gpuPciIndex++

        Add-Line "- 裝置 $gpuPciIndex：$(Format-Value $gpu.name)"

        if (Add-ItemError $gpu) {
            continue
        }

        Add-Line "  - GPU 晶片廠牌：$(Format-Value $gpu.chip_vendor)"
        Add-Line "  - 狀態：$(Format-Value $gpu.status)"
        Add-Line "  - PCI Vendor ID：$(Format-Value $gpu.pci_vendor_id)"
        Add-Line "  - PCI Device ID：$(Format-Value $gpu.pci_device_id)"
        Add-Line "  - Subsystem ID：$(Format-Value $gpu.subsystem_id)"
        Add-Line (
            "  - 板卡 / OEM 廠牌判定：{0}" -f
            (Format-Value $gpu.board_vendor "無法由目前對照表判定")
        )
        Add-Line "  - Hardware ID：$(Format-Value $gpu.hardware_id)"
    }
}

$nvidiaItems = @(
    $Report.gpu.nvidia |
        Where-Object { $null -ne $_ }
)

if (
    -not (Get-DataError $Report.gpu.nvidia) -and
    $nvidiaItems.Count -gt 0
) {
    Add-Line ""
    Add-Line "### NVIDIA 額外資訊"

    $nvidiaIndex = 0

    foreach ($gpu in $nvidiaItems) {
        $nvidiaIndex++

        Add-Line "- NVIDIA GPU $nvidiaIndex：$(Format-Value $gpu.name)"

        if (Add-ItemError $gpu) {
            continue
        }

        Add-Line "  - 驅動版本：$(Format-Value $gpu.driver_version)"
        Add-Line "  - VBIOS：$(Format-Value $gpu.vbios_version)"
        Add-Line "  - 顯示記憶體：$(Format-Value $gpu.memory_total_mb) MB"
        Add-Line "  - PCI Bus ID：$(Format-Value $gpu.pci_bus_id)"
        Add-Line "  - 目前核心時脈：$(Format-Mhz $gpu.current_graphics_mhz)"
        Add-Line "  - 目前記憶體時脈：$(Format-Mhz $gpu.current_memory_mhz)"
        Add-Line "  - 最大核心時脈：$(Format-Mhz $gpu.max_graphics_mhz)"
        Add-Line "  - 最大記憶體時脈：$(Format-Mhz $gpu.max_memory_mhz)"
    }
}

Add-Line ""
Add-Line "## 記憶體 RAM"

if (-not (Add-SectionError $Report.ram)) {
    $ramIndex = 0
    $ramTotal = 0.0

    foreach ($ram in @($Report.ram)) {
        $ramIndex++

        if ($null -ne $ram.capacity_gb) {
            $ramTotal += [double]$ram.capacity_gb
        }

        Add-Line "- RAM $ramIndex"
        Add-Line "  - 品牌：$(Format-Value $ram.manufacturer)"
        Add-Line "  - 型號 / Part Number：$(Format-Value $ram.part_number)"
        Add-Line "  - 容量：$(Format-Gb $ram.capacity_gb)"
        Add-Line "  - 標示速度：$(Format-Mhz $ram.speed_mhz)"
        Add-Line "  - 目前設定速度：$(Format-Mhz $ram.configured_clock_mhz)"
    }

    if ($ramTotal -gt 0) {
        Add-Line "- RAM 模組容量加總：約 $(Format-Gb $ramTotal)"
    }
}

Add-Line ""
Add-Line "## 主機板"

if (-not (Add-SectionError $Report.motherboard)) {
    Add-Line "- 品牌：$(Format-Value $Report.motherboard.manufacturer)"
    Add-Line "- 型號：$(Format-Value $Report.motherboard.product)"
    Add-Line "- 版本：$(Format-Value $Report.motherboard.version)"
}

Add-Line ""
Add-Line "## BIOS / UEFI"

if (-not (Add-SectionError $Report.bios)) {
    Add-Line "- 廠商：$(Format-Value $Report.bios.manufacturer)"
    Add-Line "- BIOS 版本：$(Format-Value $Report.bios.version)"
    Add-Line "- 發布日期：$(Format-Value $Report.bios.release_date)"
}

Add-Line ""
Add-Line "## 儲存裝置"
Add-Line ""
Add-Line "### 實體磁碟"

if (-not (Add-SectionError $Report.storage.physical_disks)) {
    $diskIndex = 0

    foreach ($disk in @($Report.storage.physical_disks)) {
        $diskIndex++

        Add-Line "- 磁碟 $diskIndex：$(Format-Value $disk.name)"
        Add-Line "  - 類型：$(Format-Value $disk.media_type)"
        Add-Line "  - 匯流排：$(Format-Value $disk.bus_type)"
        Add-Line "  - 容量：$(Format-Gb $disk.size_gb)"
        Add-Line "  - 健康狀態：$(Format-Value $disk.health_status)"
        Add-Line (
            "  - 運作狀態：{0}" -f
            (Format-Value (@($disk.operational_status) -join ", "))
        )
    }
}

Add-Line ""
Add-Line "### Windows 磁碟型號"

if (-not (Add-SectionError $Report.storage.drive_models)) {
    $diskIndex = 0

    foreach ($disk in @($Report.storage.drive_models)) {
        $diskIndex++

        Add-Line "- 磁碟 $diskIndex：$(Format-Value $disk.model)"
        Add-Line "  - 介面：$(Format-Value $disk.interface_type)"
        Add-Line "  - 媒體類型：$(Format-Value $disk.media_type)"
        Add-Line "  - 容量：$(Format-Gb $disk.size_gb)"
    }
}

Add-Line ""
Add-Line "## 磁碟分割區 / 磁碟機"

if (-not (Add-SectionError $Report.volumes)) {
    foreach ($volume in @($Report.volumes)) {
        $drive = "$(Format-Value $volume.drive_letter):"
        $label = Format-Value $volume.label ""

        if ($label) {
            Add-Line "- $drive $label"
        }
        else {
            Add-Line "- $drive"
        }

        Add-Line "  - 檔案系統：$(Format-Value $volume.file_system)"
        Add-Line "  - 總容量：$(Format-Gb $volume.size_gb)"
        Add-Line "  - 剩餘空間：$(Format-Gb $volume.free_gb)"

        if (
            $null -ne $volume.size_gb -and
            [double]$volume.size_gb -gt 0 -and
            $null -ne $volume.free_gb
        ) {
            $usedPercent = (
                (
                    [double]$volume.size_gb -
                    [double]$volume.free_gb
                ) /
                [double]$volume.size_gb
            ) * 100

            Add-Line "  - 已使用：約 $([math]::Round($usedPercent, 1))%"
        }
    }
}

Add-Line ""
Add-Line "## 螢幕"

if (-not (Add-SectionError $Report.monitors)) {
    $monitorIndex = 0

    foreach ($monitor in @($Report.monitors)) {
        $monitorIndex++

        Add-Line (
            "- 螢幕 {0}：{1} {2}" -f
            $monitorIndex,
            (Format-Value $monitor.manufacturer),
            (Format-Value $monitor.model)
        )
    }
}

Add-Line ""
Add-Line "## Windows"

if (-not (Add-SectionError $Report.windows)) {
    Add-Line "- 系統：$(Format-Value $Report.windows.name)"
    Add-Line "- 版本：$(Format-Value $Report.windows.version)"
    Add-Line "- Build：$(Format-Value $Report.windows.build_number)"
    Add-Line "- 架構：$(Format-Value $Report.windows.architecture)"
}

Add-Line ""
Add-Line "## 電池"

if (-not (Add-SectionError $Report.battery)) {
    $batteryItems = @($Report.battery)

    if ($batteryItems.Count -eq 0) {
        Add-Line "- 未偵測到電池。桌上型電腦通常屬於正常情況。"
    }
    else {
        $batteryIndex = 0

        foreach ($item in $batteryItems) {
            $batteryIndex++

            Add-Line "- 電池 $batteryIndex：$(Format-Value $item.name)"
            Add-Line "  - 狀態：$(Format-Value $item.status)"
            Add-Line "  - 預估剩餘電量：$(Format-Value $item.estimated_charge_percent)%"
        }
    }
}

# ---------------------------------------------------------------------------
# Write only the final report.
# Try Desktop first; if unavailable, fall back to the current directory.
# ---------------------------------------------------------------------------

$Markdown = $Lines -join [Environment]::NewLine
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$desktopPath = [Environment]::GetFolderPath("Desktop")

$outputCandidates = @(
    (Join-Path $desktopPath "PC_Valuation_Report.md"),
    (Join-Path (Get-Location).Path "PC_Valuation_Report.md")
) | Select-Object -Unique

$OutputFile = $null
$writeErrors = @()

foreach ($candidate in $outputCandidates) {
    try {
        [System.IO.File]::WriteAllText(
            $candidate,
            $Markdown,
            $Utf8NoBom
        )

        $OutputFile = $candidate
        break
    }
    catch {
        $writeErrors += $_.Exception.Message
    }
}

if ($OutputFile) {
    Write-Host ""
    Write-Host "SUCCESS" -ForegroundColor Green
    Write-Host "Saved to: $OutputFile" -ForegroundColor Cyan
    Write-Host ""
}
