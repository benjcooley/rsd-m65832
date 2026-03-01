; FlagBranch - explicit flags/branch behavior checks
;
; Verifies:
;  - SUBI sets flags (Z expected after 1-1)
;  - XSUBI does not modify flags
;  - MOV/XFER does not modify flags
;  - LD/ST do not modify flags
;  - Conditional branches observe the preserved NZVC state

    .org 0x1000

start:
    BRA test_begin

pc_goal:
    NOP

test_begin:
    ; Seed Z=1, then ensure flagless arithmetic keeps it.
    ADDI R1, R0, #1
    SUBI R1, R1, #1          ; Z = 1
    XSUBI R2, R2, #1         ; must not change flags
    BEQ z_kept_after_xsubi
    BRA fail

z_kept_after_xsubi:
    ; Transfers must not touch flags.
    MOV R3, R1
    BEQ z_kept_after_mov
    BRA fail

z_kept_after_mov:
    ; Loads/stores must not touch flags.
    LUI B, 0x80000
    XADDI R4, R0, #0x55
    ST R4, [B + 0]
    LD R5, [B + 0]
    BEQ z_kept_after_memops
    BRA fail

z_kept_after_memops:
    ; Check loaded value and flag-setting compare path.
    MOV A, R5
    CMP #0x55
    BNE fail

    ; Re-check SUBI vs XSUBI with same destination.
    ADDI R6, R0, #1
    SUBI R6, R6, #1          ; Z = 1
    XSUBI R6, R6, #1         ; must not change flags
    BEQ pass
    BRA fail

pass:
    BRA pc_goal

fail:
    BRA fail
