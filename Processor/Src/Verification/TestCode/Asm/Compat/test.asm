; Compat - Backward compatibility test for m65f32asm
;
; Every syntax pattern accepted by the original m65832as assembler
; in 32-bit mode (W=11) must assemble correctly here.
;
; The fixed32 assembler may decompose complex addressing modes into
; multiple instructions, but the semantics must be equivalent.
;
; DP addresses $00-$FC (4-byte aligned) map to R0-R63.
; B+16 means B register + 16-bit offset.

    .org 0x1000

start:
    BRA test_begin

pc_goal:
    NOP

test_begin:

; ===========================================================
; Section 1: DP register operands via hex notation
; Original syntax: LDA $04 means load from R1
; $00=R0, $04=R1, $08=R2, ... $FC=R63
; ===========================================================

    ; Store known values into registers via Rn notation
    ADDI R1, R0, #10       ; R1 = 10
    ADDI R2, R0, #20       ; R2 = 20
    ADDI R3, R0, #30       ; R3 = 30
    ADDI R8, R0, #80       ; R8 = 80

    ; Now access them via $XX hex DP notation (original syntax)
    LDA $04                 ; A = R1 = 10  (DP $04 = R1)
    LDA $08                 ; A = R2 = 20  (DP $08 = R2)
    LDA $0C                 ; A = R3 = 30  (DP $0C = R3)
    LDA $20                 ; A = R8 = 80  (DP $20 = R8)

    ; Store via $XX DP notation
    LDA #99
    STA $04                 ; R1 = 99 (STA $04 = store to R1)

    ; Load back and verify
    LDA $04                 ; A should be 99

; ===========================================================
; Section 2: DP register operands via Rn notation
; This is the preferred 32-bit mode syntax
; ===========================================================

    LDA R1                  ; same as LDA $04
    LDA R2                  ; same as LDA $08
    LDA R3                  ; same as LDA $0C
    STA R5                  ; same as STA $14

; ===========================================================
; Section 3: B+16 absolute addressing (B + 16-bit offset)
; ===========================================================

    ; Set B to a RAM base
    LUI B, 0x80000          ; B = 0x80000000

    ; B+offset stores and loads
    LDA #0x42
    STA B+$0000             ; store to [B + 0]
    LDA #0
    LDA B+$0000             ; load from [B + 0], A should be 0x42

    LDA #0xBEEF
    STA B+$0100             ; store to [B + 0x100]
    LDA B+$0100             ; load back

    ; B+offset with X indexing
    LDX #4
    LDA #0xCAFE
    STA B+$0200,X           ; store to [B + 0x200 + X]
    LDA B+$0200,X           ; load from [B + 0x200 + X]

    ; B+offset with Y indexing
    LDY #8
    LDA #0xFACE
    STA B+$0300,Y           ; store to [B + 0x300 + Y]
    LDA B+$0300,Y           ; load from [B + 0x300 + Y]

; ===========================================================
; Section 4: Bare $XXXX as absolute (B-relative in 32-bit mode)
; In the original assembler, bare $XXXX with >2 hex digits
; becomes absolute (B+16) mode
; ===========================================================

    LDA #0x55
    STA $0400               ; B-relative: [B + 0x400]
    LDA $0400               ; should be 0x55

; ===========================================================
; Section 5: Indirect addressing through DP registers
; ===========================================================

    ; Set R10 as a pointer
    LUI R10, 0x80001        ; R10 = 0x80001000
    ADDI R11, R0, #42       ; R11 = 42
    ST R11, [R10 + 0]       ; store 42 at address in R10

    ; (Rn) indirect - original syntax with $XX
    LDA ($28)               ; $28 = R10, load through pointer in R10

    ; (Rn) indirect - Rn notation
    LDA (R10)               ; same as above

    ; (Rn),Y indirect indexed
    LDY #0
    LDA ($28),Y             ; load through [R10 + Y]
    LDA (R10),Y             ; same

    ; (Rn,X) indexed indirect
    LDX #0
    LDA ($28,X)             ; load through [R10 + X]
    LDA (R10,X)             ; same (non-standard but should work)

; ===========================================================
; Section 6: Long indirect [dp] and [dp],Y
; In 32-bit mode these are equivalent to (dp) and (dp),Y
; ===========================================================

    LDA [R10]               ; long indirect through R10
    LDA [$28]               ; same via hex DP
    LDY #0
    LDA [$28],Y             ; long indirect indexed

