# M65832/vcore -- Out-of-Order Pipelined Processor

The **vcore** is the high-performance pipelined processor core for the
[m65832](https://github.com/benjcooley/m65832) 32-bit CPU. It executes
fixed-width 32-bit instructions in W=11 (32-bit native) mode using an
out-of-order superscalar pipeline.

The vcore is a fork of the [RSD RISC-V OoO processor](https://github.com/rsd-devel/rsd)
(Apache 2.0) with the RISC-V front-end replaced by an m65832 decoder
targeting the [fixed32 instruction encoding](https://github.com/benjcooley/m65832/blob/main/docs/M65832_Fixed32_Encoding.md).

## Architecture

| Feature | Specification |
|---------|---------------|
| ISA | m65832 fixed-width 32-bit (W=11) |
| Pipeline | Out-of-order superscalar |
| Fetch | 2-wide |
| Issue | 6-wide |
| In-flight | Up to 64 instructions (configurable) |
| Registers | R0-R63 (6-bit), 16 FP (F0-F15) |
| Branch prediction | Gshare + bimodal |
| Caches | Non-blocking L1 I$ and D$ |
| Scheduler | Speculative with replay |
| Load/Store | OoO with dynamic memory disambiguation |
| Bus | AXI4 |
| Target FPGA | KV260 (Zynq UltraScale+) |
| Estimated size | ~20-25K LUT |

## Status

The vcore is under active development. Current state:

| Step | Description | Status |
|------|-------------|--------|
| Fork RSD | Baseline OoO pipeline, Verilator simulation | Done |
| Replace decoder | m65832 fixed32 opcode map, 6-bit register fields, F-bit | Pending |
| Add flags (P register) | NZVC flags in rename table and ALU writeback | Pending |
| Branch resolver | cond4 condition codes instead of RISC-V comparisons | Pending |
| Simulation | Validate against m65832 emulator commit traces | Pending |

See [docs/Vcore_Roadmap.md](docs/Vcore_Roadmap.md) for the full development plan
and [docs/Vcore_Decoder_Plan.md](docs/Vcore_Decoder_Plan.md) for the detailed decoder design.

## Key Differences from RSD (RISC-V)

| Aspect | RSD (RISC-V) | vcore (m65832) |
|--------|-------------|----------------|
| Instruction encoding | RV32IMF | m65832 fixed32 |
| Integer registers | 32 (x0=zero) | 64 (R0=zero, R56-R63=arch) |
| FP registers | 32 | 16 (F0-F15) |
| Branches | Compare two registers | Test NZVC condition codes |
| Flags register | None | P register (N, Z, V, C) |
| Flag policy | N/A | F-bit: F=0 flagless, F=1 sets flags |

## Getting Started

### Prerequisites

* GNU Make, Python 3
* Verilator 5.x (tested with 5.044)
* C++ compiler with C++17 support (Apple Clang 16+, GCC 10+)

### Build and Simulate

```bash
export RSD_ROOT=$(pwd)
cd Processor/Src
make -f Makefile.verilator.mk all       # build (~2-3 min)
make -f Makefile.verilator.mk run       # run default test
```

Run a specific test:

```bash
make -f Makefile.verilator.mk run TEST_CODE=Verification/TestCode/Asm/IntRegImm
```

Generate a Konata pipeline visualization log:

```bash
make -f Makefile.verilator.mk kanata
```

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `RSD_ROOT` | Root directory of this repository (required) |
| `RSD_VERILATOR_BIN` | Path to verilator binary (default: `verilator`) |
| `RSD_GCC_PATH` | RISC-V cross-compiler path (for building new tests) |
| `RSD_GCC_PREFIX` | Cross-compiler prefix (e.g. `riscv32-unknown-elf-`) |

See `Processor/Tools/SetEnv/SetEnv.sh` for the full list.

## Repository Structure

```
├── README.md                  This file
├── LICENSE                    Apache 2.0
├── docs/                      Project roadmap and design documents
├── Processor/
│   ├── Src/                   SystemVerilog source
│   │   ├── Core.sv            Top-level core
│   │   ├── Decoder/           Instruction decoder (RISC-V, to be replaced)
│   │   ├── Pipeline/          All pipeline stages
│   │   ├── Scheduler/         Issue queue, wakeup, replay
│   │   ├── Cache/             L1 I$ and D$
│   │   ├── FetchUnit/         Branch predictor (BTB, Gshare, Bimodal)
│   │   ├── RegisterFile/      Physical register file, bypass network
│   │   ├── RenameLogic/       Register rename, active list, RMT
│   │   ├── ExecUnit/          ALU, shifter, multiplier, divider
│   │   ├── FloatingPointUnit/ FP adder, multiplier, FMA, div/sqrt
│   │   ├── LoadStoreUnit/     Load/store queues, store committer
│   │   ├── Memory/            AXI4 memory interface
│   │   ├── Recovery/          Misprediction recovery
│   │   ├── Privileged/        CSR, interrupts
│   │   └── Verification/      Testbenches and test code
│   ├── Docs/                  RSD upstream documentation
│   ├── Tools/                 Test drivers, Konata converter
│   └── Project/               Build output (Verilator, Vivado, etc.)
```

## Related Repositories

* [m65832](https://github.com/benjcooley/m65832) -- CPU architecture, VHDL core, emulator, assembler
* [llvm-m65832](https://github.com/benjcooley/llvm-m65832) -- LLVM compiler backend

## License

This project is based on [RSD](https://github.com/rsd-devel/rsd) by Ryota Shioya
and contributors (see `Processor/Docs/RSD_CREDITS.md`). Released under the
[Apache License, Version 2.0](LICENSE).

## References

* Susumu Mashimo et al., "An Open Source FPGA-Optimized Out-of-Order RISC-V Soft
  Processor", IEEE International Conference on Field-Programmable Technology (FPT), 2019.
  [Pre-print](https://www.rsg.ci.i.u-tokyo.ac.jp/members/shioya/pdfs/Mashimo-FPT'19.pdf)
* [M65832 Architecture Reference](https://github.com/benjcooley/m65832/blob/main/docs/M65832_Architecture_Reference.md)
* [M65832 Fixed32 Encoding](https://github.com/benjcooley/m65832/blob/main/docs/M65832_Fixed32_Encoding.md)
* [RSD Wiki](https://github.com/rsd-devel/rsd/wiki)
