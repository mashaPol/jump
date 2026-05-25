#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Snapshots all network interface settings that Configure-CameraInterface.ps1 modifies.

.DESCRIPTION
    Reads every property touched by Configure-CameraInterface.ps1 — NIC advanced
    properties, RSS, LSO, flow control, power management, the AFD registry key, and
    the current IPv4 configuration — then writes a timestamped JSON file.

    Output file: NICSnapshot_<AdapterName>_<timestamp>.json
    Written to the same directory as this script.

.NOTES
    Why JSON?
    The data has natural nesting (FlowControl has 3 flags, PowerManagement 3, LSO 2).
    CSV is too flat; Export-Clixml is too verbose and .NET-specific; INI has no nesting.
    JSON is human-readable, easily diffed, built into PowerShell 3+ via ConvertTo-Json,
    and consumable by other tools (Python, web dashboards, etc.).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Select adapter ────────────────────────────────────────────────────────────
$adapters = Get-NetAdapter | Sort-Object InterfaceIndex
Write-Host ""
$adapters | Format-Table -AutoSize InterfaceIndex, Name, InterfaceDescription, Status, LinkSpeed

$idx = [int](Read-Host "Enter adapter InterfaceIndex to snapshot")
$adapter = $adapters | Where-Object { $_.InterfaceIndex -eq $idx }
if (-not $adapter) { throw "No adapter with InterfaceIndex $idx found." }

Write-Host "`nSnapshotting: $($adapter.Name) — $($adapter.InterfaceDescription)`n"

$n = $adapter.Name

# ── Helper: read one named advanced property; returns $null if absent ─────────
function Get-Prop([string]$adapterName, [string]$displayName) {
    $prop = Get-NetAdapterAdvancedProperty -Name $adapterName -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $displayName }
    return $(if ($prop) { $prop.DisplayValue } else { $null })
}

# ── 1-10: NIC advanced properties (Set-NetAdapterAdvancedProperty) ────────────
Write-Host "  Reading advanced properties..."
$advancedProperties = [ordered]@{
    "Speed & Duplex"               = Get-Prop $n "Speed & Duplex"
    "Jumbo Packet"                 = Get-Prop $n "Jumbo Packet"
    "Receive Buffers"              = Get-Prop $n "Receive Buffers"
    "Transmit Buffers"             = Get-Prop $n "Transmit Buffers"
    "Interrupt Moderation"         = Get-Prop $n "Interrupt Moderation"
    "Flow Control"                 = Get-Prop $n "Flow Control"
    "Energy Efficient Ethernet"    = Get-Prop $n "Energy Efficient Ethernet"
    "Maximum Number of RSS Queues" = Get-Prop $n "Maximum Number of RSS Queues"
    "TCP Checksum Offload (IPv4)"  = Get-Prop $n "TCP Checksum Offload (IPv4)"
    "UDP Checksum Offload (IPv4)"  = Get-Prop $n "UDP Checksum Offload (IPv4)"
}

# ── 11: RSS (Set-NetAdapterRss) ───────────────────────────────────────────────
Write-Host "  Reading RSS..."
$rss = $null
try {
    $rssObj = Get-NetAdapterRss -Name $n -ErrorAction Stop
    $rss = [ordered]@{
        Enabled         = $rssObj.Enabled
        NumberOfReceiveQueues = $rssObj.NumberOfReceiveQueues
    }
} catch { Write-Warning "  RSS not readable: $($_.Exception.Message)" }

# ── 12: LSO (Disable-NetAdapterLso) ──────────────────────────────────────────
Write-Host "  Reading LSO..."
$lso = $null
try {
    $lsoObj = Get-NetAdapterLso -Name $n -ErrorAction Stop
    $lso = [ordered]@{
        IPv4Enabled = $lsoObj.IPv4Enabled
        IPv6Enabled = $lsoObj.IPv6Enabled
    }
} catch { Write-Warning "  LSO not readable: $($_.Exception.Message)" }

# ── 13: Flow Control (Set-NetAdapterFlowControl) ──────────────────────────────
Write-Host "  Reading Flow Control..."
$flowControl = $null
try {
    $fcObj = Get-NetAdapterFlowControl -Name $n -ErrorAction Stop
    $flowControl = [ordered]@{
        AutoNegotiate = $fcObj.AutoNegotiate
        RxEnabled     = $fcObj.RxEnabled
        TxEnabled     = $fcObj.TxEnabled
    }
} catch { Write-Warning "  Flow Control not readable: $($_.Exception.Message)" }

# ── 14: Power Management (Set-NetAdapterPowerManagement) ─────────────────────
Write-Host "  Reading Power Management..."
$powerManagement = $null
try {
    $pmObj = Get-NetAdapterPowerManagement -Name $n -ErrorAction Stop
    $powerManagement = [ordered]@{
        AllowComputerToTurnOffDevice = [string]$pmObj.AllowComputerToTurnOffDevice
        WakeOnMagicPacket            = [string]$pmObj.WakeOnMagicPacket
        WakeOnPattern                = [string]$pmObj.WakeOnPattern
    }
} catch { Write-Warning "  Power Management not readable: $($_.Exception.Message)" }

# ── 15: AFD socket receive buffer (Set-ItemProperty / registry) ───────────────
Write-Host "  Reading AFD registry..."
$afdKey = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
$afdReceiveWindow = $null
try {
    $afdReceiveWindow = (Get-ItemProperty -Path $afdKey `
        -Name "DefaultReceiveWindow" -ErrorAction Stop).DefaultReceiveWindow
} catch {
    # Key absent means Windows is using its built-in default (~65536 bytes).
    # Record null so a restore script can distinguish "not set" from "set to 0".
    $afdReceiveWindow = $null
}

# ── 16: Adapter name (Rename-NetAdapter) ──────────────────────────────────────
# Captured via $adapter.Name above.

# ── 17: IPv4 address + prefix (New-NetIPAddress) ──────────────────────────────
Write-Host "  Reading IP configuration..."
$ipConfiguration = $null
$ipAddr = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex `
          -AddressFamily IPv4 -ErrorAction SilentlyContinue
if ($ipAddr) {
    $ipConfiguration = [ordered]@{
        IPAddress    = $ipAddr.IPAddress
        PrefixLength = $ipAddr.PrefixLength
    }
}

# ── Assemble snapshot ─────────────────────────────────────────────────────────
$snapshot = [ordered]@{
    SnapshotTime       = (Get-Date -Format "o")    # ISO 8601, unambiguous across locales
    AdapterName        = $adapter.Name
    InterfaceIndex     = $adapter.InterfaceIndex
    Description        = $adapter.InterfaceDescription
    AdvancedProperties = $advancedProperties
    RSS                = $rss
    LSO                = $lso
    FlowControl        = $flowControl
    PowerManagement    = $powerManagement
    AFD = [ordered]@{
        DefaultReceiveWindow = $afdReceiveWindow    # bytes; null = Windows default
    }
    IPConfiguration    = $ipConfiguration
}

# ── Write JSON ────────────────────────────────────────────────────────────────
$timestamp  = Get-Date -Format "yyyy-MM-ddTHH-mm-ss"
$safeName   = $adapter.Name -replace '[^\w\-]', '_'
$outputPath = Join-Path $PSScriptRoot "NICSnapshot_${safeName}_${timestamp}.json"

$snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path $outputPath -Encoding UTF8

Write-Host ""
Write-Host "Snapshot written to:"
Write-Host "  $outputPath"
