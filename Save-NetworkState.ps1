#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Saves the current state of a user-selected network interface to a JSON file.

.DESCRIPTION
    Reads every parameter that Configure-CameraInterface.ps1 modifies — NIC advanced
    properties, RSS, LSO, flow control, power management, the AFD registry key, and
    the IPv4 configuration — and writes a timestamped JSON snapshot.

    Output: NetworkState_<AdapterName>_<yyyy-MM-ddTHH-mm-ss>.json
    Written to the script's directory, or to the working directory if run interactively.

.NOTES
    Format rationale (JSON):
      - The data is naturally nested: FlowControl has 3 flags, PowerManagement 3, LSO 2.
      - CSV is too flat; Export-Clixml is verbose and .NET-specific; INI has no nesting.
      - ConvertTo-Json / ConvertFrom-Json are built into PowerShell 3+.
      - Output is human-readable, easily diffed, and consumable by other tools.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Select adapter ────────────────────────────────────────────────────────────
$adapters = Get-NetAdapter | Sort-Object InterfaceIndex
Write-Host ""
$adapters | Format-Table -AutoSize InterfaceIndex, Name, InterfaceDescription, Status, LinkSpeed

$idx = [int](Read-Host "Enter adapter InterfaceIndex")
$adapter = $adapters | Where-Object { $_.InterfaceIndex -eq $idx }
if (-not $adapter) { throw "No adapter with InterfaceIndex $idx found." }

Write-Host "`nReading state of: $($adapter.Name) — $($adapter.InterfaceDescription)`n"

$n = $adapter.Name

# ── Helper: read one named advanced property; returns $null if absent ─────────
function Get-Prop([string]$adapterName, [string]$displayName) {
    $prop = Get-NetAdapterAdvancedProperty -Name $adapterName -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $displayName }
    if ($prop) { return $prop.DisplayValue }
    return $null
}

# ── NIC advanced properties ───────────────────────────────────────────────────
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

# ── RSS ───────────────────────────────────────────────────────────────────────
$rss = $null
try {
    $rssObj = Get-NetAdapterRss -Name $n -ErrorAction Stop
    $rss = [ordered]@{
        Enabled               = $rssObj.Enabled
        NumberOfReceiveQueues = $rssObj.NumberOfReceiveQueues
    }
} catch { Write-Warning "RSS not readable: $($_.Exception.Message)" }

# ── LSO ───────────────────────────────────────────────────────────────────────
$lso = $null
try {
    $lsoObj = Get-NetAdapterLso -Name $n -ErrorAction Stop
    $lso = [ordered]@{
        IPv4Enabled = $lsoObj.IPv4Enabled
        IPv6Enabled = $lsoObj.IPv6Enabled
    }
} catch { Write-Warning "LSO not readable: $($_.Exception.Message)" }

# ── Flow Control ──────────────────────────────────────────────────────────────
$flowControl = $null
try {
    $fcObj = Get-NetAdapterFlowControl -Name $n -ErrorAction Stop
    $flowControl = [ordered]@{
        AutoNegotiate = $fcObj.AutoNegotiate
        RxEnabled     = $fcObj.RxEnabled
        TxEnabled     = $fcObj.TxEnabled
    }
} catch { Write-Warning "Flow Control not readable: $($_.Exception.Message)" }

# ── Power Management ──────────────────────────────────────────────────────────
# Cast enum values to string; without this they serialise as integers in JSON.
$powerManagement = $null
try {
    $pmObj = Get-NetAdapterPowerManagement -Name $n -ErrorAction Stop
    $powerManagement = [ordered]@{
        AllowComputerToTurnOffDevice = [string]$pmObj.AllowComputerToTurnOffDevice
        WakeOnMagicPacket            = [string]$pmObj.WakeOnMagicPacket
        WakeOnPattern                = [string]$pmObj.WakeOnPattern
    }
} catch { Write-Warning "Power Management not readable: $($_.Exception.Message)" }

# ── AFD socket receive buffer (registry) ─────────────────────────────────────
# null means the key is absent and Windows uses its built-in default (~65536 bytes).
# Storing null rather than the Windows default lets a restore script distinguish
# "was never set" from "was explicitly set to some value".
$afdKey = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
$afdReceiveWindow = $null
try {
    $afdReceiveWindow = (Get-ItemProperty -Path $afdKey `
        -Name "DefaultReceiveWindow" -ErrorAction Stop).DefaultReceiveWindow
} catch {}

# ── IPv4 configuration ────────────────────────────────────────────────────────
# Wrap in @() so the result is always an array — an adapter can have multiple
# IPv4 addresses, and a bare cmdlet call returns a scalar when there is only one.
$ipAddresses = @(
    Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex `
        -AddressFamily IPv4 -ErrorAction SilentlyContinue
) | ForEach-Object {
    [ordered]@{
        IPAddress    = $_.IPAddress
        PrefixLength = $_.PrefixLength
    }
}

# ── Assemble and write ────────────────────────────────────────────────────────
$state = [ordered]@{
    SavedAt            = (Get-Date -Format "o")   # ISO 8601
    AdapterName        = $adapter.Name
    InterfaceIndex     = $adapter.InterfaceIndex
    Description        = $adapter.InterfaceDescription
    AdvancedProperties = $advancedProperties
    RSS                = $rss
    LSO                = $lso
    FlowControl        = $flowControl
    PowerManagement    = $powerManagement
    AFD                = [ordered]@{
        DefaultReceiveWindow = $afdReceiveWindow  # bytes; null = Windows built-in default
    }
    IPv4Addresses      = $ipAddresses
}

$outDir    = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$timestamp = Get-Date -Format "yyyy-MM-ddTHH-mm-ss"
$safeName  = $adapter.Name -replace '[^\w-]', '_'
$outPath   = Join-Path $outDir "NetworkState_${safeName}_${timestamp}.json"

$state | ConvertTo-Json -Depth 5 | Set-Content -Path $outPath -Encoding UTF8

Write-Host "Saved to: $outPath"
