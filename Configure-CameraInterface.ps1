#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures a network interface on an Intel X550-T2 for multicamera (GigE Vision) use.

.DESCRIPTION
    Prompts the user to select a network adapter, provide a new name, and choose a subnet
    octet. Then applies the following settings:
      - Speed & Duplex       : 1.0 Gbps Full Duplex
      - Jumbo Frames         : 9014 bytes
      - Receive/Tx Buffers   : 4096 (X550 maximum)
      - Interrupt Moderation : Disabled
      - Flow Control         : Disabled (Tx + Rx)
      - Energy Eff. Ethernet : Disabled
      - RSS                  : Enabled, 8 queues
      - Large Send Offload   : Disabled
      - Checksum Offload     : Rx & Tx Enabled (UDP + TCP)
      - Power Management     : Disabled
      - Socket Recv Buffer   : 16 MB system default (AFD registry)
      - Rename adapter
      - Static IP            : 192.168.<user>.1 /24
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Gather all inputs upfront ─────────────────────────────────────────────────

$adapters = Get-NetAdapter | Sort-Object InterfaceIndex
Write-Host ""
$adapters | Format-Table -AutoSize InterfaceIndex, Name, InterfaceDescription, Status, LinkSpeed

$idx = [int](Read-Host "Enter adapter InterfaceIndex")
$adapter = $adapters | Where-Object { $_.InterfaceIndex -eq $idx }
if (-not $adapter) { throw "No adapter with InterfaceIndex $idx found." }

$newName = (Read-Host "New interface name").Trim()
if ([string]::IsNullOrEmpty($newName)) { throw "Interface name cannot be empty." }

$octet = Read-Host "Subnet octet  x  for  192.168.x.1  (1-254)"
if ($octet -notmatch '^\d+$' -or [int]$octet -lt 1 -or [int]$octet -gt 254) {
    throw "Subnet octet must be an integer between 1 and 254."
}
$ip = "192.168.$octet.1"

Write-Host ""
Write-Host "  Adapter : $($adapter.Name)  ->  '$newName'"
Write-Host "  IP      : $ip/24"
Write-Host ""

