# M65832/vcore Project Roadmap

**Status:** Active Development
**Last Updated:** March 2026

## Overview

This document tracks the development stages of the **vcore** -- the
out-of-order pipelined processor core for the m65832. The vcore is a fork
of the [RSD RISC-V OoO processor](https://github.com/rsd-devel/rsd) with
the RISC-V front-end replaced by an m65832 fixed32 decoder.

All work described here is scoped to **this repository** (`rsd-m65832`).
Toolchain work (emulator, assembler, LLVM) lives in the
[m65832](https://github.com/benjcooley/m65832) and
[llvm-m65832](https://github.com/benjcooley/llvm-m65832) repositories.

---

## Stage Summary

| Stage | Description | Status | Dependencies |
|-------|-------------|--------|--------------|
| 0 | Repository Setup | Done | -- |
| 1 | Decoder and Type System | Current | -- |
| 2 | Flag Register Support | Pending | Stage 1 |
| 3 | Pipeline Adaptation | Pending | Stages 1, 2 |
| 4 | Simulation and Validation | Pending | Stages 1-3; m65832 assembler |
| 5 | Hardware Bring-Up | Pending | Stage 4 |
| 6 | System Integration | Pending | Stage 5; m65832 toolchain |

---

## Stage 0: Repository Setup (Done)

Fork RSD, adapt build system, remove RISC-V specific code.

**Deliverables:**

- Verilator 5.x / macOS build fixes (`Makefile.verilator.mk`, `TestMain.cpp`, `ICache.sv`)
- `rsd-upstream` branch and `rsd-baseline` tag preserving the original fork point
- RISC-V test code deleted (`Asm/`, `C/`, `Coremark/`, `Dhrystone/`, `Zephyr/`, `riscv-compliance/`)
- RISC-V decoder deleted (`Decoder.sv`, `DecodedBranchResolver.sv`)
- Repository reorganized: RSD docs moved to `Processor/Docs/`, new README for vcore
- 23 generic unit tests (cache, scheduler, register file, divider) confirmed independent of deleted code

---

## Stage 1: Decoder and Type System (Current)

Update the SystemVerilog type system for m65832 and implement the fixed32
instruction decoder. Detailed plan: [Vcore_Decoder_Plan.md](Vcore_Decoder_Plan.md)

**Deliverables:**

- Updated type definitions (`BasicTypes.sv`, `MicroArchConf.sv`, `OpFormat.sv`, `MicroOp.sv`)
  supporting 64 integer registers, 16 FP registers, m65832 opcodes, NZVC flags, and F-bit
- New `Decoder.sv` implementing the full m65832 fixed32 opcode map (all instruction formats:
  R3, I13F, M14, U20, B21, J26, JR, Q20, STACK, FP3, FPM, FPI)
- New `DecodedBranchResolver.sv` for m65832 branch target extraction (B21, J26, JR)
- `CoreSources.inc.mk` updated with new decoder files

**Key design decisions:**

- `MICRO_OP_MAX_NUM` = 1 (fixed32 is 1:1 instruction-to-operation, no cracking)
- Flags register is logical register 64 (`LREG_FLAGS`), renamed through the standard RMT
- `writeFlags` and `readFlags` bits added to `OpInfo` for flag dataflow tracking

---

## Stage 2: Flag Register Support

Add the P (flags) register to the out-of-order rename and execution pipeline.

**Deliverables:**

- Flags register (`LREG_FLAGS`) integrated into the rename table (RMT)
- `OpSrc` extended with `phySrcFlagsRegNum` for branch instructions
- `OpDst` extended with `phyFlagsDstRegNum` for F=1 instructions
- ALU flag outputs (N, Z, V, C) computed and written back to flags physical register
- Flag-based branch evaluation (`IsConditionEnabledFlags`) replacing RISC-V register comparisons
- Active list and recovery logic updated for dual-destination (data + flags) instructions

**Dependencies:** Stage 1 (type system must compile first)

---

## Stage 3: Pipeline Adaptation

Update pipeline stages that reference RISC-V specific encoding or semantics.

**Deliverables:**

- `IntegerRegisterReadStage.sv`: m65832 immediate expansion (13-bit I13F, 20-bit U20,
  14-bit M14 address offset) replacing `RISCV_OpImm()`
- `IntegerExecutionStage.sv`: m65832 branch target computation (B21 displacement,
  JR register-indirect) replacing RISC-V branch format
- `DecodeStage.sv`: m65832 `ISF_Common` overlay for branch resolver
- `MemoryExecutionStage.sv`: CSR/privilege path adaptation
- Operand selection updated for 6-bit register fields and flags source

**Dependencies:** Stages 1 and 2

---

## Stage 4: Simulation and Validation

Build test infrastructure and validate the pipeline against known-good execution traces.

**Deliverables:**

- Minimal m65832 fixed32 assembler (Python script producing `code.hex`)
- Basic test programs: NOP, ALU (ADD/SUB/AND/OR), load/store, unconditional branch,
  flag-setting + conditional branch (ADD.F + BEQ), function call/return (JSR/RTS)
- `TestMain.sv` / `TestMain.cpp` adapted for m65832 register conventions (64 regs, PC_GOAL)
- `TestCommands.inc.mk` populated with m65832 test targets
- Verilator simulation passing all basic tests
- Validation against m65832 emulator commit traces (when emulator fixed32 support is available)

**Dependencies:** Stages 1-3; m65832 assembler (can be a minimal Python script initially)

---

## Stage 5: Hardware Bring-Up

Synthesize and validate on FPGA hardware.

**Milestones:**

| ID | Target | Description |
|----|--------|-------------|
| HW0 | KV260 | Boot ROM + BRAM + UART, basic instruction execution |
| HW1 | KV260 | Assembly test suite passing on hardware |
| HW2 | KV260 | Branch predictor + caches enabled, performance measurement |
| HW3 | KV260 | Full SoC integration (MMU, interrupts, system bus) |
| HW4 | DE25-Nano | Port to Agilex 5 (Quartus), SDRAM controller |

**Dependencies:** Stage 4 (simulation must pass before hardware)

---

## Stage 6: System Integration

Full system bring-up with OS and peripherals.

**Milestones:**

| Milestone | Description |
|-----------|-------------|
| Linux on vcore | Boot Linux using fixed32-compiled kernel on KV260 |
| GPU integration | Connect Milo832 GPU via shared AXI4 system bus |
| Legacy emulation | Cycle-accurate 6502/65816 emulation via cycle-stealing (dual-PC fetch, R43-R55) |
| Full Commodore 256 | Complete SoC: vcore + GPU + audio + peripherals + legacy emulation |

**Dependencies:** Stage 5; m65832 LLVM backend; Milo832 GPU

---

## External Dependencies

| Dependency | Repository | Required By |
|------------|------------|-------------|
| Fixed32 assembler (minimal) | this repo (Python script) | Stage 4 |
| Fixed32 emulator (validation traces) | m65832 | Stage 4 |
| Fixed32 assembler (full) | m65832 | Stage 5 |
| LLVM backend (fixed32 codegen) | llvm-m65832 | Stage 6 |
| Milo832 GPU | milo832 | Stage 6 |

---

## Related Documents

- [Vcore_Decoder_Plan.md](Vcore_Decoder_Plan.md) -- detailed decoder implementation plan
- [M65832_vcore_Roadmap.md](https://github.com/benjcooley/m65832/blob/main/docs/M65832_vcore_Roadmap.md) -- parent project roadmap (includes toolchain stages)
- [M65832_Fixed32_Encoding.md](https://github.com/benjcooley/m65832/blob/main/docs/M65832_Fixed32_Encoding.md) -- instruction encoding specification
- [M65832_Architecture_Reference.md](https://github.com/benjcooley/m65832/blob/main/docs/M65832_Architecture_Reference.md) -- CPU architecture
