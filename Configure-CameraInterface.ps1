#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures a network interface on an Intel X550-T2 for multicamera (GigE Vision) use.

.DESCRIPTION
    Prompts the user to select a network adapter, provide a new name, and choose a subnet
    octet. For each NIC advanced property that exposes an enum of valid values, the current
    value and all options are shown and the user is asked to pick one (or press S to skip).
    Dedicated cmdlet settings (RSS, LSO, Power Management) get a simple Enable/Disable
    prompt. Free-form numeric settings (ring buffers) are applied with recommended values
    without prompting.

    Settings configured:
      - Speed & Duplex              : user choice  (recommended: 1.0 Gbps Full Duplex)
      - JumboPacket                 : user choice  (recommended: 9014 Bytes)
      - Receive Buffers             : 4096         (X550 max, applied silently)
      - Transmit Buffers            : 4096         (X550 max, applied silently)
      - Interrupt Moderation        : user choice  (recommended: Disabled)
      - Flow Control                : user choice  (recommended: Disabled)
      - Energy Efficient Ethernet   : user choice  (recommended: Disabled)
      - RSS                         : user choice  (recommended: Enable)
      - Maximum Number of RSS Queues: user choice  (recommended: 8)
      - Large Send Offload (LSO)    : user choice  (recommended: Disable)
      - TCP Checksum Offload (IPv4) : user choice  (recommended: Rx & Tx Enabled)
      - UDP Checksum Offload (IPv4) : user choice  (recommended: Rx & Tx Enabled)
      - Power Management            : user choice  (recommended: Disable)
      - AFD DefaultReceiveWindow    : 16 MB        (applied silently, requires reboot)
      - Adapter name                : user-supplied
      - Static IP                   : 192.168.<user>.1 /24
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Gather identity inputs upfront ────────────────────────────────────────────

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

$n = $adapter.Name

# ── Helper: prompt for an advanced property enum, or apply silently if free-form ──
#
# Reads ValidDisplayValues from the driver for $DisplayName.
#   - Enum property  : shows setting name, current value, all valid options (with
#                      $Recommended marked), and prompts the user to pick by index.
#                      Press S to skip the setting entirely.
#   - Free-form / no enum : applies $Recommended silently without prompting.
#   - Property absent : prints [INFO] and skips.
function Invoke-PropSelection {
    param(
        [string] $AdapterName,
        [string] $DisplayName,
        [string] $Recommended
    )

    $prop = Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $DisplayName }

    if (-not $prop) {
        Write-Host "  [INFO]  '$DisplayName' not available on this adapter - skipped"
        return
    }

    $valid = @($prop.ValidDisplayValues)

    if ($valid.Count -eq 0) {
        # Numeric / free-form setting - no enum to show, apply recommended silently
        try {
            Set-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $DisplayName `
                -DisplayValue $Recommended -ErrorAction Stop
            Write-Host "  [OK]    $DisplayName = $Recommended"
        } catch {
            Write-Warning "  [SKIP]  '$DisplayName' -- $($_.Exception.Message)"
        }
        return
    }

    # Enum property - list all options and prompt
    Write-Host "  $DisplayName  (current: $($prop.DisplayValue))"
    for ($i = 0; $i -lt $valid.Count; $i++) {
        $tag = if ($valid[$i] -eq $Recommended) { "  <- recommended" } else { "" }
        Write-Host ("    [{0}]  {1}{2}" -f $i, $valid[$i], $tag)
    }

    $chosen = $null
    do {
        $sel = (Read-Host "  Select [0-$($valid.Count - 1)], S to skip").Trim()
        if ($sel -match '^[Ss]$') {
            Write-Host "  [SKIP]  $DisplayName"
            return
        }
        if ($sel -match '^\d+$' -and [int]$sel -lt $valid.Count) {
            $chosen = $valid[[int]$sel]
        } else {
            Write-Host "  Invalid input, try again."
        }
    } while ($null -eq $chosen)

    try {
        Set-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $DisplayName `
            -DisplayValue $chosen -ErrorAction Stop
        Write-Host "  [OK]    $DisplayName = $chosen"
    } catch {
        Write-Warning "  [SKIP]  '$DisplayName' -- $($_.Exception.Message)"
    }
}