# ── Helper: set an advanced property, warn and continue if unsupported ─────────
function Set-Prop {
    param(
        [string] $AdapterName,
        [string] $DisplayName,
        [string] $Value
    )
    try {
        Set-NetAdapterAdvancedProperty -Name $AdapterName `
            -DisplayName $DisplayName -DisplayValue $Value -ErrorAction Stop
        Write-Host "  [OK]    $DisplayName = $Value"
    }
    catch {
        Write-Warning "  [SKIP]  '$DisplayName' -- $($_.Exception.Message)"
    }
}

$n = $adapter.Name

# ── Speed & Duplex ────────────────────────────────────────────────────────────
# X550-T2 is 10 GbE; force 1 G to match GigE Vision cameras and avoid
# auto-negotiation surprises on 1 G switches.
Set-Prop $n "Speed & Duplex" "1.0 Gbps Full Duplex"

# ── Jumbo Frames ──────────────────────────────────────────────────────────────
# 9014 = 9000-byte payload + Ethernet/VLAN headers.
# Reduces CPU overhead per image payload; must also be enabled on the switch.
Set-Prop $n "Jumbo Packet" "9014 Bytes"

# ── Ring Buffers (X550 maximum = 4096) ───────────────────────────────────────
Set-Prop $n "Receive Buffers"  "4096"
Set-Prop $n "Transmit Buffers" "4096"

# ── Interrupt Moderation ──────────────────────────────────────────────────────
# Batching interrupts saves CPU but adds jitter; disable for consistent
# per-frame latency across multiple cameras.
Set-Prop $n "Interrupt Moderation" "Disabled"

# ── Flow Control ──────────────────────────────────────────────────────────────
# Pause frames can stall an entire link and cause frame drops on other cameras.
try {
    Set-NetAdapterFlowControl -Name $n `
        -AutoNegotiate $false -RxEnabled $false -TxEnabled $false -ErrorAction Stop
    Write-Host "  [OK]    Flow Control = Disabled (Tx + Rx)"
}
catch {
    Set-Prop $n "Flow Control" "Disabled"
}

# ── Energy Efficient Ethernet ─────────────────────────────────────────────────
# EEE powers down the link during quiet periods; wake-up latency disrupts
# continuous camera streams.
Set-Prop $n "Energy Efficient Ethernet" "Disabled"

# ── Receive Side Scaling ──────────────────────────────────────────────────────
# Distribute incoming streams from multiple cameras across CPU cores.
try {
    Set-NetAdapterRss -Name $n -Enabled $true -ErrorAction Stop
    Write-Host "  [OK]    RSS = Enabled"
}
catch {
    Write-Warning "  [SKIP]  RSS -- $($_.Exception.Message)"
}
Set-Prop $n "Maximum Number of RSS Queues" "8"

# ── Large Send Offload ────────────────────────────────────────────────────────
# LSO is designed for TCP bulk transfers; GigE Vision uses UDP and LSO
# can interfere with packet timing.
try {
    Disable-NetAdapterLso -Name $n -ErrorAction Stop
    Write-Host "  [OK]    Large Send Offload = Disabled"
}
catch {
    Write-Warning "  [SKIP]  LSO -- $($_.Exception.Message)"
}

# ── Checksum Offload ──────────────────────────────────────────────────────────
# Offloading checksum calculation to the NIC reduces CPU load; keep enabled.
Set-Prop $n "TCP Checksum Offload (IPv4)" "Rx & Tx Enabled"
Set-Prop $n "UDP Checksum Offload (IPv4)" "Rx & Tx Enabled"

# ── Power Management ──────────────────────────────────────────────────────────
try {
    Set-NetAdapterPowerManagement -Name $n `
        -AllowComputerToTurnOffDevice Disabled `
        -WakeOnMagicPacket Disabled `
        -WakeOnPattern Disabled -ErrorAction Stop
    Write-Host "  [OK]    Power Management = Disabled"
}
catch {
    Write-Warning "  [SKIP]  Power Management -- $($_.Exception.Message)"
}

# ── System-wide UDP socket receive buffer ────────────────────────────────────
# GigE Vision cameras send large UDP bursts. The default kernel socket buffer
# (~64 KB) is too small; packets are silently dropped before the SDK reads them.
# Setting 16 MB here means every new socket inherits a large buffer even if
# the camera SDK does not call setsockopt(SO_RCVBUF) itself.
try {
    $afdKey = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
    if (-not (Test-Path $afdKey)) { New-Item -Path $afdKey -Force | Out-Null }
    Set-ItemProperty -Path $afdKey -Name "DefaultReceiveWindow" -Value 16777216 -Type DWord
    Write-Host "  [OK]    AFD DefaultReceiveWindow = 16 MB (requires reboot)"
}
catch {
    Write-Warning "  [SKIP]  AFD DefaultReceiveWindow -- $($_.Exception.Message)"
}

# ── Rename adapter ────────────────────────────────────────────────────────────
Rename-NetAdapter -Name $n -NewName $newName -ErrorAction Stop
Write-Host "  [OK]    Renamed '$n'  ->  '$newName'"
$n = $newName

# ── Static IP ─────────────────────────────────────────────────────────────────
# Remove any existing IPv4 addresses and default routes on this interface
# before assigning the new static address.
try {
    Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false

    Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" `
        -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false

    New-NetIPAddress -InterfaceAlias $n -IPAddress $ip -PrefixLength 24 | Out-Null
    Write-Host "  [OK]    Static IP = $ip/24"
}
catch {
    Write-Warning "  [SKIP]  Static IP assignment failed -- $($_.Exception.Message)"
    Write-Warning "          The adapter has been renamed to '$n' but has no IP address."
    Write-Warning "          Assign $ip/24 manually or re-run the script."
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Done."
Write-Host "  Interface : $n"
Write-Host "  IP        : $ip/24"
Write-Host ""
Write-Host "Disable and re-enable the adapter (or reboot) for NIC advanced settings to take effect."
Write-Host "The AFD socket buffer change requires a reboot."