; ===========================================================
; Section 7: Immediate addressing
; ===========================================================

    LDA #$42                ; small immediate
    LDA #$1234              ; medium immediate
    LDA #$12345678          ; large 32-bit immediate
    LDA #0                  ; zero
    LDA #-1                 ; all ones (0xFFFFFFFF)

    LDX #100
    LDY #200

; ===========================================================
; Section 8: Traditional ALU (1-operand accumulator-centric)
; ADC/SBC with various addressing modes
; ===========================================================

    LDA #100

    ; Immediate
    ADC #25                 ; A = A + 25
    SBC #10                 ; A = A - 10

    ; DP register operand (single-instruction optimization)
    ADC R2                  ; A = A + R2
    SBC R3                  ; A = A - R3

    ; DP via hex notation
    ADC $08                 ; A = A + R2 (DP $08 = R2)
    SBC $0C                 ; A = A - R3 (DP $0C = R3)

    ; B+16 absolute
    ADC B+$0000             ; A = A + [B+0]
    SBC B+$0100             ; A = A - [B+0x100]

; ===========================================================
; Section 9: Traditional logic (1-operand)
; AND/ORA/EOR with various modes
; ===========================================================

    LDA #$FF

    AND #$0F                ; A = A & 0x0F
    ORA #$F0                ; A = A | 0xF0
    EOR #$AA                ; A = A ^ 0xAA

    AND R2                  ; register operand
    ORA R3                  ; register operand
    EOR R1                  ; register operand

    AND $08                 ; DP hex notation
    ORA $0C                 ; DP hex notation
    EOR $04                 ; DP hex notation

; ===========================================================
; Section 10: Compare instructions
; ===========================================================

    LDA #42
    CMP #42                 ; compare immediate
    CMP R2                  ; compare register
    CMP $08                 ; compare DP hex

    LDX #100
    CPX #100                ; compare X immediate
    LDY #50
    CPY #50                 ; compare Y immediate

; ===========================================================
; Section 11: 3-operand ALU (fixed32 extension)
; These are NEW forms not in the original assembler
; ===========================================================

    ADD R4, R1, R2          ; R4 = R1 + R2
    SUB R5, R4, R3          ; R5 = R4 - R3
    AND R6, R1, R2          ; R6 = R1 & R2
    OR R7, R1, R2           ; R7 = R1 | R2
    XOR R8, R1, R2          ; R8 = R1 ^ R2

    ADDI R9, R0, #42       ; R9 = 42
    SUBI R10, R9, #2        ; R10 = 40

    LDA R1
    CMP R2                 ; flag-setting compare

; ===========================================================
; Section 12: Shifts - all forms
; ===========================================================

    ; Accumulator shifts (traditional implied)
    LDA #1
    ASL                     ; A <<= 1
    ASL A                   ; explicit accumulator
    LSR                     ; A >>= 1
    ROL                     ; rotate left
    ROR                     ; rotate right

    ; 3-operand shifts (fixed32 extension)
    SHL R20, R1, #4         ; R20 = R1 << 4
    SHR R21, R20, #2        ; R21 = R20 >> 2
    SAR R22, R21, #1        ; R22 = R21 >>> 1
    ROL R23, R1, #8         ; R23 = R1 rotated left 8
    ROR R24, R1, #8         ; R24 = R1 rotated right 8

; ===========================================================
; Section 13: INC/DEC variants
; ===========================================================

    LDA #10
    INC                     ; A++  (implied accumulator)
    DEC                     ; A--  (implied accumulator)
    INX                     ; X++
    DEX                     ; X--
    INY                     ; Y++
    DEY                     ; Y--

; ===========================================================
; Section 14: Transfers
; ===========================================================

    TAX                     ; X = A
    TXA                     ; A = X
    TAY                     ; Y = A
    TYA                     ; A = Y
    TSX                     ; X = SP
    TXS                     ; SP = X
    TAB                     ; B = A
    TBA                     ; A = B
    TCD                     ; D = A
    TDC                     ; A = D
    TTA                     ; A = T
    TAT                     ; T = A
    TXY                     ; Y = X
    TYX                     ; X = Y
    TCS                     ; SP = A
    TSC                     ; A = SP

    ; fixed32 extension: MOV
    MOV R14, R13            ; R14 = R13

; ===========================================================
; Section 15: Stack operations
; ===========================================================

    ; Set up SP
    LUI SP, 0x80010         ; SP = 0x80010000

    PHA                     ; push A
    PLA                     ; pull A
    PHX                     ; push X
    PLX                     ; pull X
    PHY                     ; push Y
    PLY                     ; pull Y
    PHB                     ; push B
    PLB                     ; pull B
    PHD                     ; push D
    PLD                     ; pull D
    PHP                     ; push P (placeholder)
    PLP                     ; pull P (placeholder)

    ; fixed32 extension: PUSH/PULL any register
    PUSH R10
    PULL R10

