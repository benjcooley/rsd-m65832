// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
//
// M65832 decoded branch resolver.
// Detects early branch mispredictions at decode time by comparing
// BTB predictions against targets computable from the instruction word.
//

import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import FetchUnitTypes::*;

module DecodedBranchResolver(
    input logic clk,
    input logic rst,
    input logic stall,
    input logic decodeComplete,

    input logic insnValidIn[DECODE_WIDTH],
    input InsnPath isf[DECODE_WIDTH],
    input BranchPred brPredIn[DECODE_WIDTH],
    input PC_Path pc[DECODE_WIDTH],
    input InsnInfo insnInfo[DECODE_WIDTH],

    output logic insnValidOut[DECODE_WIDTH],
    output logic insnFlushed[DECODE_WIDTH],
    output logic insnFlushTriggering[DECODE_WIDTH],
    output logic flushTriggered,
    output BranchPred brPredOut[DECODE_WIDTH],
    output PC_Path recoveredPC
);

    logic flushDetected;
    logic flushDetectedAny;
    PC_Path recoveredPCCandidate;

    M65_OpCode opcode[DECODE_WIDTH];
    logic [20:0] off21_arr[DECODE_WIDTH];
    logic [3:0] cond4_arr[DECODE_WIDTH];
    logic [25:0] target26_arr[DECODE_WIDTH];
    PC_Path brTarget[DECODE_WIDTH];
    PC_Path fallthrough[DECODE_WIDTH];
    PC_Path jmpTarget[DECODE_WIDTH];

    always_comb begin
        flushDetectedAny = FALSE;
        recoveredPCCandidate = '0;

        for (int i = 0; i < DECODE_WIDTH; i++) begin
            opcode[i] = M65_OpCode'(isf[i][31:26]);
            off21_arr[i] = isf[i][20:0];
            cond4_arr[i] = isf[i][25:22];
            target26_arr[i] = isf[i][25:0];

            // B21 target: PC + 4 + signext(off21) << 2
            brTarget[i] = ToAddrFromPC(pc[i])
                        + PC_OPERAND_OFFSET
                        + {{(ADDR_WIDTH-23){off21_arr[i][20]}}, off21_arr[i], 2'b00};

            fallthrough[i] = ToAddrFromPC(pc[i]) + PC_OPERAND_OFFSET;

            // J26 target: {PC[31:28], target26, 2'b00}
            jmpTarget[i] = ToPC_FromAddr(
                {ToAddrFromPC(pc[i])[31:28], target26_arr[i], 2'b00}
            );
        end

        for (int i = 0; i < DECODE_WIDTH; i++) begin
            insnValidOut[i] = insnValidIn[i];
            insnFlushed[i] = FALSE;
            insnFlushTriggering[i] = FALSE;
            brPredOut[i] = brPredIn[i];
            flushDetected = FALSE;

            if (insnValidIn[i] && !flushDetectedAny) begin

                if (insnInfo[i].writePC) begin
                    if (insnInfo[i].isRelBranch) begin
                        // B21 branch
                        if (cond4_arr[i] == 4'h8) begin
                            // Unconditional (BRA): always taken
                            if (!brPredIn[i].predTaken ||
                                ToPC_FromAddr(brTarget[i]) != brPredIn[i].predAddr) begin
                                flushDetected = TRUE;
                                recoveredPCCandidate = ToPC_FromAddr(brTarget[i]);
                            end
                            brPredOut[i].predTaken = TRUE;
                            brPredOut[i].predAddr  = ToPC_FromAddr(brTarget[i]);
                        end
                        else begin
                            // Conditional: can only verify target if predicted taken
                            if (brPredIn[i].predTaken &&
                                ToPC_FromAddr(brTarget[i]) != brPredIn[i].predAddr) begin
                                flushDetected = TRUE;
                                recoveredPCCandidate = ToPC_FromAddr(brTarget[i]);
                                brPredOut[i].predAddr = ToPC_FromAddr(brTarget[i]);
                            end
                        end

                    end
                    else if (opcode[i] == M65_JMP_ABS || opcode[i] == M65_JSR_ABS) begin
                        // J26 absolute jump
                        if (!brPredIn[i].predTaken ||
                            jmpTarget[i] != brPredIn[i].predAddr) begin
                            flushDetected = TRUE;
                            recoveredPCCandidate = jmpTarget[i];
                        end
                        brPredOut[i].predTaken = TRUE;
                        brPredOut[i].predAddr  = jmpTarget[i];
                    end
                    // JMP_REG, JSR_REG, RTS: register-indirect, not resolvable
                end
            end

            if (flushDetected) begin
                flushDetectedAny = TRUE;
                insnFlushTriggering[i] = TRUE;
            end

            if (flushDetectedAny && !flushDetected) begin
                insnFlushed[i] = TRUE;
                insnValidOut[i] = FALSE;
            end
        end

        flushTriggered = flushDetectedAny;
        recoveredPC = recoveredPCCandidate;
    end

endmodule