# ── Helper: Enable/Disable prompt for dedicated cmdlet settings ───────────────
#
# Shows setting name with [0] Disable / [1] Enable, marks which is recommended.
# Returns $true (Enable), $false (Disable), or $null if user pressed S to skip.
function Select-EnableDisable {
    param(
        [string] $SettingName,
        [bool]   $RecommendEnable
    )

    Write-Host "  $SettingName"
    Write-Host "    [0]  Disable$(if (-not $RecommendEnable) { '  <- recommended' })"
    Write-Host "    [1]  Enable$(if ($RecommendEnable) { '  <- recommended' })"

    do {
        $sel = (Read-Host "  Select [0/1], S to skip").Trim()
        if ($sel -match '^[Ss]$') {
            Write-Host "  [SKIP]  $SettingName"
            return $null
        }
        if ($sel -eq '0') { return $false }
        if ($sel -eq '1') { return $true }
        Write-Host "  Invalid input, try again."
    } while ($true)
}

Write-Host "Configure settings  (S = skip any setting)"
Write-Host ""

# ── Speed & Duplex ────────────────────────────────────────────────────────────
# X550-T2 is 10 GbE; 1 G matches GigE Vision cameras and avoids auto-negotiation
# surprises on 1 G switches.
Invoke-PropSelection $n "Speed & Duplex" "1.0 Gbps Full Duplex"

# ── Jumbo Frames ──────────────────────────────────────────────────────────────
# 9014 = 9000-byte payload + Ethernet/VLAN headers. Must also be enabled on the switch.
Invoke-PropSelection $n "JumboPacket" "9014 Bytes"

# ── Ring Buffers (X550 maximum = 4096) ───────────────────────────────────────
Invoke-PropSelection $n "Receive Buffers"  "4096"
Invoke-PropSelection $n "Transmit Buffers" "4096"

# ── Interrupt Moderation ──────────────────────────────────────────────────────
# Batching interrupts saves CPU but adds jitter; Disabled gives consistent frame timing.
Invoke-PropSelection $n "Interrupt Moderation" "Disabled"

# ── Flow Control ──────────────────────────────────────────────────────────────
# Pause frames can stall an entire link and cause frame drops on other cameras.
Invoke-PropSelection $n "Flow Control" "Disabled"

# ── Energy Efficient Ethernet ─────────────────────────────────────────────────
# EEE powers down the link during quiet periods; wake-up latency disrupts streams.
Invoke-PropSelection $n "Energy Efficient Ethernet" "Disabled"

# ── Receive Side Scaling ──────────────────────────────────────────────────────
# Distributes incoming camera streams across CPU cores.
$rssEnable = Select-EnableDisable "RSS (Receive Side Scaling)" $true
if ($null -ne $rssEnable) {
    try {
        Set-NetAdapterRss -Name $n -Enabled $rssEnable -ErrorAction Stop
        Write-Host "  [OK]    RSS = $(if ($rssEnable) { 'Enabled' } else { 'Disabled' })"
    } catch {
        Write-Warning "  [SKIP]  RSS -- $($_.Exception.Message)"
    }
}

# ── RSS Queue count ───────────────────────────────────────────────────────────
Invoke-PropSelection $n "Maximum Number of RSS Queues" "8"

# ── Large Send Offload ────────────────────────────────────────────────────────
# LSO targets TCP bulk transfers; GigE Vision uses UDP and LSO can interfere.
$lsoEnable = Select-EnableDisable "Large Send Offload (LSO)" $false
if ($null -ne $lsoEnable) {
    try {
        if ($lsoEnable) { Enable-NetAdapterLso  -Name $n -ErrorAction Stop }
        else             { Disable-NetAdapterLso -Name $n -ErrorAction Stop }
        Write-Host "  [OK]    LSO = $(if ($lsoEnable) { 'Enabled' } else { 'Disabled' })"
    } catch {
        Write-Warning "  [SKIP]  LSO -- $($_.Exception.Message)"
    }
}

# ── Checksum Offload ──────────────────────────────────────────────────────────
# Offloading checksum calculation to the NIC reduces CPU load; Rx & Tx Enabled recommended.
Invoke-PropSelection $n "TCP Checksum Offload (IPv4)" "Rx & Tx Enabled"
Invoke-PropSelection $n "UDP Checksum Offload (IPv4)" "Rx & Tx Enabled"

# ── Power Management ──────────────────────────────────────────────────────────
# Disable to prevent the OS from powering down the adapter during active capture.
$pmEnable = Select-EnableDisable "Power Management (allow OS to turn off adapter / wake on packet)" $false
if ($null -ne $pmEnable) {
    try {
        $pmVal = if ($pmEnable) { "Enabled" } else { "Disabled" }
        Set-NetAdapterPowerManagement -Name $n `
            -AllowComputerToTurnOffDevice $pmVal `
            -WakeOnMagicPacket $pmVal `
            -WakeOnPattern $pmVal -ErrorAction Stop
        Write-Host "  [OK]    Power Management = $pmVal"
    } catch {
        Write-Warning "  [SKIP]  Power Management -- $($_.Exception.Message)"
    }
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
} catch {
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
} catch {
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
