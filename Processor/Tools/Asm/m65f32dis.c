/*
 * m65f32dis - M65832 Fixed-Width 32-bit Disassembler
 *
 * Disassembles fixed-width 32-bit machine code back to traditional
 * m65832 assembly. Recognizes multi-instruction sequences emitted by
 * the assembler for complex addressing modes and reconstructs the
 * original high-level notation.
 *
 * Pattern-matching examples:
 *   XFER A, R1        →  LDA R1
 *   XFER R1, A        →  STA R1
 *   ADD A, A, R2 (F)  →  ADC R2
 *   LD A, [B+off]     →  LDA B+$off
 *   LUI+ORI           →  LDA #$const  (when dest is same)
 *   SUBI SP,SP,4 + ST R,[SP+0]  →  PUSH R / PHA etc.
 *
 * Usage: m65f32dis [-r] [-t] input.hex
 *   -r : raw mode (show fixed32 mnemonics only, no pattern matching)
 *   -t : traditional mode (reconstruct original notation, default)
 *
 * Input: RSD hex format (same as assembler output).
 *
 * Copyright (c) 2026. MIT License.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

/* Opcodes (must match assembler) */
enum {
    OP_ADD=0x00, OP_ADDI=0x01, OP_SUB=0x02, OP_SUBI=0x03,
    OP_AND=0x04, OP_ANDI=0x05, OP_OR=0x06,  OP_ORI=0x07,
    OP_XOR=0x08, OP_XORI=0x09, OP_SLT=0x0A, OP_SLTI=0x0B,
    OP_SLTU=0x0C,OP_SLTUI=0x0D,OP_CMP=0x0E, OP_CMPI=0x0F,
    OP_SHIFT_R=0x10, OP_SHIFT_I=0x11, OP_XFER=0x12,
    OP_FP_RR=0x13, OP_FP_LD=0x14, OP_FP_ST=0x15, OP_FP_CVT=0x16,
    OP_MUL=0x1A, OP_DIV=0x1B, OP_LD=0x1C, OP_ST=0x1D,
    OP_LUI=0x1E, OP_AUIPC=0x1F,
    OP_LDQ=0x20, OP_STQ=0x21, OP_CAS=0x22, OP_LLI=0x23, OP_SCI=0x24,
    OP_BR=0x25, OP_JMP_ABS=0x26, OP_JMP_REG=0x27,
    OP_JSR_ABS=0x28, OP_JSR_REG=0x29, OP_RTS=0x2A,
    OP_STACK=0x2B, OP_MODE=0x2C, OP_SYS=0x2D, OP_BLKMOV=0x2E,
};

enum { SH_SHL=0, SH_SHR=1, SH_SAR=2, SH_ROL=3, SH_ROR=4 };
enum { SYS_TRAP=0, SYS_FENCE=1, SYS_FENCER=2, SYS_FENCEW=3, SYS_WAI=4, SYS_STP=5 };
enum { COND_EQ=0, COND_NE=1, COND_CS=2, COND_CC=3,
       COND_MI=4, COND_PL=5, COND_VS=6, COND_VC=7, COND_AL=8 };

#define REG_ZERO 0
#define REG_A    56
#define REG_X    57
#define REG_Y    58
#define REG_SP   59
#define REG_D    60
#define REG_B    61
#define REG_VBR  62
#define REG_T    63

/* Decoded instruction */
typedef struct {
    uint32_t raw;
    int op, rd, rs1, rs2, func7, f;
    int32_t imm13, off14;
    uint32_t imm20, target26;
    int cond, link;
    int32_t off21;
    int sys_sub;
    uint32_t sys_payload;
} Insn;

static const char *reg_name(int r) {
    static const char *names[] = {
        [REG_A]="A", [REG_X]="X", [REG_Y]="Y", [REG_SP]="SP",
        [REG_D]="D", [REG_B]="B", [REG_VBR]="VBR", [REG_T]="T",
    };
    /* Rotating buffer pool to allow multiple reg_name() calls in one printf */
    static char bufs[4][8];
    static int idx = 0;
    if (r == 0) return "R0";
    if (r >= 56 && r <= 63 && names[r]) return names[r];
    char *buf = bufs[idx++ & 3];
    snprintf(buf, 8, "R%d", r);
    return buf;
}

