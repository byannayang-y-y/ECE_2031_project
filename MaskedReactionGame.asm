; MaskedReactionGame.asm
;
; Final demonstration program for the MaskedEventDetector peripheral.
;
; Game play
; ---------
; 1. Return all switches to the down position.
; 2. Raise SW9 by itself to freeze a rapidly changing target.
; 3. The right four HEX digits show a target switch number from 0 to 7.
; 4. Lower SW9. The reaction timer begins.
; 5. Flick the indicated target switch. It may be returned low immediately:
;    the hardware event register remembers the change.
; 6. The right HEX digits show the round time in deciseconds. The left two
;    HEX digits show the accumulated time (lower is better).
;
; Only the selected target bit is enabled in SW_MASK. Moving a different
; switch therefore cannot finish the round.

ORG 0

Start:
    LOADI  0
    STORE  Score
    OUT    Hex0
    OUT    Hex1

    ; Begin the rapid target cycle at SW0.
    LOADI  1
    STORE  TargetMask
    LOADI  0
    STORE  TargetNumber

    ; Disable monitoring and discard any power-up events.
    OUT    SW_MASK
    LOAD   AllSwitchBits
    OUT    SW_CLEAR


; A new round cannot begin until every physical switch is down.
WaitAllDown:
    IN     SW_CURRENT
    OUT    LEDs
    JNZ    WaitAllDown

    ; Changes made while returning the switches to zero must not leak into
    ; the next round. Clear after all switches have reached zero.
    LOADI  0
    OUT    SW_MASK
    LOAD   AllSwitchBits
    OUT    SW_CLEAR


; Advance the target as quickly as SCOMP can execute. Human timing when SW9
; is raised makes the selected target unpredictable.
RandomizeTarget:
    IN     SW_CURRENT
    OUT    LEDs
    STORE  SwitchState

    AND    StartSwitch
    JNZ    CheckStart

    CALL   AdvanceTarget
    JUMP   RandomizeTarget


; A round starts only when SW9, and no other switch, is raised.
CheckStart:
    LOAD   SwitchState
    SUB    StartSwitch
    JNZ    WaitAllDown

    ; Freeze and display the selected target, then monitor only that bit.
    LOAD   TargetNumber
    OUT    Hex0
    LOAD   TargetMask
    OUT    SW_MASK


; SW9 must be released before reaction timing begins. Events made while the
; target is being displayed are cleared when SW9 reaches zero.
WaitStartRelease:
    IN     SW_CURRENT
    OUT    LEDs
    AND    StartSwitch
    JNZ    WaitStartRelease

    LOAD   AllSwitchBits
    OUT    SW_CLEAR
    OUT    Timer


; The processor reads the sticky event register, not the live switch value.
; Therefore a quick up/down flick remains detectable.
WaitForTarget:
    IN     SW_CURRENT
    OUT    LEDs

    IN     SW_EVENTS
    AND    TargetMask
    JZERO  WaitForTarget


; A correct target event ends the round. The timer counts in deciseconds.
TargetHit:
    IN     Timer
    STORE  RoundTime
    ADD    Score
    STORE  Score
    OUT    Hex1

    ; Show the most recent reaction time on the right four HEX digits.
    LOAD   RoundTime
    OUT    Hex0

    ; Stop monitoring and acknowledge the completed target event.
    LOADI  0
    OUT    SW_MASK
    LOAD   AllSwitchBits
    OUT    SW_CLEAR
    JUMP   WaitAllDown


; Cycle through the one-hot target masks 1, 2, 4, ... 128, then wrap.
AdvanceTarget:
    LOAD   TargetMask
    AND    Bit7
    JNZ    WrapTarget

    LOAD   TargetMask
    SHIFT  1
    STORE  TargetMask

    LOAD   TargetNumber
    ADDI   1
    STORE  TargetNumber
    RETURN

WrapTarget:
    LOADI  1
    STORE  TargetMask
    LOADI  0
    STORE  TargetNumber
    RETURN


; Game state
Score:          DW 0
TargetMask:     DW 1
TargetNumber:   DW 0
SwitchState:    DW 0
RoundTime:      DW 0

; Useful bit masks
Bit7:           DW &H0080
StartSwitch:    DW &H0200
AllSwitchBits:  DW &H03FF

; Existing SCOMP peripheral addresses
LEDs:           EQU 001
Timer:          EQU 002
Hex0:           EQU 004
Hex1:           EQU 005

; MaskedEventDetector addresses
SW_CURRENT:     EQU &H020
SW_MASK:        EQU &H021
SW_EVENTS:      EQU &H022
SW_CLEAR:       EQU &H023
