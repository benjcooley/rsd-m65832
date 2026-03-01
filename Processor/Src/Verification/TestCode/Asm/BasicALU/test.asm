; BasicALU - M65832 vcore first test program
;
; Tests basic integer ALU operations and control flow.
; Starts at reset vector 0x1000, exercises ALU, then
; jumps to PC_GOAL (0x8000_1004) to signal test completion.
;
; Memory map:
;   0x0000_1000 - ROM (reset vector, code starts here)
;   0x8000_0000 - RAM (PC_GOAL target lives here)

    .org 0x1000

; ---- Entry point (reset vector) ----
; Skip past 0x1004 (which is where PC_GOAL will match)
start:
    BRA test_begin

; 0x1004: This is the PC_GOAL target.
; When PC reaches here, the Verilator testbench will stop the simulation.
pc_goal:
    NOP

; ---- Test code begins at 0x1008 ----
test_begin:

; Test 1: Load immediate via ADDI
    ADDI R1, R0, #1        ; R1 = 1
    ADDI R2, R0, #2        ; R2 = 2
    ADDI R3, R0, #42       ; R3 = 42

; Test 2: Register-register ADD
    ADD R4, R1, R2          ; R4 = 1 + 2 = 3
    ADD R5, R3, R4          ; R5 = 42 + 3 = 45

; Test 3: SUB
    SUB R6, R5, R3          ; R6 = 45 - 42 = 3
    SUBI R7, R5, #10        ; R7 = 45 - 10 = 35

; Test 4: Logical operations
    ADDI R8, R0, #0xFF      ; R8 = 0xFF
    ADDI R9, R0, #0x0F      ; R9 = 0x0F
    AND R10, R8, R9         ; R10 = 0xFF & 0x0F = 0x0F
    OR R11, R8, R9          ; R11 = 0xFF | 0x0F = 0xFF
    XOR R12, R8, R9         ; R12 = 0xFF ^ 0x0F = 0xF0

; Test 5: LUI (load upper immediate)
    LUI R13, 0xDEADB        ; R13 = 0xDEADB000
    ORI R13, R13, #0xEEF    ; R13 = 0xDEADBEEF

; Test 6: MOV (transfer)
    MOV R14, R13            ; R14 = 0xDEADBEEF

; Test 7: Shifts
    ADDI R15, R0, #1        ; R15 = 1
    SHL R16, R15, #4        ; R16 = 1 << 4 = 16
    SHR R17, R16, #2        ; R17 = 16 >> 2 = 4

; Test 8: Compare (sets flags, result discarded)
    CMP R4, R6              ; compare R4 (3) vs R6 (3) -> Z=1

; Test 9: SLT (set less than)
    SLT R18, R1, R2         ; R18 = (1 < 2) = 1
    SLT R19, R2, R1         ; R19 = (2 < 1) = 0

; Test 10: Zero register behavior
    ADD R20, R0, R0         ; R20 = 0 (zero + zero)
    ADDI R0, R1, #999       ; R0 should stay 0 (writes discarded)

; ---- All tests done, jump to PC_GOAL ----
    BRA pc_goal