static Insn decode(uint32_t w) {
    Insn i = {0};
    i.raw = w;
    i.op = (w >> 26) & 0x3F;
    i.rd = (w >> 20) & 0x3F;
    i.rs1 = (w >> 14) & 0x3F;
    i.rs2 = (w >> 8) & 0x3F;
    i.func7 = (w >> 1) & 0x7F;
    i.f = w & 1;
    i.imm13 = ((int32_t)((w >> 1) & 0x1FFF) << 19) >> 19;
    i.off14 = ((int32_t)(w & 0x3FFF) << 18) >> 18;
    i.imm20 = w & 0xFFFFF;
    i.target26 = w & 0x3FFFFFF;
    i.cond = (w >> 22) & 0xF;
    i.link = (w >> 21) & 1;
    i.off21 = ((int32_t)(w & 0x1FFFFF) << 11) >> 11;
    i.sys_sub = w & 0x7;
    i.sys_payload = (w >> 3) & 0x1FFFF;
    return i;
}

/* ======================================================================== */
/* Raw disassembly (one instruction at a time)                               */
/* ======================================================================== */

static void dis_raw(Insn *i, uint32_t pc, char *out, size_t sz) {
    int op = i->op;
    static const char *alu_rr[] = {
        [OP_ADD]="ADD",[OP_SUB]="SUB",[OP_AND]="AND",[OP_OR]="OR",
        [OP_XOR]="XOR",[OP_SLT]="SLT",[OP_SLTU]="SLTU",[OP_CMP]="CMP",
        [OP_MUL]="MUL",[OP_DIV]="DIV",[OP_XFER]="MOV",
    };
    static const char *alu_ri[] = {
        [OP_ADDI]="ADDI",[OP_SUBI]="SUBI",[OP_ANDI]="ANDI",[OP_ORI]="ORI",
        [OP_XORI]="XORI",[OP_SLTI]="SLTI",[OP_SLTUI]="SLTUI",[OP_CMPI]="CMPI",
    };
    static const char *sh_names[] = {"SHL","SHR","SAR","ROL","ROR"};
    static const char *cond_names[] = {"EQ","NE","CS","CC","MI","PL","VS","VC","AL"};

    if (op == OP_ADD || op == OP_SUB || op == OP_AND || op == OP_OR ||
        op == OP_XOR || op == OP_SLT || op == OP_SLTU || op == OP_CMP ||
        op == OP_MUL || op == OP_DIV) {
        snprintf(out, sz, "%s %s, %s, %s%s",
                 alu_rr[op], reg_name(i->rd), reg_name(i->rs1), reg_name(i->rs2),
                 i->f ? ", F" : "");
        return;
    }
    if (op == OP_XFER) {
        snprintf(out, sz, "MOV %s, %s%s",
                 reg_name(i->rd), reg_name(i->rs1), i->f ? ", F" : "");
        return;
    }
    if (op == OP_ADDI || op == OP_SUBI || op == OP_ANDI || op == OP_ORI ||
        op == OP_XORI || op == OP_SLTI || op == OP_SLTUI || op == OP_CMPI) {
        snprintf(out, sz, "%s %s, %s, #%d%s",
                 alu_ri[op], reg_name(i->rd), reg_name(i->rs1), i->imm13,
                 i->f ? ", F" : "");
        return;
    }
    if (op == OP_SHIFT_R) {
        int kind = i->func7 & 7;
        const char *nm = (kind < 5) ? sh_names[kind] : "SH?";
        snprintf(out, sz, "%s %s, %s, %s%s",
                 nm, reg_name(i->rd), reg_name(i->rs1), reg_name(i->rs2),
                 i->f ? ", F" : "");
        return;
    }
    if (op == OP_SHIFT_I) {
        int imm = (i->raw >> 1) & 0x1FFF;
        int kind = (imm >> 10) & 7;
        int shamt = imm & 0x1F;
        const char *nm = (kind < 5) ? sh_names[kind] : "SH?";
        snprintf(out, sz, "%s %s, %s, #%d%s",
                 nm, reg_name(i->rd), reg_name(i->rs1), shamt,
                 i->f ? ", F" : "");
        return;
    }
    if (op == OP_LD) {
        snprintf(out, sz, "LD %s, [%s + %d]",
                 reg_name(i->rd), reg_name(i->rs1), i->off14);
        return;
    }
    if (op == OP_ST) {
        snprintf(out, sz, "ST %s, [%s + %d]",
                 reg_name(i->rd), reg_name(i->rs1), i->off14);
        return;
    }
    if (op == OP_LUI) {
        snprintf(out, sz, "LUI %s, 0x%05X", reg_name(i->rd), i->imm20);
        return;
    }
    if (op == OP_AUIPC) {
        snprintf(out, sz, "AUIPC %s, 0x%05X", reg_name(i->rd), i->imm20);
        return;
    }
    if (op == OP_BR) {
        int32_t target = pc + 4 + (i->off21 << 2);
        if (i->cond <= COND_AL) {
            if (i->link)
                snprintf(out, sz, "BSR $%08X", (uint32_t)target);
            else if (i->cond == COND_AL)
                snprintf(out, sz, "BRA $%08X", (uint32_t)target);
            else
                snprintf(out, sz, "B%s $%08X", cond_names[i->cond], (uint32_t)target);
        } else {
            snprintf(out, sz, "B?? $%08X", (uint32_t)target);
        }
        return;
    }
    if (op == OP_JMP_ABS) {
        uint32_t target = (pc & 0xF0000000u) | (i->target26 << 2);
        snprintf(out, sz, "JMP $%08X", target);
        return;
    }
    if (op == OP_JSR_ABS) {
        uint32_t target = (pc & 0xF0000000u) | (i->target26 << 2);
        snprintf(out, sz, "JSR $%08X", target);
        return;
    }
    if (op == OP_JMP_REG) {
        snprintf(out, sz, "JMP.REG %s", reg_name(i->rs1));
        return;
    }
    if (op == OP_JSR_REG) {
        snprintf(out, sz, "JSR.REG %s, %s", reg_name(i->rd), reg_name(i->rs1));
        return;
    }
    if (op == OP_RTS) {
        snprintf(out, sz, "RTS");
        return;
    }
    if (op == OP_SYS) {
        switch (i->sys_sub) {
        case SYS_TRAP:   snprintf(out, sz, "TRAP #%d", i->sys_payload); return;
        case SYS_FENCE:  snprintf(out, sz, "FENCE"); return;
        case SYS_FENCER: snprintf(out, sz, "FENCER"); return;
        case SYS_FENCEW: snprintf(out, sz, "FENCEW"); return;
        case SYS_WAI:    snprintf(out, sz, "WAI"); return;
        case SYS_STP:    snprintf(out, sz, "STP"); return;
        }
        snprintf(out, sz, "SYS #%d, %d", i->sys_sub, i->sys_payload);
        return;
    }
    if (op == OP_STACK) {
        int push = (i->raw >> 25) & 1;
        int reg = (i->raw >> 19) & 0x3F;
        snprintf(out, sz, "%s %s", push ? "PULL" : "PUSH", reg_name(reg));
        return;
    }

    /* NOP detection */
    if (i->raw == 0) {
        snprintf(out, sz, "NOP"); return;
    }

    snprintf(out, sz, ".dword $%08X", i->raw);
}

