# Configure-CameraInterface.ps1

PowerShell script that configures a Windows network interface for multicamera
capture over GigE Vision (or similar UDP-based camera protocols).
Tuned for the **Intel X550-T2** NIC driver; settings gracefully skip if the
driver doesn't expose a given property.

## Requirements

- Windows 10 / Server 2016 or later
- PowerShell 5.1+
- **Run as Administrator** (required for NIC settings and registry writes)
- Intel X550-T2 driver installed (inbox or from Intel)

## Usage

```powershell
.\Configure-CameraInterface.ps1
```

The script is fully interactive — no command-line arguments needed.
It will prompt for:

| Prompt | Example |
|---|---|
| Adapter InterfaceIndex | `3` (shown in the table printed at startup) |
| New interface name | `GigE-Cameras` |
| Subnet octet `x` for `192.168.x.1` | `10`  →  assigns `192.168.10.1/24` |

## Settings Applied

### NIC Advanced Properties (Intel X550-T2 driver names)

| Setting | Value | Reason |
|---|---|---|
| Speed & Duplex | 1.0 Gbps Full Duplex | Matches GigE Vision camera spec; avoids auto-negotiation surprises |
| Jumbo Packet | 9014 Bytes | Reduces CPU overhead per image payload; enable on the switch too |
| Receive Buffers | 4096 | X550 maximum; absorbs burst traffic from multiple cameras |
| Transmit Buffers | 4096 | X550 maximum |
| Interrupt Moderation | Disabled | Eliminates interrupt-batching jitter for consistent frame timing |
| Flow Control | Disabled (Tx + Rx) | Prevents pause frames from stalling the entire link |
| Energy Efficient Ethernet | Disabled | EEE wake-up latency disrupts continuous streams |
| RSS | Enabled, 8 queues | Spreads incoming camera streams across CPU cores |
| Large Send Offload (LSO) | Disabled | LSO targets TCP bulk transfers; can interfere with UDP packet timing |
| TCP/UDP Checksum Offload | Rx & Tx Enabled | Offloads checksum calculation to NIC, reduces CPU load |
| Power Management | Disabled | Prevents the OS from powering down the adapter |

### System-wide

| Setting | Value | Reason |
|---|---|---|
| AFD `DefaultReceiveWindow` | 16 MB | Default kernel socket receive buffer — prevents silent UDP drops during burst traffic (see below) |
| Static IP | `192.168.x.1/24` | Dedicated subnet isolates camera traffic; no DHCP dependency |
| Adapter name | User-supplied | Makes the interface identifiable in logs and SDK config |

## What is the AFD Socket Buffer?

`afd.sys` (*Ancillary Function Driver*) is the Windows kernel driver that
implements Winsock. It holds each socket's incoming data in a kernel-side ring
buffer until the application reads it out.

```
Camera SDK  →  winsock DLL  →  afd.sys  →  tcpip.sys  →  NIC driver  →  wire
                                   ↑
                      receive buffer lives here (kernel pool)
```

When cameras send image bursts faster than the SDK thread can call
`recvfrom()`, this buffer is the only thing preventing packet loss. The Windows
default (~64 KB) can fill in under 1 ms at GigE line rate with multiple cameras.

The registry key
`HKLM\SYSTEM\CurrentControlSet\Services\AFD\Parameters\DefaultReceiveWindow`
sets the default size for every new socket. Camera SDKs that do not call
`setsockopt(SO_RCVBUF)` explicitly inherit this value. Setting it to 16 MB
gives the kernel ~128 ms of headroom per socket at full GigE line rate.

This is a system-wide setting — it applies to all sockets on the machine, not
just camera sockets. 16 MB is a well-established safe value for GigE Vision
workstations.

## After Running

| Action | When required |
|---|---|
| Disable / re-enable adapter | NIC advanced property changes |
| **Reboot** | AFD `DefaultReceiveWindow` registry change |

The static IP assignment and adapter rename take effect immediately.

## Verifying Driver Property Names

Intel occasionally changes property display names between driver versions.
To list the exact names and current values exposed by your installed driver:

```powershell
Get-NetAdapterAdvancedProperty -Name "<adapter-name>" | Select DisplayName, DisplayValue
```

Any property the script cannot match is reported as `[SKIP]` and does not abort
the rest of the configuration.
