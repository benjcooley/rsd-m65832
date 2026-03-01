// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
//
// M65832 fixed32 instruction format types and generic pipeline types.
//

package OpFormatTypes;

import BasicTypes::*;

// Branch/jump link saves PC+4 (32-bit instruction width)
localparam PC_OPERAND_OFFSET = 4;

//
// --- Condition codes (m65832 flag-based)
//
// These map directly to the cond4 field in the B21 branch format.
// Conditions test NZVC flags from the P register, not register values.
//
typedef enum logic [3:0]
{
    COND_EQ  = 4'h0,   // Z=1
    COND_NE  = 4'h1,   // Z=0
    COND_CS  = 4'h2,   // C=1 (unsigned >=)
    COND_CC  = 4'h3,   // C=0 (unsigned <)
    COND_MI  = 4'h4,   // N=1 (negative)
    COND_PL  = 4'h5,   // N=0 (positive/zero)
    COND_VS  = 4'h6,   // V=1 (overflow)
    COND_VC  = 4'h7,   // V=0 (no overflow)
    COND_AL  = 4'h8    // always (unconditional)
} CondCode;

//
// --- NZVC flags
//
typedef struct packed {
    logic N;  // Negative (result[31])
    logic Z;  // Zero (result == 0)
    logic V;  // Overflow (signed)
    logic C;  // Carry (unsigned)
} M65_Flags;

//
// --- M65832 opcode (6-bit, bits [31:26] of instruction word)
//
typedef enum logic [5:0]
{
    M65_ADD     = 6'h00,
    M65_ADDI    = 6'h01,
    M65_SUB     = 6'h02,
    M65_SUBI    = 6'h03,
    M65_AND     = 6'h04,
    M65_ANDI    = 6'h05,
    M65_OR      = 6'h06,
    M65_ORI     = 6'h07,
    M65_XOR     = 6'h08,
    M65_XORI    = 6'h09,
    M65_SLT     = 6'h0A,
    M65_SLTI    = 6'h0B,
    M65_SLTU    = 6'h0C,
    M65_SLTUI   = 6'h0D,
    M65_CMP     = 6'h0E,
    M65_CMPI    = 6'h0F,

    M65_SHIFT_R = 6'h10,
    M65_SHIFT_I = 6'h11,
    M65_XFER    = 6'h12,

    M65_FP_RR   = 6'h13,
    M65_FP_LD   = 6'h14,
    M65_FP_ST   = 6'h15,
    M65_FP_CVT  = 6'h16,

    M65_MUL     = 6'h1A,
    M65_DIV     = 6'h1B,
    M65_LD      = 6'h1C,
    M65_ST      = 6'h1D,
    M65_LUI     = 6'h1E,
    M65_AUIPC   = 6'h1F,

    M65_LDQ     = 6'h20,
    M65_STQ     = 6'h21,
    M65_CAS     = 6'h22,
    M65_LLI     = 6'h23,
    M65_SCI     = 6'h24,

    M65_BR      = 6'h25,
    M65_JMP_ABS = 6'h26,
    M65_JMP_REG = 6'h27,
    M65_JSR_ABS = 6'h28,
    M65_JSR_REG = 6'h29,
    M65_RTS     = 6'h2A,
    M65_STACK   = 6'h2B,
    M65_MODE    = 6'h2C,
    M65_SYS     = 6'h2D,
    M65_BLKMOV  = 6'h2E
} M65_OpCode;


// ============================================================
// M65832 instruction format structs
// All instructions are 32 bits. rd at [25:20], rs1 at [19:14].
// ============================================================

// Common overlay for early register extraction
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [5:0] rd;         // [25:20]
    logic [5:0] rs1;        // [19:14]
    logic [13:0] payload;   // [13:0] format-dependent
} M65_ISF_Common;

