#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restores network interface settings from a JSON file created by Save-NetworkState.ps1.

.DESCRIPTION
    Reads a NetworkState JSON snapshot and applies every stored value back to the
    matching network adapter: NIC advanced properties, RSS, LSO, flow control,
    power management, the AFD registry key, IPv4 addresses, and the adapter name.

.PARAMETER JsonPath
    Path to a NetworkState_*.json file. If omitted, the script lists available
    snapshots in its own directory and prompts for a selection.

.EXAMPLE
    .\Restore-NetworkState.ps1
    .\Restore-NetworkState.ps1 -JsonPath "C:\Backup\NetworkState_Ethernet_2_2024-01-15T09-00-00.json"
#>

param(
    [string]$JsonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Locate and load the JSON file ─────────────────────────────────────────────
if (-not $JsonPath) {
    $searchDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
    $files = @(Get-ChildItem -Path $searchDir -Filter "NetworkState_*.json" | Sort-Object Name)
    if ($files.Count -eq 0) {
        throw "No NetworkState_*.json files found in '$searchDir'. Use -JsonPath to specify one explicitly."
    }
    Write-Host "`nAvailable snapshots:"
    for ($i = 0; $i -lt $files.Count; $i++) {
        Write-Host "  [$i]  $($files[$i].Name)"
    }
    $sel = [int](Read-Host "Select number")
    if ($sel -lt 0 -or $sel -ge $files.Count) { throw "Invalid selection." }
    $JsonPath = $files[$sel].FullName
}

if (-not (Test-Path $JsonPath)) { throw "File not found: $JsonPath" }

try {
    $state = Get-Content -Path $JsonPath -Raw | ConvertFrom-Json
} catch {
    throw "Failed to parse '$JsonPath': $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Snapshot : $(Split-Path $JsonPath -Leaf)"
Write-Host "Saved at : $($state.SavedAt)"
Write-Host "Adapter  : $($state.AdapterName)  (InterfaceIndex $($state.InterfaceIndex))"
Write-Host ""

# ── Locate adapter ────────────────────────────────────────────────────────────
# InterfaceIndex is the primary key — it survives renames. Fall back to name if
# the index changed (possible after a reboot), then prompt if neither matches.
$adapter = Get-NetAdapter | Where-Object { $_.InterfaceIndex -eq $state.InterfaceIndex }

if (-not $adapter) {
    Write-Warning "InterfaceIndex $($state.InterfaceIndex) not found - trying by name '$($state.AdapterName)'..."
    $adapter = Get-NetAdapter | Where-Object { $_.Name -eq $state.AdapterName }
}

if (-not $adapter) {
    Write-Warning "Adapter '$($state.AdapterName)' not found by name either. Please select manually:"
    Get-NetAdapter | Sort-Object InterfaceIndex |
        Format-Table -AutoSize InterfaceIndex, Name, InterfaceDescription, Status
    $manualIdx = [int](Read-Host "Enter InterfaceIndex")
    $adapter = Get-NetAdapter | Where-Object { $_.InterfaceIndex -eq $manualIdx }
    if (-not $adapter) { throw "Adapter not found." }
}

$n = $adapter.Name
Write-Host "Target: '$n'  (InterfaceIndex $($adapter.InterfaceIndex))`n"

# ── Helper ────────────────────────────────────────────────────────────────────
function Set-Prop([string]$adapterName, [string]$displayName, $value) {
    if ($null -eq $value) { return }
    try {
        Set-NetAdapterAdvancedProperty -Name $adapterName `
            -DisplayName $displayName -DisplayValue $value -ErrorAction Stop
        Write-Host "  [OK]    $displayName = $value"
    } catch {
        Write-Warning "  [SKIP]  '$displayName': $($_.Exception.Message)"
    }
}

# ── Advanced properties ───────────────────────────────────────────────────────
Write-Host "Advanced properties:"
foreach ($prop in $state.AdvancedProperties.PSObject.Properties) {
    Set-Prop $n $prop.Name $prop.Value
}

# ── RSS ───────────────────────────────────────────────────────────────────────
if ($null -ne $state.RSS) {
    try {
        Set-NetAdapterRss -Name $n -Enabled ([bool]$state.RSS.Enabled) -ErrorAction Stop
        Write-Host "  [OK]    RSS Enabled = $($state.RSS.Enabled)"
    } catch { Write-Warning "  [SKIP]  RSS: $($_.Exception.Message)" }
}

# ── LSO ───────────────────────────────────────────────────────────────────────
# Enable/Disable-NetAdapterLso acts on both protocols at once. Re-enable if either
# was on; only fully disable when both were off.
if ($null -ne $state.LSO) {
    try {
        if ($state.LSO.IPv4Enabled -or $state.LSO.IPv6Enabled) {
            Enable-NetAdapterLso -Name $n -ErrorAction Stop
            Write-Host "  [OK]    LSO = Enabled"
        } else {
            Disable-NetAdapterLso -Name $n -ErrorAction Stop
            Write-Host "  [OK]    LSO = Disabled"
        }
    } catch { Write-Warning "  [SKIP]  LSO: $($_.Exception.Message)" }
}

# ── Flow Control ──────────────────────────────────────────────────────────────
if ($null -ne $state.FlowControl) {
    try {
        Set-NetAdapterFlowControl -Name $n `
            -AutoNegotiate ([bool]$state.FlowControl.AutoNegotiate) `
            -RxEnabled     ([bool]$state.FlowControl.RxEnabled) `
            -TxEnabled     ([bool]$state.FlowControl.TxEnabled) -ErrorAction Stop
        Write-Host "  [OK]    Flow Control restored  (AutoNeg=$($state.FlowControl.AutoNegotiate)  Rx=$($state.FlowControl.RxEnabled)  Tx=$($state.FlowControl.TxEnabled))"
    } catch { Write-Warning "  [SKIP]  Flow Control: $($_.Exception.Message)" }
}

# ── Power Management ──────────────────────────────────────────────────────────
# Values were stored as strings ("Enabled", "Disabled", "NotSupported", …).
# Only "Enabled" and "Disabled" can be written back; skip "NotSupported" and
# anything else — those reflect hardware capability, not a configurable choice.
if ($null -ne $state.PowerManagement) {
    try {
        $pmSplat = @{ Name = $n; ErrorAction = "Stop" }
        $pm = $state.PowerManagement
        if ($pm.AllowComputerToTurnOffDevice -in "Enabled", "Disabled") {
            $pmSplat["AllowComputerToTurnOffDevice"] = $pm.AllowComputerToTurnOffDevice
        }
        if ($pm.WakeOnMagicPacket -in "Enabled", "Disabled") {
            $pmSplat["WakeOnMagicPacket"] = $pm.WakeOnMagicPacket
        }
        if ($pm.WakeOnPattern -in "Enabled", "Disabled") {
            $pmSplat["WakeOnPattern"] = $pm.WakeOnPattern
        }
        Set-NetAdapterPowerManagement @pmSplat
        Write-Host "  [OK]    Power Management restored"
    } catch { Write-Warning "  [SKIP]  Power Management: $($_.Exception.Message)" }
}

# ── AFD socket receive buffer (registry) ─────────────────────────────────────
$afdKey = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
if ($null -ne $state.AFD.DefaultReceiveWindow) {
    if (-not (Test-Path $afdKey)) { New-Item -Path $afdKey -Force | Out-Null }
    Set-ItemProperty -Path $afdKey -Name "DefaultReceiveWindow" `
        -Value ([int]$state.AFD.DefaultReceiveWindow) -Type DWord
    Write-Host "  [OK]    AFD DefaultReceiveWindow = $($state.AFD.DefaultReceiveWindow) bytes"
} else {
    # null in the snapshot means the key was absent at save time — remove it to
    # restore the Windows built-in default rather than leaving a stale value.
    Remove-ItemProperty -Path $afdKey -Name "DefaultReceiveWindow" -ErrorAction SilentlyContinue
    Write-Host "  [OK]    AFD DefaultReceiveWindow removed (Windows built-in default restored)"
}

# ── IPv4 addresses ────────────────────────────────────────────────────────────
# @(...| Where-Object ...) guards against two PS 5.1 ConvertFrom-Json quirks:
#   - a single-element array is collapsed to a scalar
#   - an empty array [] is deserialised as $null, making @($null).Count = 1
$savedIPs = @($state.IPv4Addresses | Where-Object { $null -ne $_ })
if ($savedIPs.Count -gt 0) {
    Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
    Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" `
        -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
    foreach ($ip in $savedIPs) {
        New-NetIPAddress -InterfaceAlias $n `
            -IPAddress $ip.IPAddress -PrefixLength ([int]$ip.PrefixLength) | Out-Null
        Write-Host "  [OK]    IP = $($ip.IPAddress)/$($ip.PrefixLength)"
    }
}

# ── Rename adapter (must be last — all prior cmdlets reference the current name) ─
if ($adapter.Name -ne $state.AdapterName) {
    try {
        Rename-NetAdapter -Name $n -NewName $state.AdapterName -ErrorAction Stop
        Write-Host "  [OK]    Renamed '$n'  ->  '$($state.AdapterName)'"
        $n = $state.AdapterName
    } catch { Write-Warning "  [SKIP]  Rename: $($_.Exception.Message)" }
}

Write-Host ""
Write-Host "Done."
Write-Host "  Disable/re-enable the adapter (or reboot) for NIC property changes to take effect."
Write-Host "  AFD DefaultReceiveWindow change requires a reboot."