/* ======================================================================== */
/* Traditional pattern matching                                              */
/* ======================================================================== */

/* Look at a window of instructions and try to match multi-instruction
   patterns back to traditional 65xx notation. Returns the number of
   instructions consumed (1 if no pattern matched). */

static int match_traditional(Insn *insns, int count, uint32_t base_pc,
                             char *out, size_t sz) {
    Insn *a = &insns[0];

    /* ---- NOP: ADD R0, R0, R0 (no flags) ---- */
    if (a->op == OP_ADD && a->rd == 0 && a->rs1 == 0 && a->rs2 == 0 && a->f == 0) {
        snprintf(out, sz, "NOP");
        return 1;
    }

    /* ---- XFER patterns → traditional transfers or LDA/STA Rn ---- */
    if (a->op == OP_XFER && a->f == 0) {
        int d = a->rd, s = a->rs1;
        /* Named transfers */
        if (d==REG_X && s==REG_A) { snprintf(out,sz,"TAX"); return 1; }
        if (d==REG_A && s==REG_X) { snprintf(out,sz,"TXA"); return 1; }
        if (d==REG_Y && s==REG_A) { snprintf(out,sz,"TAY"); return 1; }
        if (d==REG_A && s==REG_Y) { snprintf(out,sz,"TYA"); return 1; }
        if (d==REG_X && s==REG_SP){ snprintf(out,sz,"TSX"); return 1; }
        if (d==REG_SP && s==REG_X){ snprintf(out,sz,"TXS"); return 1; }
        if (d==REG_B && s==REG_A) { snprintf(out,sz,"TAB"); return 1; }
        if (d==REG_A && s==REG_B) { snprintf(out,sz,"TBA"); return 1; }
        if (d==REG_D && s==REG_A) { snprintf(out,sz,"TCD"); return 1; }
        if (d==REG_A && s==REG_D) { snprintf(out,sz,"TDC"); return 1; }
        if (d==REG_SP && s==REG_A){ snprintf(out,sz,"TCS"); return 1; }
        if (d==REG_A && s==REG_SP){ snprintf(out,sz,"TSC"); return 1; }
        if (d==REG_A && s==REG_T) { snprintf(out,sz,"TTA"); return 1; }
        if (d==REG_T && s==REG_A) { snprintf(out,sz,"TAT"); return 1; }
        if (d==REG_Y && s==REG_X) { snprintf(out,sz,"TXY"); return 1; }
        if (d==REG_X && s==REG_Y) { snprintf(out,sz,"TYX"); return 1; }

        /* XFER A, Rn → LDA Rn */
        if (d == REG_A && s >= 0 && s <= 55) {
            snprintf(out, sz, "LDA R%d", s);
            return 1;
        }
        /* XFER Rn, A → STA Rn */
        if (s == REG_A && d >= 0 && d <= 55) {
            snprintf(out, sz, "STA R%d", d);
            return 1;
        }
        /* Generic MOV */
        snprintf(out, sz, "MOV %s, %s", reg_name(d), reg_name(s));
        return 1;
    }

    /* ---- LUI+ORI → LDA/LDX/LDY #const (only for named regs) ---- */
    if (a->op == OP_LUI && count >= 2) {
        Insn *b = &insns[1];
        if (b->op == OP_ORI && b->rd == a->rd && b->rs1 == a->rd) {
            uint32_t val = (a->imm20 << 12) | (((uint32_t)b->raw >> 1) & 0xFFF);
            if (a->rd == REG_A) { snprintf(out, sz, "LDA #$%08X", val); return 2; }
            if (a->rd == REG_X) { snprintf(out, sz, "LDX #$%08X", val); return 2; }
            if (a->rd == REG_Y) { snprintf(out, sz, "LDY #$%08X", val); return 2; }
        }
    }

    /* ---- ADDI Rd, R0, #imm → small constant load ---- */
    if (a->op == OP_ADDI && a->rs1 == REG_ZERO && a->f == 0) {
        if (a->rd == REG_A) { snprintf(out, sz, "LDA #%d", a->imm13); return 1; }
        if (a->rd == REG_X) { snprintf(out, sz, "LDX #%d", a->imm13); return 1; }
        if (a->rd == REG_Y) { snprintf(out, sz, "LDY #%d", a->imm13); return 1; }
    }

    /* ---- XFER Rd, R0 → load zero ---- */
    if (a->op == OP_XFER && a->rs1 == REG_ZERO && a->f == 0) {
        if (a->rd == REG_A) { snprintf(out, sz, "LDA #0"); return 1; }
        if (a->rd == REG_X) { snprintf(out, sz, "LDX #0"); return 1; }
        if (a->rd == REG_Y) { snprintf(out, sz, "LDY #0"); return 1; }
    }

    /* ---- LD A, [B + off] → LDA B+$off ---- */
    if (a->op == OP_LD && a->rs1 == REG_B) {
        if (a->rd == REG_A) snprintf(out, sz, "LDA B+$%04X", a->off14 & 0xFFFF);
        else if (a->rd == REG_X) snprintf(out, sz, "LDX B+$%04X", a->off14 & 0xFFFF);
        else if (a->rd == REG_Y) snprintf(out, sz, "LDY B+$%04X", a->off14 & 0xFFFF);
        else snprintf(out, sz, "LD %s, [B + %d]", reg_name(a->rd), a->off14);
        return 1;
    }

    /* ---- ST A, [B + off] → STA B+$off ---- */
    if (a->op == OP_ST && a->rs1 == REG_B) {
        if (a->rd == REG_A) snprintf(out, sz, "STA B+$%04X", a->off14 & 0xFFFF);
        else if (a->rd == REG_X) snprintf(out, sz, "STX B+$%04X", a->off14 & 0xFFFF);
        else if (a->rd == REG_Y) snprintf(out, sz, "STY B+$%04X", a->off14 & 0xFFFF);
        else if (a->rd == REG_ZERO) snprintf(out, sz, "STZ B+$%04X", a->off14 & 0xFFFF);
        else snprintf(out, sz, "ST %s, [B + %d]", reg_name(a->rd), a->off14);
        return 1;
    }

    /* ---- LD A, [Rn + 0] → LDA (Rn) indirect ---- */
    if (a->op == OP_LD && a->rd == REG_A && a->off14 == 0 &&
        a->rs1 > 0 && a->rs1 <= 55) {
        snprintf(out, sz, "LDA (R%d)", a->rs1);
        return 1;
    }

    /* ---- SUBI SP,SP,4 + ST Rn,[SP+0] → PUSH Rn / PHA etc. ---- */
    if (a->op == OP_SUBI && a->rd == REG_SP && a->rs1 == REG_SP &&
        a->imm13 == 4 && a->f == 0 && count >= 2) {
        Insn *b = &insns[1];
        if (b->op == OP_ST && b->rs1 == REG_SP && b->off14 == 0) {
            int r = b->rd;
            if (r == REG_A) snprintf(out, sz, "PHA");
            else if (r == REG_X) snprintf(out, sz, "PHX");
            else if (r == REG_Y) snprintf(out, sz, "PHY");
            else if (r == REG_B) snprintf(out, sz, "PHB");
            else if (r == REG_D) snprintf(out, sz, "PHD");
            else snprintf(out, sz, "PUSH %s", reg_name(r));
            return 2;
        }
    }

    /* ---- LD Rn,[SP+0] + ADDI SP,SP,4 → PULL Rn / PLA etc. ---- */
    if (a->op == OP_LD && a->rs1 == REG_SP && a->off14 == 0 && count >= 2) {
        Insn *b = &insns[1];
        if (b->op == OP_ADDI && b->rd == REG_SP && b->rs1 == REG_SP &&
            b->imm13 == 4 && b->f == 0) {
            int r = a->rd;
            if (r == REG_A) snprintf(out, sz, "PLA");
            else if (r == REG_X) snprintf(out, sz, "PLX");
            else if (r == REG_Y) snprintf(out, sz, "PLY");
            else if (r == REG_B) snprintf(out, sz, "PLB");
            else if (r == REG_D) snprintf(out, sz, "PLD");
            else snprintf(out, sz, "PULL %s", reg_name(r));
            return 2;
        }
    }

    /* ---- ADD A,A,Rn (F=1) → ADC Rn ---- */
    if (a->op == OP_ADD && a->rd == REG_A && a->rs1 == REG_A && a->f == 1 &&
        a->rs2 > 0 && a->rs2 <= 55) {
        snprintf(out, sz, "ADC R%d", a->rs2);
        return 1;
    }
    /* ---- SUB A,A,Rn (F=1) → SBC Rn ---- */
    if (a->op == OP_SUB && a->rd == REG_A && a->rs1 == REG_A && a->f == 1 &&
        a->rs2 > 0 && a->rs2 <= 55) {
        snprintf(out, sz, "SBC R%d", a->rs2);
        return 1;
    }
    /* ---- AND A,A,Rn (F=1) → AND Rn ---- */
    if (a->op == OP_AND && a->rd == REG_A && a->rs1 == REG_A && a->f == 1 &&
        a->rs2 > 0 && a->rs2 <= 55) {
        snprintf(out, sz, "AND R%d", a->rs2);
        return 1;
    }
    /* ---- OR A,A,Rn (F=1) → ORA Rn ---- */
    if (a->op == OP_OR && a->rd == REG_A && a->rs1 == REG_A && a->f == 1 &&
        a->rs2 > 0 && a->rs2 <= 55) {
        snprintf(out, sz, "ORA R%d", a->rs2);
        return 1;
    }
    /* ---- XOR A,A,Rn (F=1) → EOR Rn ---- */
    if (a->op == OP_XOR && a->rd == REG_A && a->rs1 == REG_A && a->f == 1 &&
        a->rs2 > 0 && a->rs2 <= 55) {
        snprintf(out, sz, "EOR R%d", a->rs2);
        return 1;
    }
    /* ---- CMP R0,A,Rn (F=1) → CMP Rn ---- */
    if (a->op == OP_CMP && a->rd == REG_ZERO && a->rs1 == REG_A && a->f == 1 &&
        a->rs2 > 0 && a->rs2 <= 55) {
        snprintf(out, sz, "CMP R%d", a->rs2);
        return 1;
    }

    /* ---- Specific INC/DEC/INX/DEX/INY/DEY (must come BEFORE generic ADC/SBC) ---- */
    if (a->op == OP_ADDI && a->rd == REG_A && a->rs1 == REG_A && a->imm13 == 1 && a->f == 1) {
        snprintf(out, sz, "INC"); return 1;
    }
    if (a->op == OP_SUBI && a->rd == REG_A && a->rs1 == REG_A && a->imm13 == 1 && a->f == 1) {
        snprintf(out, sz, "DEC"); return 1;
    }
    if (a->op == OP_ADDI && a->rd == REG_X && a->rs1 == REG_X && a->imm13 == 1 && a->f == 1) {
        snprintf(out, sz, "INX"); return 1;
    }
    if (a->op == OP_SUBI && a->rd == REG_X && a->rs1 == REG_X && a->imm13 == 1 && a->f == 1) {
        snprintf(out, sz, "DEX"); return 1;
    }
    if (a->op == OP_ADDI && a->rd == REG_Y && a->rs1 == REG_Y && a->imm13 == 1 && a->f == 1) {
        snprintf(out, sz, "INY"); return 1;
    }
    if (a->op == OP_SUBI && a->rd == REG_Y && a->rs1 == REG_Y && a->imm13 == 1 && a->f == 1) {
        snprintf(out, sz, "DEY"); return 1;
    }
    /* ---- INC/DEC Rn (GPR) ---- */
    if (a->op == OP_ADDI && a->rd == a->rs1 && a->imm13 == 1 && a->f == 1 &&
        a->rd > 0 && a->rd <= 55) {
        snprintf(out, sz, "INC R%d", a->rd); return 1;
    }
    if (a->op == OP_SUBI && a->rd == a->rs1 && a->imm13 == 1 && a->f == 1 &&
        a->rd > 0 && a->rd <= 55) {
        snprintf(out, sz, "DEC R%d", a->rd); return 1;
    }

    /* ---- Generic traditional ALU immediate (ADC/SBC/AND/ORA/EOR #imm) ---- */
    if (a->op == OP_ADDI && a->rd == REG_A && a->rs1 == REG_A && a->f == 1) {
        snprintf(out, sz, "ADC #%d", a->imm13);
        return 1;
    }
    if (a->op == OP_SUBI && a->rd == REG_A && a->rs1 == REG_A && a->f == 1) {
        snprintf(out, sz, "SBC #%d", a->imm13);
        return 1;
    }
    if (a->op == OP_ANDI && a->rd == REG_A && a->rs1 == REG_A && a->f == 1) {
        snprintf(out, sz, "AND #$%X", a->imm13 & 0x1FFF);
        return 1;
    }
    if (a->op == OP_ORI && a->rd == REG_A && a->rs1 == REG_A && a->f == 1) {
        snprintf(out, sz, "ORA #$%X", a->imm13 & 0x1FFF);
        return 1;
    }
    if (a->op == OP_XORI && a->rd == REG_A && a->rs1 == REG_A && a->f == 1) {
        snprintf(out, sz, "EOR #$%X", a->imm13 & 0x1FFF);
        return 1;
    }
    if (a->op == OP_CMPI && a->rd == REG_ZERO && a->rs1 == REG_A && a->f == 1) {
        snprintf(out, sz, "CMP #%d", a->imm13);
        return 1;
    }
    if (a->op == OP_CMPI && a->rd == REG_ZERO && a->rs1 == REG_X && a->f == 1) {
        snprintf(out, sz, "CPX #%d", a->imm13);
        return 1;
    }
    if (a->op == OP_CMPI && a->rd == REG_ZERO && a->rs1 == REG_Y && a->f == 1) {
        snprintf(out, sz, "CPY #%d", a->imm13);
        return 1;
    }

    /* ---- Shift by 1 → ASL/LSR/ROL/ROR (accumulator or GPR) ---- */
    if (a->op == OP_SHIFT_I && a->rd == a->rs1 && a->f == 1) {
        int imm = (a->raw >> 1) & 0x1FFF;
        int kind = (imm >> 10) & 7;
        int shamt = imm & 0x1F;
        if (shamt == 1 && kind < 5 && kind != 2) {
            static const char *trad_sh[] = {"ASL","LSR","???","ROL","ROR"};
            if (a->rd == REG_A) {
                snprintf(out, sz, "%s", trad_sh[kind]);
            } else {
                snprintf(out, sz, "%s R%d", trad_sh[kind], a->rd);
            }
            return 1;
        }
    }

    /* ---- ANDI R0, A, #imm (F=1) → BIT #imm ---- */
    if (a->op == OP_ANDI && a->rd == REG_ZERO && a->rs1 == REG_A && a->f == 1) {
        snprintf(out, sz, "BIT #$%X", a->imm13 & 0x1FFF);
        return 1;
    }

    /* ---- AND R0, A, Rn (F=1) → BIT Rn ---- */
    if (a->op == OP_AND && a->rd == REG_ZERO && a->rs1 == REG_A && a->f == 1) {
        snprintf(out, sz, "BIT R%d", a->rs2);
        return 1;
    }

    /* ---- ADD T, Rn, Y + LD A, [T+0] → LDA (Rn),Y ---- */
    if (a->op == OP_ADD && a->rd == REG_T && a->rs2 == REG_Y && count >= 2) {
        Insn *b = &insns[1];
        if (b->op == OP_LD && b->rd == REG_A && b->rs1 == REG_T && b->off14 == 0) {
            int rn = a->rs1;
            if (rn >= 0 && rn <= 55) {
                snprintf(out, sz, "LDA (R%d),Y", rn);
                return 2;
            }
        }
    }

    /* ---- ADD T, Rn, X + LD A, [T+0] → LDA (Rn,X) ---- */
    if (a->op == OP_ADD && a->rd == REG_T && a->rs2 == REG_X && count >= 2) {
        Insn *b = &insns[1];
        if (b->op == OP_LD && b->rd == REG_A && b->rs1 == REG_T && b->off14 == 0) {
            int rn = a->rs1;
            if (rn >= 0 && rn <= 55) {
                snprintf(out, sz, "LDA (R%d,X)", rn);
                return 2;
            }
        }
    }

    /* ---- ADD T, B, X + LD/ST A, [T+off] → LDA/STA B+$off,X ---- */
    if (a->op == OP_ADD && a->rd == REG_T && a->rs1 == REG_B && a->rs2 == REG_X && count >= 2) {
        Insn *b = &insns[1];
        if ((b->op == OP_LD || b->op == OP_ST) && b->rs1 == REG_T) {
            const char *mn = (b->op == OP_LD) ? "LDA" : "STA";
            if (b->rd == REG_X) mn = (b->op == OP_LD) ? "LDX" : "STX";
            if (b->rd == REG_Y) mn = (b->op == OP_LD) ? "LDY" : "STY";
            snprintf(out, sz, "%s B+$%04X,X", mn, b->off14 & 0xFFFF);
            return 2;
        }
    }
    /* ---- ADD T, B, Y + LD/ST A, [T+off] → LDA/STA B+$off,Y ---- */
    if (a->op == OP_ADD && a->rd == REG_T && a->rs1 == REG_B && a->rs2 == REG_Y && count >= 2) {
        Insn *b = &insns[1];
        if ((b->op == OP_LD || b->op == OP_ST) && b->rs1 == REG_T) {
            const char *mn = (b->op == OP_LD) ? "LDA" : "STA";
            snprintf(out, sz, "%s B+$%04X,Y", mn, b->off14 & 0xFFFF);
            return 2;
        }
    }

    /* ---- SHIFT_I with SHL 24 + SAR 24 → SEXT8 ---- */
    if (a->op == OP_SHIFT_I && count >= 2) {
        int imm_a = (a->raw >> 1) & 0x1FFF;
        int kind_a = (imm_a >> 10) & 7;
        int shamt_a = imm_a & 0x1F;
        Insn *b = &insns[1];
        if (b->op == OP_SHIFT_I) {
            int imm_b = (b->raw >> 1) & 0x1FFF;
            int kind_b = (imm_b >> 10) & 7;
            int shamt_b = imm_b & 0x1F;
            if (kind_a == SH_SHL && kind_b == SH_SAR && shamt_a == 24 && shamt_b == 24 && b->rs1 == a->rd && b->rd == a->rd) {
                snprintf(out, sz, "SEXT8 %s, %s", reg_name(b->rd), reg_name(a->rs1));
                return 2;
            }
            if (kind_a == SH_SHL && kind_b == SH_SAR && shamt_a == 16 && shamt_b == 16 && b->rs1 == a->rd && b->rd == a->rd) {
                snprintf(out, sz, "SEXT16 %s, %s", reg_name(b->rd), reg_name(a->rs1));
                return 2;
            }
            if (kind_a == SH_SHL && kind_b == SH_SHR && shamt_a == 16 && shamt_b == 16 && b->rs1 == a->rd && b->rd == a->rd) {
                snprintf(out, sz, "ZEXT16 %s, %s", reg_name(b->rd), reg_name(a->rs1));
                return 2;
            }
        }
    }
    /* ---- ANDI Rd, Rs, 0xFF → ZEXT8 ---- */
    if (a->op == OP_ANDI && a->imm13 == 0xFF && a->f == 1) {
        snprintf(out, sz, "ZEXT8 %s, %s", reg_name(a->rd), reg_name(a->rs1));
        return 1;
    }

    /* No pattern matched -- fall back to raw disassembly */
    dis_raw(a, base_pc, out, sz);
    return 1;
}