; ===========================================================
; Section 16: Branches
; ===========================================================

    ADDI R1, R0, #5
    ADDI R2, R0, #5
    LDA R1
    CMP R2
    BEQ br_eq
    NOP
br_eq:
    BNE br_ne
    NOP
br_ne:
    BCS br_cs
    NOP
br_cs:
    BCC br_cc
    NOP
br_cc:
    BMI br_mi
    NOP
br_mi:
    BPL br_pl
    NOP
br_pl:
    BVS br_vs
    NOP
br_vs:
    BVC br_vc
    NOP
br_vc:
    BRA br_always
    NOP
br_always:

; ===========================================================
; Section 17: JSR/RTS
; ===========================================================

    JSR test_sub
    NOP
    BRA skip_sub

test_sub:
    LDA #42
    RTS

skip_sub:

; ===========================================================
; Section 18: JMP
; ===========================================================

    JMP jmp_target
    NOP
jmp_target:

; ===========================================================
; Section 19: Flag manipulation (NOP placeholders in fixed32)
; ===========================================================

    CLC
    SEC
    CLD
    SED
    CLI
    SEI
    CLV

; ===========================================================
; Section 20: System instructions
; ===========================================================

    NOP
    FENCE
    FENCER
    FENCEW

; ===========================================================
; Section 21: Register window control (NOPs in fixed32)
; ===========================================================

    RSET
    RCLR

; ===========================================================
; Section 22: Mode control (NOPs/placeholders in fixed32)
; ===========================================================

    REP #$30
    SEP #$20
    XCE

; ===========================================================
; Section 23: BIT instruction
; ===========================================================

    LDA #$FF
    BIT #$80                ; immediate BIT
    BIT R2                  ; register BIT (not standard 65xx)

; ===========================================================
; Section 24: Sign/Zero extend (m65832 extension)
; ===========================================================

    ADDI R30, R0, #0xFF
    SEXT8 R31, R30          ; sign-extend byte
    ZEXT8 R32, R30          ; zero-extend byte
    SEXT16 R33, R30         ; sign-extend word
    ZEXT16 R34, R30         ; zero-extend word

; ===========================================================
; Section 25: LUI + ORI constant loading
; ===========================================================

    LUI R40, 0xDEADB        ; R40 = 0xDEADB000
    ORI R40, R40, #0xEEF    ; R40 = 0xDEADBEEF

; ===========================================================
; Section 26: Directives
; ===========================================================

    .align 4

MYCONST = $42
MYCONST2 .equ $100
MYCONST3 EQU $200

    ADDI R1, R0, #MYCONST   ; should use value $42

; ===========================================================
; Section 27: Data directives
; ===========================================================

    BRA skip_data
data_area:
    .byte $01, $02, $03, $04
    .word $1234, $5678
    .dword $DEADBEEF
    .ds 4
skip_data:

; ===========================================================
; Section 28: Width hints (no-ops in fixed32, but must parse)
; ===========================================================

    .M32
    .X32
    .A32
    .I32
    .M16
    .X16
    .M8
    .X8

; ===========================================================
; Section 29: Section directives (ignored, but must parse)
; ===========================================================

    .TEXT
    .CODE
    .DATA
    .BSS
    .RODATA

; ===========================================================
; Section 30: Extended transfers
; ===========================================================

    TTA                     ; A = T
    TAT                     ; T = A

; ===========================================================
; Section 31: Barrel shifter with register (3-op)
; ===========================================================

    ADDI R1, R0, #1
    SHL R2, R1, #4          ; R2 = 16
    SHR R3, R2, #2          ; R3 = 4

; ===========================================================
; Section 32: STP / BRK / WAI
; ===========================================================

    NOP
    ; WAI                   ; wait for interrupt
    ; STP                   ; stop (commented out - would halt)
    NOP                     ; keep running in simulation (avoid trap loop)

; ===========================================================
; Section 33: Large immediate in CMP
; ===========================================================

    LDA #$DEADBEEF
    CMP #$DEADBEEF          ; large immediate compare

; ===========================================================
; Section 34: PEA (Push Effective Address)
; ===========================================================

    PEA $1234               ; push 16-bit value

; ===========================================================
; Done -- jump to pc_goal to signal completion
; ===========================================================

test_done:
    BRA pc_goal
