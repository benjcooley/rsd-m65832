; FlagStress - sustained NZVC dependency stress for OoO flags domain
;
; Goals:
;  - Drive many consecutive F=1 ALU/shift writes to flags
;  - Interleave flagless ops between flag writes and flag reads
;  - Repeatedly branch on expected Z/non-Z outcomes
;  - Catch stale/wrong flags dependencies with fail loop

    .org 0x1000

start:
    BRA test_begin

pc_goal:
    NOP

test_begin:
    ; Scratch RAM base for LD/ST (flagless by ISA rule).
    LUI B, 0x80000

    ; Loop count controls stress duration.
    ADDI R20, R0, #2000
    ADDI R1,  R0, #1
    ADDI R2,  R0, #3
    ADDI R15, R0, #0x123

loop:
    ; High-density F=1 producers.
    ADDI R1,  R1, #1
    ADDI R2,  R2, #3
    SUB  R3,  R2, R1
    ANDI R4,  R3, #0xFF
    ORI  R5,  R4, #0x10
    ORI  R6,  R5, #0xAA
    SHL  R7,  R6, #1
    SHR  R8,  R7, #1
    SAR  R9,  R8, #1
    ROL  R10, R9, #3
    ROR  R11, R10, #3
    SLT  R12, R1, R2
    SLTU R13, R1, R2

    ; Seed Z=1.
    SUB  R16, R1, R1

    ; Flagless ops must not clobber Z.
    XSUBI R15, R15, #1
    MOV   R17, R16
    ST    R17, [B + 0x40]
    LD    R18, [B + 0x40]
    BEQ   z_preserved
    BRA   fail

z_preserved:
    ; Set Z=0 and verify branch observes newest flags.
    ADDI R19, R0, #1
    SUBI R19, R19, #0
    BNE  nz_seen
    BRA  fail

nz_seen:
    ; Loop control also uses flags dependency.
    SUBI R20, R20, #1
    BNE  loop

pass:
    BRA pc_goal

fail:
    BRA fail