/* ======================================================================== */
/* Hex file reader                                                           */
/* ======================================================================== */

#define MAX_CODE (512 * 1024)
static uint8_t code[MAX_CODE];

static int read_hex(const char *filename, uint32_t *max_phy) {
    FILE *f = fopen(filename, "r");
    if (!f) { perror(filename); return -1; }
    memset(code, 0xCD, sizeof(code));
    char line[256];
    uint32_t addr = 0;
    *max_phy = 0;
    while (fgets(line, sizeof(line), f)) {
        size_t len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r')) line[--len] = 0;
        if (len < 32) { addr += 16; continue; }
        /* RSD format: 4 words per line, high-address word first */
        uint32_t w[4];
        if (sscanf(line, "%08X%08X%08X%08X", &w[3], &w[2], &w[1], &w[0]) != 4) {
            addr += 16;
            continue;
        }
        for (int i = 0; i < 4; i++) {
            uint32_t a = addr + i * 4;
            if (a + 3 < MAX_CODE) {
                code[a+0] = (w[i]>>0)&0xFF;
                code[a+1] = (w[i]>>8)&0xFF;
                code[a+2] = (w[i]>>16)&0xFF;
                code[a+3] = (w[i]>>24)&0xFF;
                if (w[i] != 0xCDCDCDCD && a+4 > *max_phy) *max_phy = a+4;
            }
        }
        addr += 16;
    }
    fclose(f);
    return 0;
}

