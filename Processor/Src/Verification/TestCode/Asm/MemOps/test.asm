; MemOps - Memory operations and subroutine test for M65832 vcore
;
; Tests:
;   - Direct page loads/stores (register window: Rn notation)
;   - Memory load/store through base+offset
;   - Stack-based subroutine calls with JSR/RTS
;   - SEXT/ZEXT pseudo-instructions
;   - LUI/ORI constant loading patterns
;   - Multi-level subroutine calls

    .org 0x1000

start:
    BRA test_begin

pc_goal:
    NOP

test_begin:

; ===========================================================
; Initialize SP and D for memory operations
; ===========================================================

    ; SP = 0x80010000 (top of RAM)
    LUI SP, 0x80010

    ; D = 0 (direct page base at address 0 -- register window mode)
    ADDI D, R0, #0

    ; B = 0x80000000 (base for absolute addressing into RAM)
    LUI B, 0x80000

; ===========================================================
; Test 1: Register-to-register via MOV
; ===========================================================

    ADDI R1, R0, #100
    ADDI R2, R0, #200
    MOV R3, R1              ; R3 = 100
    MOV R4, R2              ; R4 = 200
    ADD R5, R3, R4          ; R5 = 300

; ===========================================================
; Test 2: Store and reload via RAM (B+offset)
; ===========================================================

    ADDI A, R0, #0x42       ; A = 0x42
    ST A, [B + 0]           ; store to RAM[B+0]
    ADDI A, R0, #0          ; clear A
    LD A, [B + 0]           ; reload A, should be 0x42

; ===========================================================
; Test 3: Stack push/pull round-trip
; ===========================================================

    ADDI R10, R0, #111
    ADDI R11, R0, #222
    ADDI R12, R0, #333

    PUSH R10                ; push 111
    PUSH R11                ; push 222
    PUSH R12                ; push 333

    PULL R15                ; R15 = 333 (LIFO)
    PULL R14                ; R14 = 222
    PULL R13                ; R13 = 111

    ; Verify: R13=111, R14=222, R15=333

; ===========================================================
; Test 4: JSR/RTS with single-level call
; ===========================================================

    ADDI A, R0, #0          ; A = 0
    JSR add_ten             ; call subroutine (A += 10)
    ; A should be 10 now

; ===========================================================
; Test 5: Two-level nested JSR/RTS
; ===========================================================

    ADDI A, R0, #5          ; A = 5
    JSR double_and_add      ; call (A = A*2 + 10 = 20)
    ; A should be 20

; ===========================================================
; Test 6: LUI+ORI for 32-bit constant, verify with CMP
; ===========================================================

    LDA #0xCAFEBABE
    CMP #0                  ; just verify A is non-zero (NE)
    BNE test6_ok
    NOP                     ; should not reach here
test6_ok:

; ===========================================================
; Test 7: SEXT8 / ZEXT8
; ===========================================================

    ADDI R1, R0, #0xFF      ; R1 = 255
    SEXT8 R2, R1            ; R2 = -1 (0xFFFFFFFF)
    ZEXT8 R3, R1            ; R3 = 255 (0x000000FF)

    ADDI R4, R0, #0x80      ; R4 = 128
    SEXT8 R5, R4            ; R5 = -128 (0xFFFFFF80)
    ZEXT8 R6, R4            ; R6 = 128 (0x00000080)

; ===========================================================
; Test 8: Memory array loop
; Store values 1..8 to RAM, then sum them
; ===========================================================

    ; Store 1..8 starting at B+$100
    ADDI R1, R0, #1         ; counter
    ADDI R2, R0, #0         ; offset (in words)

store_loop:
    ; Compute address: B + 0x100 + R2*4
    ; For simplicity, just use incrementing offset
    ADD R3, B, R2           ; R3 = B + offset
    ST R1, [R3 + 0x100]    ; store R1 at B+0x100+offset
    ADDI R1, R1, #1         ; counter++
    ADDI R2, R2, #4         ; offset += 4 (word size)
    MOV A, R1
    CMP #9                  ; done when counter == 9
    BNE store_loop

    ; Sum them back
    ADDI R1, R0, #0         ; sum = 0
    ADDI R2, R0, #0         ; offset = 0
    ADDI R4, R0, #8         ; count = 8

sum_loop:
    ADD R3, B, R2
    LD R5, [R3 + 0x100]    ; load value
    ADD R1, R1, R5          ; sum += value
    ADDI R2, R2, #4
    SUBI R4, R4, #1
    BNE sum_loop            ; loop while count != 0

    ; R1 should be 1+2+3+4+5+6+7+8 = 36
    MOV A, R1
    CMP #36
    BEQ test_done
    ; If we get here, test failed
    NOP

; ---- All tests done ----
test_done:
    BRA pc_goal

; ===========================================================
; Subroutines
; ===========================================================

; add_ten: A = A + 10
add_ten:
    ADDI A, A, #10
    RTS

; double_and_add: A = A * 2 + 10
; Calls add_ten internally (nested JSR)
double_and_add:
    ; Save return address (T register) before nested call
    PUSH T
    ADD A, A, A             ; A = A * 2
    JSR add_ten             ; A = A + 10 (this clobbers T)
    ; Restore return address
    PULL T
    RTS
