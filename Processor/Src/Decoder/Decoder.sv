// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
//
// M65832 fixed32 instruction decoder.
// Decodes a 32-bit instruction word into OpInfo + InsnInfo.
// One instruction -> one micro-op (no cracking).
//

import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;

module Decoder(
    input InsnPath insn,
    output InsnInfo insnInfo,
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    input logic illegalPC
);

    // ============================================================
    // Field extraction (fixed positions across all formats)
    // ============================================================
    M65_OpCode opcode;
    logic [5:0] rd_raw, rs1_raw, rs2_raw;
    logic fBit;

    assign opcode  = M65_OpCode'(insn[31:26]);
    assign rd_raw  = insn[25:20];
    assign rs1_raw = insn[19:14];
    assign rs2_raw = insn[13:8];
    assign fBit    = insn[0];

    // B21 fields
    logic [3:0] cond4;
    logic       linkBit;
    logic [20:0] off21;
    assign cond4   = insn[25:22];
    assign linkBit = insn[21];
    assign off21   = insn[20:0];

    // J26 fields
    logic [25:0] target26;
    assign target26 = insn[25:0];

    // I13F immediate
    logic [12:0] imm13;
    assign imm13 = insn[13:1];

    // M14 offset
    logic [13:0] off14;
    assign off14 = insn[13:0];

    // U20 immediate
    logic [19:0] imm20;
    assign imm20 = insn[19:0];

    // R3 func7
    logic [6:0] func7;
    assign func7 = insn[7:1];

    // STACK fields
    logic       pushPull;
    logic [5:0] stackReg;
    assign pushPull = insn[25];
    assign stackReg = insn[24:19];

    // ============================================================
    // Helper: construct LRegNumPath from a 6-bit integer register index
    // ============================================================
    function automatic LRegNumPath IntReg(input logic [5:0] idx);
`ifdef RSD_MARCH_FP_PIPE
        return {1'b0, idx};
`else
        return idx;
