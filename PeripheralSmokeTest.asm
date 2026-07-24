; PeripheralSmokeTest.asm
;
; Physical-board smoke test for the MaskedEventDetector peripheral.
;
; SW0-SW8 are monitored for changes.
; SW9 acknowledges and clears all currently displayed event bits.
; LEDs show the synchronized current switch positions.
; The right four HEX digits show the sticky event flags.

ORG 0

    ; Monitor SW0-SW8. SW9 is reserved as the clear control.
    LOAD   MonitoredMask
    OUT    SW_MASK

    ; Start with no pending event flags.
    LOAD   AllSwitchBits
    OUT    SW_CLEAR

MainLoop:
    ; Give continuous visual feedback of the physical switch positions.
    IN     SW_CURRENT
    OUT    LEDs

    ; SW9 is not in the monitoring mask. When raised, it acknowledges
    ; and clears exactly the event flags that are currently pending.
    AND    ClearSwitch
    JNZ    ClearEvents

    ; Display sticky event flags on the right four HEX digits.
    IN     SW_EVENTS
    OUT    Hex0
    JUMP   MainLoop

ClearEvents:
    IN     SW_EVENTS
    OUT    SW_CLEAR

WaitForClearRelease:
    ; Wait for SW9 to return low so one deliberate movement performs
    ; one clear operation rather than clearing continuously.
    IN     SW_CURRENT
    OUT    LEDs
    AND    ClearSwitch
    JNZ    WaitForClearRelease

    IN     SW_EVENTS
    OUT    Hex0
    JUMP   MainLoop

; Useful values
MonitoredMask: DW &B0111111111
ClearSwitch:   DW &B1000000000
AllSwitchBits: DW &B1111111111

; Existing SCOMP peripheral addresses
LEDs:          EQU 001
Hex0:          EQU 004

; MaskedEventDetector addresses
SW_CURRENT:    EQU &H020
SW_MASK:       EQU &H021
SW_EVENTS:     EQU &H022
SW_CLEAR:      EQU &H023
