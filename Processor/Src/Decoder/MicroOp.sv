// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
//
// Definitions related to micro ops (adapted for m65832 fixed32).
//

package MicroOpTypes;

import BasicTypes::*;
import OpFormatTypes::*;


// R0 is the zero register (reads as 0, writes discarded)
localparam ZERO_REGISTER = { LSCALAR_NUM_BIT_WIDTH{1'b0} };

// m65832 fixed32: each instruction produces exactly one micro-op (no cracking)
localparam MICRO_OP_MAX_NUM = 1;
localparam MICRO_OP_INDEX_BITS = 1;
typedef logic [MICRO_OP_INDEX_BITS-1:0] MicroOpIndex;
typedef logic [MICRO_OP_INDEX_BITS  :0] MicroOpCount;


localparam ALL_DECODED_MICRO_OP_WIDTH = MICRO_OP_MAX_NUM * DECODE_WIDTH;
localparam ALL_DECODED_MICRO_OP_WIDTH_BIT_SIZE = MICRO_OP_INDEX_BITS + DECODE_WIDTH_BIT_SIZE;

typedef logic [ALL_DECODED_MICRO_OP_WIDTH-1:0] AllDecodedMicroOpPath;
// With MICRO_OP_MAX_NUM=1, no remaining micro-ops exist; keep 1-bit min width.
typedef logic [0:0] RemainingDecodedMicroOpPath;
typedef logic [ALL_DECODED_MICRO_OP_WIDTH_BIT_SIZE-1:0] AllDecodedMicroOpIndex;


`ifdef RSD_MARCH_FP_PIPE
localparam MICRO_OP_SOURCE_REG_NUM = 3;
`else
localparam MICRO_OP_SOURCE_REG_NUM = 2;
`endif

typedef enum logic [1:0]
{
    MOP_TYPE_INT     = 2'b00,
    MOP_TYPE_COMPLEX = 2'b01,
    MOP_TYPE_MEM     = 2'b10
`ifdef RSD_MARCH_FP_PIPE
    ,
    MOP_TYPE_FP      = 2'b11
`endif
} MicroOpType;

typedef enum logic [2:0]
{
    INT_MOP_TYPE_ALU       = 3'b000,
    INT_MOP_TYPE_SHIFT     = 3'b001,
    INT_MOP_TYPE_BR        = 3'b010,
    INT_MOP_TYPE_RIJ       = 3'b011
} IntMicroOpSubType;

typedef enum logic [2:0]
{
    COMPLEX_MOP_TYPE_MUL       = 3'b000,
    COMPLEX_MOP_TYPE_DIV       = 3'b001
} ComplexMicroOpSubType;

typedef enum logic [2:0]
{
    MEM_MOP_TYPE_LOAD      = 3'b000,
    MEM_MOP_TYPE_STORE     = 3'b001,
    MEM_MOP_TYPE_MUL       = 3'b010,
    MEM_MOP_TYPE_DIV       = 3'b011,
    MEM_MOP_TYPE_CSR       = 3'b100,
    MEM_MOP_TYPE_FENCE     = 3'b101,
    MEM_MOP_TYPE_ENV       = 3'b110
} MemMicroOpSubType;

typedef enum logic [2:0]
{
    FP_MOP_TYPE_ADD    = 3'b000,
    FP_MOP_TYPE_MUL    = 3'b001,
    FP_MOP_TYPE_DIV    = 3'b010,
    FP_MOP_TYPE_SQRT   = 3'b011,
    FP_MOP_TYPE_FMA    = 3'b100,
    FP_MOP_TYPE_OTHER  = 3'b101
} FPMicroOpSubType;

typedef union packed
{
    IntMicroOpSubType     intType;
    ComplexMicroOpSubType complexType;
    MemMicroOpSubType     memType;
`ifdef RSD_MARCH_FP_PIPE
    FPMicroOpSubType     fpType;
`endif
} MicroOpSubType;

typedef struct packed // OpId
{
    OpSerial sid;
    MicroOpIndex mid;
} OpId;

typedef enum logic [1:0]
{
    OOT_REG = 2'b00,
    OOT_IMM = 2'b01,
    OOT_PC  = 2'b10
} OpOperandType;


// ============================================================
// Micro-op operand structs (union members -- all must be equal width).
//
// The Int struct sets the target width via its fixed-size fields:
//   3 * LRegNumPath + IntALU_Code(4) + ShiftOperandType(1) + ShifterPath(31) = 3R + 36
// All other structs pad to match.
//
// With FP pipe (LRegNumPath=7): target = 3*7 + 36 = 57 bits
// Without FP (LRegNumPath=6): target = 3*6 + 36 = 54 bits
// Padding values are R-independent, so no ifdefs needed in non-FP structs.
// ============================================================

// Int ALU/shift: 3R + 4 + 1 + 31 = 3R + 36
typedef struct packed
{
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;
    LRegNumPath srcRegNumB;
    IntALU_Code aluCode;        // 4
    ShiftOperandType shiftType; // 1
    ShifterPath shiftIn;        // 31 (M65_IntOperandImm packed here by decoder)
} IntMicroOpOperand;

// Mem load/store: 3R + 1+1+3 + 8 + 9 + 14 = 3R + 36
typedef struct packed
{
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;
    LRegNumPath srcRegNumB;
    logic isAddAddr;            // 1
    logic isRegAddr;            // 1
    MemAccessMode memAccessMode;// 3
    CSR_CtrlPath csrCtrl;       // 8
    logic [8:0] padding;        // 9
    AddrOperandImm addrIn;      // 14
} MemMicroOpOperand;

// Branch: 3R + 15 + 21 = 3R + 36
typedef struct packed
{
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;
    LRegNumPath srcRegNumB;
    logic [14:0] padding;       // 15
    BranchDisplacement brDisp;  // 21
} BrMicroOpOperand;

// Complex (MUL/DIV): 3R + 1+2+2 + 31 = 3R + 36
typedef struct packed
{
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;
    LRegNumPath srcRegNumB;
    logic mulGetUpper;          // 1
    IntMUL_Code mulCode;        // 2
    IntDIV_Code divCode;        // 2
    logic [30:0] padding;       // 31
} ComplexMicroOpOperand;

// MiscMem (FENCE): 3R + 1+1 + 34 = 3R + 36
typedef struct packed
{
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;
    LRegNumPath srcRegNumB;
    logic fence;                // 1
    logic fenceI;               // 1
    logic [33:0] padding;       // 34
} MiscMemMicroOpOperand;

// System (TRAP/ENV): 3R + 3+1 + 20 + 12 = 3R + 36
typedef struct packed
{
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;
    LRegNumPath srcRegNumB;
    ENV_Code envCode;           // 3
    logic isEnv;                // 1
    logic [19:0] padding;       // 20
    logic [11:0] imm;           // 12
} SystemMicroOpOperand;

// FP: 4R + 5+3 + 21 = 4R + 29
// With FP pipe: 4*7 + 29 = 57 = 3*7 + 36. ✓
`ifdef RSD_MARCH_FP_PIPE
typedef struct packed
{
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;
    LRegNumPath srcRegNumB;
    LRegNumPath srcRegNumC;
    FPU_Code fpuCode;           // 5
    Rounding_Mode rm;           // 3
    logic [20:0] padding;       // 21
} FPMicroOpOperand;
`endif

typedef union packed
{
    IntMicroOpOperand     intOp;
    MemMicroOpOperand     memOp;
    BrMicroOpOperand      brOp;
    ComplexMicroOpOperand complexOp;
    MiscMemMicroOpOperand miscMemOp;
    SystemMicroOpOperand  systemOp;
`ifdef RSD_MARCH_FP_PIPE
    FPMicroOpOperand fpOp;
`endif
} MicroOpOperand;


typedef struct packed // OpInfo
{
    CondCode cond;              // 4 bits (m65832 flag-based condition)

    MicroOpType mopType;        // 2
    MicroOpSubType mopSubType;  // 3
    
    MicroOpOperand operand;

    OpOperandType opTypeA;      // 2
    OpOperandType opTypeB;      // 2
`ifdef RSD_MARCH_FP_PIPE
    OpOperandType opTypeC;      // 2
`endif

    logic writeReg;
    logic writeFlags;           // m65832: this op writes the NZVC flags register
    logic readFlags;            // m65832: this op reads the NZVC flags register (branches)
    
    logic undefined;
    logic unsupported;
    
    logic split;
    logic valid;
    logic last;
    
    MicroOpIndex mid;           // 1

    logic serialized;
} OpInfo;

typedef struct packed { // InsnInfo
    logic writePC;
    logic isCall;
    logic isReturn;
    logic isRelBranch;
    logic isSerialized;
} InsnInfo;


endpackage
