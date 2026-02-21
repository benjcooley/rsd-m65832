# 未確認
#  * 割り込みの時のPELP
#  * LPADのmisalign


    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function


main:
    # save return address
    addi sp, sp, -16
    sw ra, 0(sp)

    # ---------------- TEST 0 ----------------
    # Zicfilp is disabled
    # set trap vector
    la a0, trap_vector_cfi_disable
    csrrw x0, mtvec, a0

    # call function (Zicfilp disabled)
    la t1, target_nolpad
    jalr ra, t1, 0
    la t1, target_lpad_nolabel
    jalr ra, t1, 0
    la t1, target_lpad_label_1
    jalr ra, t1, 0
    la t1, target_lpad_label_2
    jalr ra, t1, 0

    # Setup
    # enable Zicfilp
    la a0, trap_vector_cfi_enable
    csrrw x0, mtvec, a0
    li t0, 0x400 # MLPE = 1
    csrrw x0, mseccfg, t0

    # ---------------- TEST 1 ----------------
    # indirect jump to non lpad

    call reset_registers
    li a1, 0
    la t1, target_nolpad
    jalr ra, t1, 0
    
    # check
    beqz a1, fail
    li t0, 123
    beq a2, t0, fail
    li t0, 234
    beq a3, t0, fail

    # ---------------- TEST 2 ----------------
    # indirect jump to no labeled lpad

    call reset_registers
    li a1, 0
    li x7, 0xdeadbeef # label number (ignored)
    la t1, target_lpad_nolabel
    jalr ra, t1, 0

    # check
    bnez a1, fail
    li t0, 345
    bne a2, t0, fail
    li t0, 456
    bne a3, t0, fail

    # ---------------- TEST 3 ----------------
    # indirect jump to labeled lpad (label 1), x7[31:12] is 1

    call reset_registers
    li a1, 0
    li x7, 0x1000 # label number
    la t1, target_lpad_label_1
    jalr ra, t1, 0

    # check
    bnez a1, fail
    li t0, 567
    bne a2, t0, fail
    li t0, 789
    bne a3, t0, fail

    # ---------------- TEST 4 ----------------
    # indirect jump to labeled lpad (label 2), x7[31:12] is 1

    call reset_registers
    li a1, 0
    li x7, 0x1000 # label number
    la t1, target_lpad_label_2
    jalr ra, t1, 0

    # check
    beqz a1, fail
    bnez a2, fail
    bnez a3, fail

end:
    # restore return address
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

reset_registers:
    # reset registers
    li a2, 0
    li a3, 0
    ret

fail:
    # infinite loop
    j fail

target_nolpad:
    addi a2, x0, 123
    addi a3, x0, 234
    ret
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

target_lpad_nolabel:
    lpad 0
    addi a2, x0, 345
    addi a3, x0, 456
    ret
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

target_lpad_label_1:
    lpad 1
    addi a2, x0, 567
    addi a3, x0, 789
    ret
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

target_lpad_label_2:
    lpad 2
    addi a2, x0, 890
    addi a3, x0, 901
    ret
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

# loop
trap_vector_cfi_disable:
    j trap_vector_cfi_disable

trap_vector_cfi_enable:
    # cause is 18
    li t1, 18 # software check exception
    csrr t0, mcause
    bne t0, t1, fail

    # MPELP = 1
    li t1, 0x200
    csrr t0, mstatush
    and t0, t0, t1
    beqz t0, fail

    # trap value is 2
    li t1, 2 # landing pad fault
    csrr t0, mtval
    bne t0, t1, fail

    # set a1 to non-zero value to indicate that trap handler is called
    addi a1, a1, 1

    # lpad exception is trapped on lpad, so set mepc = ra to return next pc of jalr
    csrrw x0, mepc, ra

    mret