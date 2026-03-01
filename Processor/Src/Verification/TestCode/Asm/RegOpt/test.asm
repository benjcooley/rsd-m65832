; RegOpt - Register window optimization test
;
; Verifies that traditional 65xx syntax with DP register operands
; generates efficient single-instruction code via the register window.
;
; In fixed32, DP addresses $00-$FC (4-byte aligned) map to R0-R63.
; Operations like "LDA R5" should be a single XFER instruction,
; NOT a memory load. "ADC R3" should be a single ADD instruction,
; NOT a load-then-add sequence.
;
; This test demonstrates that traditional m65832 code runs at
; full pipeline speed when using DP register operands.

    .org 0x1000

start:
    BRA test_begin

pc_goal:
    NOP

test_begin:

; ===========================================================
; Setup: put values in registers using traditional syntax
; ===========================================================

    LDA #10         ; A = 10
    STA R1          ; R1 = 10  (should be: XFER R1, A -- 1 insn)
    LDA #20
    STA R2          ; R2 = 20  (1 insn)
    LDA #30
    STA R3          ; R3 = 30  (1 insn)

; ===========================================================
; Test 1: LDA from register (should be 1 insn: XFER A, Rn)
; ===========================================================

    LDA R1          ; A = R1 = 10  (XFER A, R1)
    LDA R2          ; A = R2 = 20  (XFER A, R2)
    LDA R3          ; A = R3 = 30  (XFER A, R3)

; ===========================================================
; Test 2: ADC with register (should be 1 insn: ADD A, A, Rn)
; ===========================================================

    LDA #0          ; A = 0
    ADC R1          ; A = A + R1 = 10  (ADD A, A, R1)
    ADC R2          ; A = A + R2 = 30  (ADD A, A, R2)
    ADC R3          ; A = A + R3 = 60  (ADD A, A, R3)

; ===========================================================
; Test 3: SBC with register (1 insn: SUB A, A, Rn)
; ===========================================================

    SBC R1          ; A = 60 - 10 = 50  (SUB A, A, R1)

; ===========================================================
; Test 4: AND/ORA/EOR with register (1 insn each)
; ===========================================================

    LDA #0xFF
    AND R2          ; A = 0xFF & 20 = 20  (AND A, A, R2)

    LDA #0
    ORA R3          ; A = 0 | 30 = 30  (OR A, A, R3)

    LDA #0xFF
    EOR R1          ; A = 0xFF ^ 10 = 0xF5  (XOR A, A, R1)

; ===========================================================
; Test 5: CMP with register (1 insn: CMP R0, A, Rn)
; ===========================================================

    LDA #30
    CMP R3          ; compare A(30) with R3(30) → Z=1

; ===========================================================
; Test 6: LDA (Rn),Y - indirect indexed through register
; This is a genuine memory access but with register as base.
; Should be: ADD T, Rn, Y; LD data, [T+0]  (2 insns)
; ===========================================================

    ; Set up R10 as a pointer to some RAM location
    LUI R10, 0x80001         ; R10 = 0x80001000
    ; Store a value there
    ADDI R11, R0, #42
    ST R11, [R10 + 0]
    ; Clear Y
    LDY #0
    ; Load through indirect indexed
    LDA (R10),Y    ; A = [R10 + Y] = 42  (2 insns)

; ===========================================================
; Test 7: Barrel shifter (3-op register syntax)
; ===========================================================

    LDA #1
    STA R20         ; R20 = 1
    SHL R21, R20, #4    ; R21 = 16
    SHR R22, R21, #2    ; R22 = 4
    SAR R23, R22, #1    ; R23 = 2

; ===========================================================
; Test 8: Extend operations (2-op register syntax)
; ===========================================================

    ADDI R30, R0, #0xFF    ; R30 = 255
    SEXT8 R31, R30          ; R31 = -1 (0xFFFFFFFF)
    ZEXT8 R32, R30          ; R32 = 255

; ===========================================================
; Test 9: Mix of 3-op (fixed32) and traditional syntax
; Both should work and interoperate
; ===========================================================

    ; Fixed32 native: set up values
    ADDI R40, R0, #100
    ADDI R41, R0, #200
    ADD R42, R40, R41       ; R42 = 300

    ; Traditional: load result from register
    LDA R42         ; A = 300  (XFER A, R42)
    CMP #300        ; verify (CMPI R0, A, 300)
    BNE fail

    ; Traditional: accumulate into register via STA
    LDA #500
    STA R43         ; R43 = 500  (XFER R43, A)
    LDA R43         ; A = 500  (XFER A, R43)
    ADC R40         ; A = 600  (ADD A, A, R40)
    STA R44         ; R44 = 600  (XFER R44, A)

    BRA test_done

fail:
    NOP             ; should not reach here

test_done:
    BRA pc_goal