// R3: 3-register (ALU reg-reg, shifts, mul/div, CAS, XFER)
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [5:0] rd;         // [25:20]
    logic [5:0] rs1;        // [19:14]
    logic [5:0] rs2;        // [13:8]
    logic [6:0] func7;      // [7:1]
    logic       fBit;       // [0]
} M65_ISF_R3;

// I13F: register + 13-bit immediate
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [5:0] rd;         // [25:20]
    logic [5:0] rs1;        // [19:14]
    logic [12:0] imm13;     // [13:1]
    logic       fBit;       // [0]
} M65_ISF_I13F;

// M14: load/store with 14-bit signed offset
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [5:0] rt;         // [25:20] dest for LD, source for ST
    logic [5:0] base;       // [19:14]
    logic [13:0] off14;     // [13:0] signed byte offset
} M65_ISF_M14;

// U20: upper immediate (LUI, AUIPC)
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [5:0] rd;         // [25:20]
    logic [19:0] imm20;     // [19:0]
} M65_ISF_U20;

// B21: conditional/unconditional branch
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [3:0] cond4;      // [25:22]
    logic       linkBit;    // [21]
    logic [20:0] off21;     // [20:0] signed word offset
} M65_ISF_B21;

// J26: absolute region jump/call
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [25:0] target26;  // [25:0]
} M65_ISF_J26;

// JR: register jump/call
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [5:0] rd;         // [25:20]
    logic [5:0] rs1;        // [19:14]
    logic [13:0] zero;      // [13:0]
} M65_ISF_JR;

// Q20: 64-bit A:T pair load/store
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [5:0] base;       // [25:20]
    logic [19:0] off20;     // [19:0] signed offset
} M65_ISF_Q20;

// STACK: single register push/pull
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic       pushPull;   // [25] 0=push, 1=pull
    logic [5:0] reg6;       // [24:19]
    logic [18:0] zero;      // [18:0]
} M65_ISF_STACK;

// FP3: FP register-register
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [3:0] fd;         // [25:22]
    logic [3:0] fs1;        // [21:18]
    logic [3:0] fs2;        // [17:14]
    logic [8:0] func9;      // [13:5]
    logic [3:0] reserved;   // [4:1]
    logic       rBit;       // [0] rounding mode override
} M65_ISF_FP3;

// FPM: FP load/store
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [3:0] ft;         // [25:22]
    logic       dBit;       // [21] 0=single, 1=double
    logic [5:0] base;       // [20:15] integer base register (note: shifted from normal position)
    logic [14:0] off15;     // [14:0] signed offset
} M65_ISF_FPM;

// FPI: FP-integer transfer
typedef struct packed {
    M65_OpCode  opcode;     // [31:26]
    logic [3:0] fd;         // [25:22]
    logic [1:0] subop;      // [21:20]
    logic [5:0] rs1;        // [19:14]
    logic [13:0] zero;      // [13:0]
} M65_ISF_FPI;


// ============================================================
// Shift operand types (generic, shared with pipeline)
// ============================================================

typedef enum logic
{
    SOT_IMM_SHIFT = 1'b0,
    SOT_REG_SHIFT = 1'b1
} ShiftOperandType;

typedef enum logic [1:0]
{
    ST_LSL = 2'b00,
    ST_LSR = 2'b01,
    ST_ASR = 2'b10,
    ST_ROR = 2'b11
} ShiftType;


// ============================================================
// M65832 immediate/operand types for pipeline stages
// ============================================================

// Immediate type for pipeline stage expansion
typedef enum logic [1:0] {
    M65_IMM_NONE = 2'b00,    // Register-register (no immediate)
    M65_IMM_I13  = 2'b01,    // 13-bit immediate (I13F format), sign/zero in imm[19:0]
    M65_IMM_U20  = 2'b10,    // 20-bit upper immediate (LUI/AUIPC), shift << 12
    M65_IMM_SHFT = 2'b11     // Shift immediate (shamt in imm[4:0], kind in shiftType)
} M65_ImmType;

