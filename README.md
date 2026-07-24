# Masked Switch Event Detector for SCOMP

ECE 2031 Summer 2026
Target board: Terasic DE10-Lite (Intel MAX 10 `10M50DAF484C7G`)

## Overview

`MaskedEventDetector` is a memory-mapped SCOMP peripheral for the ten
DE10-Lite slide switches. It replaces the original read-only switch
interface while retaining the ability to read the current switch positions.

The original switch peripheral only reported the positions present at the
instant software performed an `IN`. If a switch changed and returned to its
previous position before that read, software could miss the change. This
peripheral adds:

- two-stage synchronization of all physical switch inputs;
- detection of both rising and falling switch transitions;
- a programmable mask selecting which switches are monitored;
- sticky event flags that remember monitored changes;
- selective write-one-to-clear event handling; and
- event priority when a new event and a clear occur simultaneously.

The peripheral uses the existing SCOMP I/O bus and requires no new processor
instructions. SCOMP software controls it with ordinary `IN` and `OUT`
instructions.

## SCOMP I/O Interface

Only bits 9 through 0 correspond to physical switches. Bits 15 through 10
read as zero and are ignored on writes.

| Address | Name | Access | Description |
| --- | --- | --- | --- |
| `0x020` | `SW_CURRENT` | Read | Current synchronized values of `SW9..SW0` |
| `0x021` | `SW_MASK` | Write | Selects which switch changes can create events |
| `0x022` | `SW_EVENTS` | Read | Sticky event flags for monitored switch changes |
| `0x023` | `SW_CLEAR` | Write | Write-one-to-clear command for selected event flags |

### `SW_CURRENT` — address `0x020`

Reading this address returns the current synchronized switch positions.
A `1` means the corresponding physical switch is raised. Reading this
register has no effect on the event flags.

### `SW_MASK` — address `0x021`

Writing this address configures the monitoring mask:

- mask bit `1`: changes on that switch are recorded;
- mask bit `0`: changes on that switch are ignored.

The mask resets to zero. Changing the mask affects future switch changes and
does not erase events that are already stored.

### `SW_EVENTS` — address `0x022`

Reading this address returns the sticky event flags. A bit becomes `1` when
the corresponding monitored switch changes in either direction. It stays
`1` even if the switch returns to its previous position.

Reading `SW_EVENTS` does not clear it. Multiple switch events accumulate
until software explicitly clears them.

An event bit records that one or more changes occurred; it is not a counter.
Repeated changes on the same switch before a clear still produce one set bit.

### `SW_CLEAR` — address `0x023`

This is a write-one-to-clear interface:

- written bit `1`: clear the corresponding stored event;
- written bit `0`: preserve the corresponding stored event.

For example, if `SW_EVENTS = 0x0005`, writing `0x0001` to `SW_CLEAR`
produces `SW_EVENTS = 0x0004`.

## Event Logic

After synchronization, the peripheral compares the current sample with the
previous sample:

```text
changed             = current_switches XOR previous_switches
monitored_changes   = changed AND mask
events_next         = (events AND NOT clear_data) OR monitored_changes
```

Because `monitored_changes` is ORed after the clear operation, a new event
wins if a clear and a switch change occur in the same clock cycle.

During reset and synchronizer startup, event generation is suppressed so
that the physical switch positions present at startup do not create false
events. Reset also clears the mask and all stored event flags.

## Hardware Integration

The VHDL entity is `MaskedEventDetector` in [`switch.vhd`](switch.vhd).

| Port | Direction | Width | Connection |
| --- | --- | --- | --- |
| `CLOCK` | Input | 1 | SCOMP system clock (`clk_10MHz`) |
| `RESETN` | Input | 1 | Active-low system reset (`resetn`) |
| `SWITCHES` | Input | 10 | Physical `SW[9..0]` |
| `IO_READ` | Input | 1 | SCOMP `IO_READ` |
| `IO_WRITE` | Input | 1 | SCOMP `IO_WRITE` |
| `IO_ADDR` | Input | 11 | SCOMP `IO_ADDR[10..0]` |
| `IO_DATA` | Bidirectional | 16 | Shared SCOMP `IO_DATA[15..0]` |

The peripheral drives `IO_DATA` only during a valid read from `SW_CURRENT`
or `SW_EVENTS`. It otherwise drives high impedance so that SCOMP and the
other peripherals can share the bus.

The complete system is in
[`SCOMP_System_Copy.bdf`](SCOMP_System_Copy.bdf), and the Quartus top-level
entity must be `SCOMP_System_Copy`.

## SCOMP Programming Example

SCASM hexadecimal constants use the `&H` prefix:

```asm
SW_CURRENT: EQU &H020
SW_MASK:    EQU &H021
SW_EVENTS:  EQU &H022
SW_CLEAR:   EQU &H023

; Monitor SW2 only.
LOAD   SW2Bit
OUT    SW_MASK

; Remove stale events before beginning an operation.
LOAD   AllSwitchBits
OUT    SW_CLEAR

WaitForSW2:
    IN     SW_EVENTS
    AND    SW2Bit
    JZERO  WaitForSW2

; Acknowledge only the SW2 event.
LOAD   SW2Bit
OUT    SW_CLEAR

SW2Bit:        DW &H0004
AllSwitchBits: DW &H03FF
```

Current switch values can be read independently:

```asm
IN  SW_CURRENT
OUT LEDs
```

## Demonstration Application: Masked Reaction Game

[`MaskedReactionGame.asm`](MaskedReactionGame.asm) is the final SCOMP
demonstration application. Its assembled memory image is
[`MaskedReactionGame.mif`](MaskedReactionGame.mif).

Game sequence:

1. The player returns all switches to the down position.
2. Software rapidly cycles through target switches `SW0` through `SW7`.
3. Raising `SW9` by itself freezes and displays a target number.
4. Software writes a one-hot target value to `SW_MASK`.
5. The player lowers `SW9`, starting the reaction timer.
6. Changes on incorrect switches are ignored by the hardware mask.
7. A quick flick of the target switch sets its sticky `SW_EVENTS` bit.
8. Software reads the event, records the reaction time, and updates the
   accumulated score.
9. Software clears completed events through `SW_CLEAR` before the next
   round.

The right four HEX digits display the target during a round and the reaction
time afterward. The left two HEX digits display the accumulated reaction
time. Times are hexadecimal deciseconds, so `000A` represents 1.0 second.
Lower accumulated scores are better.

The game demonstrates every software-visible peripheral address:

| Game behavior | Peripheral feature |
| --- | --- |
| LEDs mirror the switches and SW9 starts a round | `SW_CURRENT` |
| Only the displayed target can finish the round | `SW_MASK` |
| A quick up/down flick is not missed | `SW_EVENTS` |
| Old events do not leak into later rounds | `SW_CLEAR` |

## Verification

Two self-checking VHDL testbenches are included:

- [`MaskedEventDetector_tb.vhd`](MaskedEventDetector_tb.vhd) verifies the
  peripheral independently.
- [`MaskedReactionGame_tb.vhd`](MaskedReactionGame_tb.vhd) runs the real
  SCOMP game program against the peripheral and accelerated behavioral
  models of the existing I/O devices.

The peripheral test covers:

- reset and synchronizer startup;
- synchronized current-value reads;
- rising- and falling-edge detection;
- masked and unmasked changes;
- sticky event accumulation;
- non-destructive event reads;
- selective write-one-to-clear behavior;
- mask changes that preserve existing events; and
- simultaneous clear/new-event priority.

The game integration test covers wrong-switch rejection, one-clock target
pulses, score accumulation, LED feedback, target wrapping, and sixteen
consecutive game rounds.

[`PeripheralSmokeTest.asm`](PeripheralSmokeTest.asm) is also included as a
simple board diagnostic. It displays current switches on the LEDs, displays
sticky event flags on the right HEX digits, and uses SW9 to clear events.

## Project Files

| File | Purpose |
| --- | --- |
| `MaskedEventDetector.qpf` | Quartus project file |
| `maskedevendemo.qsf` | Quartus revision, source, device, and pin assignments |
| `SCOMP_System_Copy.bdf` | Complete SCOMP system top level |
| `switch.vhd` | `MaskedEventDetector` peripheral implementation |
| `SCOMP.vhd` | SCOMP processor and program-memory initialization |
| `MaskedReactionGame.asm` | Final demonstration source code |
| `MaskedReactionGame.mif` | Assembled SCOMP program memory |
| `MaskedEventDetector_tb.vhd` | Peripheral self-checking testbench |
| `MaskedReactionGame_tb.vhd` | Full game integration testbench |
| `PeripheralSmokeTest.asm` | Simple physical-board diagnostic |
| `PLL.*`, `TIMER.vhd`, `clk_div.vhd` | Clock, reset, and timer support |
| `HEX_DISP*`, `DIG_OUT.vhd` | Existing HEX-display and LED peripherals |

## Building the Project

1. Open `MaskedEventDetector.qpf` in Quartus Prime.
2. Confirm that the selected device is `10M50DAF484C7G`.
3. Confirm that the top-level entity is `SCOMP_System_Copy`.
4. Confirm that `SCOMP.vhd` initializes program memory from
   `MaskedReactionGame.mif`.
5. Run **Processing → Start Compilation**.
6. Open **Tools → Programmer**, select the USB-Blaster in JTAG mode, enable
   **Program/Configure**, and program the generated `.sof`.
7. Press and release `KEY0` to reset SCOMP and begin the game.

Quartus-generated `db`, `incremental_db`, `output_files`, and `simulation`
directories are intentionally not required as source files and should not
be included in the assignment ZIP.

## Team

- Vikram Devaraju
- Mauricio Minaya
- Anna Yang
- Nil Patel
- Zaara Syeda