`endif
    endfunction

    function automatic LRegNumPath ZeroReg();
        return IntReg(6'h0);
    endfunction

    // SP register for STACK instructions
    localparam logic [5:0] SP_REG = 6'd59;
    // T register for MUL high / implicit link
    localparam logic [5:0] T_REG = 6'd63;

    // ============================================================
    // Decode logic
    // ============================================================
    OpInfo op;
    InsnInfo info;

    always_comb begin
        // ---- Defaults ----
        op = '0;
        op.valid = !illegalPC;
        op.last  = TRUE;
        op.mid   = '0;
        op.cond  = COND_AL;
        op.mopType = MOP_TYPE_INT;
        op.mopSubType.intType = INT_MOP_TYPE_ALU;
        op.opTypeA = OOT_REG;
        op.opTypeB = OOT_REG;
        op.operand.intOp.dstRegNum  = ZeroReg();
        op.operand.intOp.srcRegNumA = ZeroReg();
        op.operand.intOp.srcRegNumB = ZeroReg();
        op.operand.intOp.aluCode    = AC_ADD;
        op.operand.intOp.shiftType  = SOT_IMM_SHIFT;
        op.operand.intOp.shiftIn    = '0;

        info = '0;

        case (opcode)

        // ============================================================
        // Core ALU (R3 format): ADD, SUB, AND, OR, XOR, SLT, SLTU, CMP
        // ============================================================
        M65_ADD: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_ADD;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.srcRegNumB = IntReg(rs2_raw);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_SUB: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_SUB;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.srcRegNumB = IntReg(rs2_raw);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_AND: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_AND;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.srcRegNumB = IntReg(rs2_raw);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_OR: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_ORR;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.srcRegNumB = IntReg(rs2_raw);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_XOR: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_EOR;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.srcRegNumB = IntReg(rs2_raw);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_SLT: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_SLT;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.srcRegNumB = IntReg(rs2_raw);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_SLTU: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_SLTU;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.srcRegNumB = IntReg(rs2_raw);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_CMP: begin
            // CMP = SUB with result discarded (rd=R0 implied, flags always set)
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_SUB;
            op.operand.intOp.dstRegNum  = ZeroReg();
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.srcRegNumB = IntReg(rs2_raw);
            op.writeReg   = FALSE;
            op.writeFlags = TRUE;
        end

        // ============================================================
        // Core ALU immediate (I13F format)
        // ============================================================
        M65_ADDI: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_ADD;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn = PackI13Signed(imm13, fBit);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_SUBI: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_SUB;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn = PackI13Signed(imm13, fBit);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_ANDI: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_AND;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn = PackI13Unsigned(imm13, fBit);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_ORI: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_ORR;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn = PackI13Unsigned(imm13, fBit);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_XORI: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_EOR;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn = PackI13Unsigned(imm13, fBit);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_SLTI: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_SLT;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn = PackI13Signed(imm13, fBit);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_SLTUI: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_SLTU;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn = PackI13Unsigned(imm13, fBit);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_CMPI: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_SUB;
            op.operand.intOp.dstRegNum  = ZeroReg();
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn = PackI13Signed(imm13, 1'b1);
            op.writeReg   = FALSE;
            op.writeFlags = TRUE;
        end

        // ============================================================
        // Shifts
        // ============================================================
        M65_SHIFT_R: begin
            // R3 format: func7[2:0] = shift kind
            op.mopSubType.intType = INT_MOP_TYPE_SHIFT;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.srcRegNumB = IntReg(rs2_raw);
            op.operand.intOp.shiftType  = SOT_REG_SHIFT;
            op.operand.intOp.shiftIn    = PackShiftReg(func7[2:0], fBit);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        M65_SHIFT_I: begin
            // I13F format: imm13[12:10] = kind, imm13[4:0] = shamt
            op.mopSubType.intType = INT_MOP_TYPE_SHIFT;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.shiftType  = SOT_IMM_SHIFT;
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn    = PackShiftImm(imm13, fBit);
            op.writeReg   = (rd_raw != 6'h0);
            op.writeFlags = fBit;
        end

        // ============================================================
        // XFER (MOV): R3 format, implemented as ADD rd, rs1, R0
        // ============================================================
        M65_XFER: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_ADD;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.intOp.srcRegNumB = ZeroReg();
            op.writeReg   = (rd_raw != 6'h0);
            // Transfers are always flagless in m65832.
            op.writeFlags = FALSE;
        end

        // ============================================================
        // MUL / DIV (complex pipeline, R3 format)
        // ============================================================
        M65_MUL: begin
            op.mopType = MOP_TYPE_COMPLEX;
            op.mopSubType.complexType = COMPLEX_MOP_TYPE_MUL;
            op.operand.complexOp.dstRegNum  = IntReg(rd_raw);
            op.operand.complexOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.complexOp.srcRegNumB = IntReg(rs2_raw);
            op.operand.complexOp.mulCode    = AC_MUL;
            op.operand.complexOp.divCode    = AC_DIV;
            op.operand.complexOp.mulGetUpper = FALSE;
            op.writeReg = (rd_raw != 6'h0);
        end

        M65_DIV: begin
            op.mopType = MOP_TYPE_COMPLEX;
            op.mopSubType.complexType = COMPLEX_MOP_TYPE_DIV;
            op.operand.complexOp.dstRegNum  = IntReg(rd_raw);
            op.operand.complexOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.complexOp.srcRegNumB = IntReg(rs2_raw);
            op.operand.complexOp.mulCode    = AC_MUL;
            op.operand.complexOp.divCode    = AC_DIV;
            op.operand.complexOp.mulGetUpper = FALSE;
            op.writeReg = (rd_raw != 6'h0);
        end

        // ============================================================
        // Load / Store (M14 format, memory pipeline)
        // ============================================================
        M65_LD: begin
            op.mopType = MOP_TYPE_MEM;
            op.mopSubType.memType = MEM_MOP_TYPE_LOAD;
            op.operand.memOp.dstRegNum  = IntReg(rd_raw);
            op.operand.memOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.memOp.srcRegNumB = ZeroReg();
            op.operand.memOp.isAddAddr  = TRUE;
            op.operand.memOp.isRegAddr  = FALSE;
            op.operand.memOp.memAccessMode.isSigned = TRUE;
            op.operand.memOp.memAccessMode.size = MEM_ACCESS_SIZE_WORD;
            op.operand.memOp.addrIn.imm = off14;
            op.writeReg = (rd_raw != 6'h0);
        end

        M65_ST: begin
            op.mopType = MOP_TYPE_MEM;
            op.mopSubType.memType = MEM_MOP_TYPE_STORE;
            op.operand.memOp.dstRegNum  = IntReg(rd_raw);  // source data register
            op.operand.memOp.srcRegNumA = IntReg(rs1_raw);  // base address
            // Store data is carried in operand B in the memory pipeline.
            op.operand.memOp.srcRegNumB = IntReg(rd_raw);
            op.operand.memOp.isAddAddr  = TRUE;
            op.operand.memOp.isRegAddr  = FALSE;
            op.operand.memOp.memAccessMode.isSigned = FALSE;
            op.operand.memOp.memAccessMode.size = MEM_ACCESS_SIZE_WORD;
            op.operand.memOp.addrIn.imm = off14;
            op.writeReg = FALSE;
        end

        // ============================================================
        // LUI / AUIPC (U20 format)
        // ============================================================
        M65_LUI: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_ADD;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = ZeroReg();  // R0 = 0
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn = PackU20(imm20);
            op.writeReg = (rd_raw != 6'h0);
        end

        M65_AUIPC: begin
            op.mopSubType.intType = INT_MOP_TYPE_ALU;
            op.operand.intOp.aluCode    = AC_ADD;
            op.operand.intOp.dstRegNum  = IntReg(rd_raw);
            op.operand.intOp.srcRegNumA = ZeroReg();
            op.opTypeA = OOT_PC;  // operand A = PC
            op.opTypeB = OOT_IMM;
            op.operand.intOp.shiftIn = PackU20(imm20);
            op.writeReg = (rd_raw != 6'h0);
        end

        // ============================================================
        // Branch (B21 format)
        // ============================================================
        M65_BR: begin
            op.mopSubType.intType = INT_MOP_TYPE_BR;
            op.cond = CondCode'({1'b0, cond4}[3:0]);
            if (cond4 <= 4'h8)
                op.cond = CondCode'(cond4);
            else
                op.cond = COND_AL;

            op.operand.brOp.dstRegNum  = (linkBit) ? IntReg(T_REG) : ZeroReg();
            op.operand.brOp.srcRegNumA = ZeroReg();
            op.operand.brOp.srcRegNumB = ZeroReg();
            op.operand.brOp.brDisp     = off21;

            op.readFlags  = (cond4 != 4'h8);  // conditional branches read flags
            op.writeReg   = linkBit;           // BSR saves PC+4
            op.writeFlags = FALSE;

            info.writePC    = TRUE;
            info.isRelBranch = TRUE;
            info.isCall     = linkBit;
        end

        // ============================================================
        // JMP_ABS (J26 format): jump to {PC[31:28], target26, 2'b00}
        // Target is resolved at decode time by the branch resolver.
        // ============================================================
        M65_JMP_ABS: begin
            op.mopSubType.intType = INT_MOP_TYPE_RIJ;
            op.operand.brOp.dstRegNum  = ZeroReg();
            op.operand.brOp.srcRegNumA = ZeroReg();
            op.operand.brOp.srcRegNumB = ZeroReg();
            op.operand.brOp.brDisp     = '0;
            op.opTypeA = OOT_IMM;  // not register-indirect
            op.writeReg = FALSE;

            info.writePC = TRUE;
        end

        // ============================================================
        // JMP_REG (JR format): jump to address in rs1
        // ============================================================
        M65_JMP_REG: begin
            op.mopSubType.intType = INT_MOP_TYPE_RIJ;
            op.operand.brOp.dstRegNum  = ZeroReg();
            op.operand.brOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.brOp.srcRegNumB = ZeroReg();
            op.operand.brOp.brDisp     = '0;
            op.opTypeA = OOT_REG;
            op.writeReg = FALSE;

            info.writePC = TRUE;
        end

        // ============================================================
        // JSR_ABS (J26 format): save PC+4 to T, jump to target
        // Target is resolved at decode time by the branch resolver.
        // ============================================================
        M65_JSR_ABS: begin
            op.mopSubType.intType = INT_MOP_TYPE_RIJ;
            op.operand.brOp.dstRegNum  = IntReg(T_REG);
            op.operand.brOp.srcRegNumA = ZeroReg();
            op.operand.brOp.srcRegNumB = ZeroReg();
            op.operand.brOp.brDisp     = '0;
            op.opTypeA = OOT_IMM;  // not register-indirect
            op.writeReg = TRUE;

            info.writePC = TRUE;
            info.isCall  = TRUE;
        end

        // ============================================================
        // JSR_REG (JR format): save PC+4 to rd, jump to rs1
        // ============================================================
        M65_JSR_REG: begin
            op.mopSubType.intType = INT_MOP_TYPE_RIJ;
            op.operand.brOp.dstRegNum  = IntReg(rd_raw);
            op.operand.brOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.brOp.srcRegNumB = ZeroReg();
            op.operand.brOp.brDisp     = '0;
            op.opTypeA = OOT_REG;
            op.writeReg = (rd_raw != 6'h0);

            info.writePC = TRUE;
            info.isCall  = TRUE;
        end

        // ============================================================
        // RTS (JR format): jump to address in rs1
        // ============================================================
        M65_RTS: begin
            op.mopSubType.intType = INT_MOP_TYPE_RIJ;
            op.operand.brOp.dstRegNum  = ZeroReg();
            op.operand.brOp.srcRegNumA = IntReg(rs1_raw);
            op.operand.brOp.srcRegNumB = ZeroReg();
            op.operand.brOp.brDisp     = '0;
            op.opTypeA = OOT_REG;
            op.writeReg = FALSE;

            info.writePC = TRUE;
            info.isReturn = TRUE;
        end

        // ============================================================
        // STACK (push/pull via SP) -- mark as unsupported for now;
        // compiler decomposes to explicit SUB/ADD + LD/ST
        // ============================================================
        M65_STACK: begin
            op.unsupported = TRUE;
        end

        // ============================================================
        // SYS (TRAP, FENCE, WAI, STP)
        // ============================================================
        M65_SYS: begin
            op.mopType = MOP_TYPE_MEM;
            // Use SYS sub-opcode from imm20[2:0]
            case (M65_SysSubOp'(imm20[2:0]))
                M65_SYS_TRAP: begin
                    op.mopSubType.memType = MEM_MOP_TYPE_ENV;
                    op.operand.systemOp.dstRegNum  = ZeroReg();
                    op.operand.systemOp.srcRegNumA = ZeroReg();
                    op.operand.systemOp.srcRegNumB = ZeroReg();
                    op.operand.systemOp.envCode    = ENV_TRAP;
                    op.operand.systemOp.isEnv      = TRUE;
                    op.operand.systemOp.imm        = imm20[11:0];
                    op.serialized = TRUE;
                end
                M65_SYS_FENCE, M65_SYS_FENCER, M65_SYS_FENCEW: begin
                    op.mopSubType.memType = MEM_MOP_TYPE_FENCE;
                    op.operand.miscMemOp.dstRegNum  = ZeroReg();
                    op.operand.miscMemOp.srcRegNumA = ZeroReg();
                    op.operand.miscMemOp.srcRegNumB = ZeroReg();
                    op.operand.miscMemOp.fence  = TRUE;
                    op.operand.miscMemOp.fenceI = FALSE;
                    op.serialized = TRUE;
                end
                M65_SYS_WAI: begin
                    op.mopSubType.memType = MEM_MOP_TYPE_ENV;
                    op.operand.systemOp.dstRegNum  = ZeroReg();
                    op.operand.systemOp.srcRegNumA = ZeroReg();
                    op.operand.systemOp.srcRegNumB = ZeroReg();
                    op.operand.systemOp.envCode    = ENV_WAI;
                    op.operand.systemOp.isEnv      = TRUE;
                    op.serialized = TRUE;
                end
                M65_SYS_STP: begin
                    op.mopSubType.memType = MEM_MOP_TYPE_ENV;
                    op.operand.systemOp.dstRegNum  = ZeroReg();
                    op.operand.systemOp.srcRegNumA = ZeroReg();
                    op.operand.systemOp.srcRegNumB = ZeroReg();
                    op.operand.systemOp.envCode    = ENV_STP;
                    op.operand.systemOp.isEnv      = TRUE;
                    op.serialized = TRUE;
                end
                default: begin
                    op.undefined = TRUE;
                end
            endcase
        end

        // ============================================================
        // FP operations (deferred -- mark unsupported)
        // ============================================================
        M65_FP_RR, M65_FP_LD, M65_FP_ST, M65_FP_CVT: begin
            op.unsupported = TRUE;
        end

        // ============================================================
        // Deferred/complex operations
        // ============================================================
        M65_LDQ, M65_STQ, M65_CAS, M65_LLI, M65_SCI,
        M65_MODE, M65_BLKMOV: begin
            op.unsupported = TRUE;
        end

        default: begin
            op.undefined = TRUE;
        end

        endcase

        // ---- Output ----
        microOps[0] = op;
        insnInfo     = info;
    end


    // ============================================================
    // Immediate packing helpers
    // ============================================================

    // Sign-extend 13-bit immediate to 20 bits, pack into ShifterPath
    function automatic ShifterPath PackI13Signed(
        input logic [12:0] imm,
        input logic f
    );
        M65_IntOperandImm p;
        p.imm       = { {7{imm[12]}}, imm };  // sign-extend 13->20
        p.shiftType = ST_LSL;
        p.isRegShift = 1'b0;
        p.fBit      = f;
        p.isSigned  = 1'b1;
        p.immType   = M65_IMM_I13;
        p.padding   = '0;
        return ShifterPath'(p);
    endfunction

    // Zero-extend 13-bit immediate to 20 bits, pack into ShifterPath
    function automatic ShifterPath PackI13Unsigned(
        input logic [12:0] imm,
        input logic f
    );
        M65_IntOperandImm p;
        p.imm       = { 7'b0, imm };  // zero-extend 13->20
        p.shiftType = ST_LSL;
        p.isRegShift = 1'b0;
        p.fBit      = f;
        p.isSigned  = 1'b0;
        p.immType   = M65_IMM_I13;
        p.padding   = '0;
        return ShifterPath'(p);
    endfunction

    // Pack U20 immediate (for LUI/AUIPC)
    function automatic ShifterPath PackU20(
        input logic [19:0] imm
    );
        M65_IntOperandImm p;
        p.imm       = imm;
        p.shiftType = ST_LSL;
        p.isRegShift = 1'b0;
        p.fBit      = 1'b0;
        p.isSigned  = 1'b0;
        p.immType   = M65_IMM_U20;
        p.padding   = '0;
        return ShifterPath'(p);
    endfunction

    // Pack register shift (SHIFT_R): kind from func7[2:0]
    function automatic ShifterPath PackShiftReg(
        input logic [2:0] kind,
        input logic f
    );
        M65_IntOperandImm p;
        p.imm       = '0;
        p.isRegShift = 1'b1;
        p.fBit      = f;
        p.isSigned  = 1'b0;
        p.immType   = M65_IMM_SHFT;
        p.padding   = '0;
        case (kind)
            3'd0: p.shiftType = ST_LSL;
            3'd1: p.shiftType = ST_LSR;
            3'd2: p.shiftType = ST_ASR;
            3'd3: p.shiftType = ST_ROR;  // ROL mapped to ROR (amount inverted in exec)
            3'd4: p.shiftType = ST_ROR;
            default: p.shiftType = ST_LSL;
        endcase
        return ShifterPath'(p);
    endfunction

    // Pack immediate shift (SHIFT_I): imm13[12:10]=kind, imm13[4:0]=shamt
    function automatic ShifterPath PackShiftImm(
        input logic [12:0] imm,
        input logic f
    );
        M65_IntOperandImm p;
        p.imm       = {15'b0, imm[4:0]};  // shift amount in low 5 bits
        p.isRegShift = 1'b0;
        p.fBit      = f;
        p.isSigned  = 1'b0;
        p.immType   = M65_IMM_SHFT;
        p.padding   = '0;
        case (imm[12:10])
            3'd0: p.shiftType = ST_LSL;
            3'd1: p.shiftType = ST_LSR;
            3'd2: p.shiftType = ST_ASR;
            3'd3: p.shiftType = ST_ROR;
            3'd4: p.shiftType = ST_ROR;
            default: p.shiftType = ST_LSL;
        endcase
        return ShifterPath'(p);
    endfunction

endmodule