static uint32_t read32_at(uint32_t phy) {
    if (phy + 3 >= MAX_CODE) return 0xCDCDCDCD;
    return (uint32_t)code[phy] | ((uint32_t)code[phy+1]<<8)
         | ((uint32_t)code[phy+2]<<16) | ((uint32_t)code[phy+3]<<24);
}

/* ======================================================================== */
/* Main                                                                      */
/* ======================================================================== */

int main(int argc, char **argv) {
    const char *input = NULL;
    int raw_mode = 0;
    uint32_t start_addr = 0x1000;
    uint32_t end_addr = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-r")) raw_mode = 1;
        else if (!strcmp(argv[i], "-t")) raw_mode = 0;
        else if (!strcmp(argv[i], "-s") && i+1 < argc) start_addr = strtoul(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "-e") && i+1 < argc) end_addr = strtoul(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            printf("Usage: m65f32dis [-r|-t] [-s start] [-e end] input.hex\n");
            printf("  -r : raw fixed32 mnemonics\n");
            printf("  -t : traditional notation (default)\n");
            printf("  -s : start address (default: 0x1000)\n");
            printf("  -e : end address (default: auto-detect)\n");
            return 0;
        }
        else if (argv[i][0] != '-') input = argv[i];
        else { fprintf(stderr, "Unknown option: %s\n", argv[i]); return 1; }
    }

    if (!input) { fprintf(stderr, "Usage: m65f32dis [-r|-t] input.hex\n"); return 1; }

    uint32_t max_phy = 0;
    if (read_hex(input, &max_phy) < 0) return 1;
    if (end_addr == 0) end_addr = max_phy;
    if (end_addr <= start_addr) { fprintf(stderr, "No code to disassemble\n"); return 1; }

    /* Pre-decode all instructions */
    int max_insns = (end_addr - start_addr) / 4;
    Insn *insns = calloc(max_insns, sizeof(Insn));
    if (!insns) { fprintf(stderr, "out of memory\n"); return 1; }
    for (int i = 0; i < max_insns; i++) {
        uint32_t w = read32_at(start_addr + i * 4);
        insns[i] = decode(w);
    }

    /* Disassemble with pattern matching */
    char buf[256];
    int idx = 0;
    while (idx < max_insns) {
        uint32_t pc = start_addr + idx * 4;
        int remaining = max_insns - idx;
        int consumed;

        if (raw_mode) {
            dis_raw(&insns[idx], pc, buf, sizeof(buf));
            consumed = 1;
        } else {
            consumed = match_traditional(&insns[idx], remaining, pc, buf, sizeof(buf));
        }

        /* Print with address and raw hex */
        if (consumed == 1) {
            printf("  %08X  %08X          %s\n", pc, insns[idx].raw, buf);
        } else if (consumed == 2) {
            printf("  %08X  %08X %08X  %s\n", pc, insns[idx].raw, insns[idx+1].raw, buf);
        } else {
            printf("  %08X  ", pc);
            for (int j = 0; j < consumed; j++) printf("%08X ", insns[idx+j].raw);
            printf(" %s\n", buf);
        }
        idx += consumed;
    }

    free(insns);
    return 0;
}