// Packed into ShifterPath (31 bits) in IntMicroOpOperand.shiftIn
typedef struct packed {
    logic [19:0] imm;       // 20 bits: pre-extended I13 or raw U20
    ShiftType    shiftType;  // 2 bits: shift kind
    logic        isRegShift; // 1 bit
    logic        fBit;       // 1 bit: flag-setting
    logic        isSigned;   // 1 bit: sign-extend control
    M65_ImmType  immType;    // 2 bits: how execution stage expands this
    logic [3:0]  padding;    // 4 bits: pad to 31
} M65_IntOperandImm;

// Shift sub-operation kinds (encoded in R3 func7 or I13F imm13[12:10])
typedef enum logic [2:0] {
    M65_SH_SHL = 3'd0,
    M65_SH_SHR = 3'd1,
    M65_SH_SAR = 3'd2,
    M65_SH_ROL = 3'd3,
    M65_SH_ROR = 3'd4
} M65_ShiftKind;

// SYS sub-operation (encoded in instruction payload)
typedef enum logic [2:0] {
    M65_SYS_TRAP   = 3'd0,
    M65_SYS_FENCE  = 3'd1,
    M65_SYS_FENCER = 3'd2,
    M65_SYS_FENCEW = 3'd3,
    M65_SYS_WAI    = 3'd4,
    M65_SYS_STP    = 3'd5
} M65_SysSubOp;


// ============================================================
// Addressing / Memory access types (generic)
// ============================================================

localparam ADDR_OPERAND_IMM_WIDTH = 14;
localparam ADDR_SIGN_EXTENTION_WIDTH = ADDR_WIDTH - ADDR_OPERAND_IMM_WIDTH;

typedef struct packed {
    logic [ADDR_OPERAND_IMM_WIDTH-1:0] imm;    // M14 off14
} AddrOperandImm;

typedef enum logic [1:0]
{
    MEM_ACCESS_SIZE_BYTE = 2'b00,
    MEM_ACCESS_SIZE_HALF_WORD = 2'b01,
    MEM_ACCESS_SIZE_WORD = 2'b10,
    MEM_ACCESS_SIZE_VEC  = 2'b11
} MemAccessSizeType;

function automatic logic IsMisalignedAddress(input AddrPath addr, input MemAccessSizeType size);
    if (size == MEM_ACCESS_SIZE_BYTE || size == MEM_ACCESS_SIZE_VEC) begin
        return FALSE;
    end
    else if (size == MEM_ACCESS_SIZE_HALF_WORD) begin
        return addr[0:0] != 0 ? TRUE : FALSE;
    end
    else if (size == MEM_ACCESS_SIZE_WORD) begin
        return addr[1:0] != 0 ? TRUE : FALSE;
    end
    else 
        return FALSE;
endfunction

typedef struct packed
{
    logic isSigned;
    MemAccessSizeType size;
} MemAccessMode;


// ============================================================
// Branch displacement
// ============================================================

// B21 word offset: target = PC + 4 + (signext(off21) << 2)
localparam BR_DISP_WIDTH = 21;
typedef logic [BR_DISP_WIDTH-1:0] BranchDisplacement;
localparam BR_DISP_SIGN_EXTENTION_WIDTH = ADDR_WIDTH - BR_DISP_WIDTH;

function automatic AddrPath ExtendBranchDisplacement(
    input BranchDisplacement brDisp
);
    return {
        { (ADDR_WIDTH-BR_DISP_WIDTH-2){brDisp[BR_DISP_WIDTH-1]} },
        brDisp,
        2'b00
    };
endfunction


// ============================================================
// ALU codes (generic, used by all pipelines)
// ============================================================

typedef enum logic [3:0]
{
    AC_ADD     = 4'b0000,
    AC_SUB     = 4'b0001,
    AC_SLT     = 4'b0010,
    AC_SLTU    = 4'b0011,
    AC_EOR     = 4'b0100,
    AC_ORR     = 4'b0110,
    AC_AND     = 4'b0111,
    AC_SH1ADD  = 4'b1010,
    AC_SH2ADD  = 4'b1011,
    AC_SH3ADD  = 4'b1100,
    AC_EQZ     = 4'b1000,
    AC_NEZ     = 4'b1001
} IntALU_Code;


// ============================================================
// Complex integer (MUL/DIV) codes
// ============================================================

typedef enum logic [1:0]
{
    AC_MUL    = 2'b00,
    AC_MULH   = 2'b01,
    AC_MULHSU = 2'b10,
    AC_MULHU  = 2'b11
} IntMUL_Code;

typedef enum logic [1:0]
{
    AC_DIV    = 2'b00,
    AC_DIVU   = 2'b01,
    AC_REM    = 2'b10,
    AC_REMU   = 2'b11
} IntDIV_Code;


// ============================================================
// CSR / Environment codes (adapted for m65832 system operations)
// ============================================================

typedef enum logic [1:0]
{
    CSR_UNKNOWN = 2'b00,
    CSR_WRITE   = 2'b01,
    CSR_SET     = 2'b10,
    CSR_CLEAR   = 2'b11
} CSR_Code;

localparam CSR_NUMBER_WIDTH = 12;
typedef logic [CSR_NUMBER_WIDTH-1:0] CSR_NumberPath;

localparam CSR_IMM_WIDTH = 5;
typedef logic [CSR_IMM_WIDTH-1:0] CSR_ImmPath;

typedef struct packed // 5+1+2=8
{
    CSR_ImmPath imm;
    logic isImm;
    CSR_Code code;
} CSR_CtrlPath;

typedef enum logic [2:0]
{
    ENV_TRAP            = 3'b000,
    ENV_FENCE           = 3'b001,
    ENV_FENCER          = 3'b010,
    ENV_FENCEW          = 3'b011,
    ENV_WAI             = 3'b100,
    ENV_STP             = 3'b101,
    ENV_INSN_ILLEGAL    = 3'b110,
    ENV_INSN_VIOLATION  = 3'b111
} ENV_Code;


// ============================================================
// FPU codes (generic, used by FP pipeline)
// ============================================================

typedef enum logic [4:0]
{
    FC_ADD      = 5'b00000,
    FC_SUB      = 5'b00001,
    FC_MUL      = 5'b00010,
    FC_DIV      = 5'b00011,
    FC_SQRT     = 5'b00100,
    FC_SGNJ     = 5'b00101,
    FC_SGNJN    = 5'b00110,
    FC_SGNJX    = 5'b00111,
    FC_FMIN     = 5'b01000,
    FC_FMAX     = 5'b01001,
    FC_FCVT_WS  = 5'b01010,
    FC_FCVT_WUS = 5'b01011,
    FC_FMV_XW   = 5'b01100,
    FC_FEQ      = 5'b01101,
    FC_FLT      = 5'b01110,
    FC_FLE      = 5'b01111,
    FC_FCLASS   = 5'b10000,
    FC_FCVT_SW  = 5'b10001,
    FC_FCVT_SWU = 5'b10010,
    FC_FMV_WX   = 5'b10011,
    FC_FMADD    = 5'b10100,
    FC_FMSUB    = 5'b10101,
    FC_FNMSUB   = 5'b10110,
    FC_FNMADD   = 5'b10111
} FPU_Code;

typedef enum logic [2:0]
{
    RM_RNE = 3'b000,
    RM_RTZ = 3'b001,
    RM_RDN = 3'b010,
    RM_RUP = 3'b011,
    RM_RMM = 3'b100,
    RM_DYN = 3'b111
} Rounding_Mode;

typedef struct packed {
    logic NV;
    logic DZ;
    logic OF;
    logic UF;
    logic NX;
} FFlags_Path;


endpackage
