// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Execution stage
//

import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import PipelineTypes::*;
import DebugTypes::*;
import FetchUnitTypes::*;
import RenameLogicTypes::*;


// m65832 flag-based condition evaluation.
// flagsData[3:0] = {N, Z, V, C} from the physical register holding NZVC.
// Until Phase 4 plumbs the flags register, only COND_AL (unconditional) works correctly.
function automatic logic IsConditionEnabledFlags(CondCode cond, DataPath flagsData);
    M65_Flags flags;
    flags = M65_Flags'(flagsData[3:0]);
    case (cond)
        COND_EQ: return flags.Z;
        COND_NE: return !flags.Z;
        COND_CS: return flags.C;
        COND_CC: return !flags.C;
        COND_MI: return flags.N;
        COND_PL: return !flags.N;
        COND_VS: return flags.V;
        COND_VC: return !flags.V;
        COND_AL: return 1'b1;
        default: return 1'b0;
    endcase
endfunction

//
// 実行ステージ
//

module IntegerExecutionStage(
    IntegerExecutionStageIF.ThisStage port,
    IntegerRegisterReadStageIF.NextStage prev,
    BypassNetworkIF.IntegerExecutionStage bypass,
    RecoveryManagerIF.IntegerExecutionStage recovery,
    ControllerIF.IntegerExecutionStage ctrl,
    DebugIF.IntegerExecutionStage debug
);

    IntegerExecutionStageRegPath pipeReg [INT_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    // --- Pipeline registers
    always_ff@(posedge port.clk)   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= FALSE;
            end
        end
        else if(!ctrl.backEnd.stall) begin  // write data
            pipeReg <= prev.nextStage;
        end
    end

    // Pipeline control
    logic stall, clear;
    logic flush[ INT_ISSUE_WIDTH ];

    IntIssueQueueEntry iqData[INT_ISSUE_WIDTH];
    IntOpInfo  intOpInfo [ INT_ISSUE_WIDTH ];
    BranchPred bPred [ INT_ISSUE_WIDTH ];
    AddrPath pc [ INT_ISSUE_WIDTH ];

    PRegDataPath fuOpA [ INT_ISSUE_WIDTH ];
    PRegDataPath fuOpB [ INT_ISSUE_WIDTH ];
    PRegDataPath dataOut [ INT_ISSUE_WIDTH ];

    // Condition
    logic isCondEnabled [ INT_ISSUE_WIDTH ];

    // ALU
    DataPath aluDataOut [ INT_ISSUE_WIDTH ];
    FlagPath aluFlagsOut [ INT_ISSUE_WIDTH ];
    IntALU_Code aluCode [ INT_ISSUE_WIDTH ];

    for ( genvar i = 0; i < INT_ISSUE_WIDTH; i++ ) begin : BlockALU
        IntALU intALU(
            .aluCode ( aluCode[i] ),
            .fuOpA_In ( fuOpA[i].data ),
            .fuOpB_In ( fuOpB[i].data ),
            .aluDataOut ( aluDataOut[i] ),
            .aluFlagsOut ( aluFlagsOut[i] )
        );
    end

    // Shifter
    ShiftOperandType shiftOperandType [ INT_ISSUE_WIDTH ];
    M65_IntOperandImm shiftImmIn [ INT_ISSUE_WIDTH ];
    DataPath shiftDataOut [ INT_ISSUE_WIDTH ];
    logic shiftCarryOut [ INT_ISSUE_WIDTH ];

    for ( genvar i = 0; i < INT_ISSUE_WIDTH; i++ ) begin : BlockShifter
        Shifter shifter(
            .shiftOperandType( shiftOperandType[i] ),
            .shiftType( shiftImmIn[i].shiftType ),
            .immShiftAmount( shiftImmIn[i].imm[SHIFT_AMOUNT_BIT_SIZE-1:0] ),
            .regShiftAmount( fuOpB[i][SHIFT_AMOUNT_BIT_SIZE-1:0] ),
            .dataIn( fuOpA[i].data ),
            .carryIn( 1'b0 ),
            .dataOut( shiftDataOut[i] ),
            .carryOut( shiftCarryOut[i] )
        );
    end

    // Branch
    logic isBranch [ INT_ISSUE_WIDTH ];
    logic isJump [ INT_ISSUE_WIDTH ];
    logic brTaken  [ INT_ISSUE_WIDTH ];
    BranchResult brResult [ INT_ISSUE_WIDTH ];
    logic predMiss [ INT_ISSUE_WIDTH ];
    logic regValid [ INT_ISSUE_WIDTH ];

    IntOpSubInfo intSubInfo[ INT_ISSUE_WIDTH ];
    BrOpSubInfo  brSubInfo[ INT_ISSUE_WIDTH ];
    PFlagDataPath fuOpFlags [ INT_ISSUE_WIDTH ];
    PFlagDataPath flagsResult [ INT_ISSUE_WIDTH ];

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            iqData[i] = pipeReg[i].intQueueData;
            intOpInfo[i] = iqData[i].intOpInfo;
            intSubInfo[i] = intOpInfo[i].intSubInfo;
            brSubInfo[i] = intOpInfo[i].brSubInfo;
            pc[i] = ToAddrFromPC(iqData[i].pc);
            flush[i] = SelectiveFlushDetector(
                        recovery.toRecoveryPhase,
                        recovery.flushRangeHeadPtr,
                        recovery.flushRangeTailPtr,
                        recovery.flushAllInsns,
                        iqData[i].activeListPtr
                        );

            // Operands (data)
            fuOpA[i] = ( pipeReg[i].bCtrl.rA.valid ? bypass.intSrcRegDataOutA[i] : pipeReg[i].operandA );
            fuOpB[i] = ( pipeReg[i].bCtrl.rB.valid ? bypass.intSrcRegDataOutB[i] : pipeReg[i].operandB );

            // Flags operand (via bypass or register file read)
            fuOpFlags[i] = ( pipeReg[i].bCtrl.rFlags.valid ? bypass.intSrcFlagDataOut[i] : pipeReg[i].operandFlags );

            // Condition evaluation using NZVC flags from the flags register
            isCondEnabled[i] = IsConditionEnabledFlags(iqData[i].cond, {28'b0, fuOpFlags[i].flags});

            // Shifter
            shiftOperandType[i] = intSubInfo[i].shiftType;
            shiftImmIn[i] = M65_IntOperandImm'(intSubInfo[i].shiftIn);

            // ALU
            aluCode[i] = intSubInfo[i].aluCode;

            //
            // データアウト
            //
            unique case ( iqData[i].opType )
            INT_MOP_TYPE_ALU:       dataOut[i].data = aluDataOut[i];
            INT_MOP_TYPE_SHIFT:     dataOut[i].data = shiftDataOut[i];
            //INT_MOP_TYPE_BR, INT_MOP_TYPE_RIJ :        dataOut[i].data = ToPC_FromAddr(pc[i] + PC_OPERAND_OFFSET);
            INT_MOP_TYPE_BR, INT_MOP_TYPE_RIJ :        dataOut[i].data = pc[i] + PC_OPERAND_OFFSET;
            default: /* select */  dataOut[i].data = ( isCondEnabled[i] ? fuOpA[i].data : fuOpB[i].data );
            endcase

            // Compute NZVC flags result
            unique case ( iqData[i].opType )
            INT_MOP_TYPE_ALU: begin
                flagsResult[i].flags = aluFlagsOut[i];
            end
            INT_MOP_TYPE_SHIFT: begin
                flagsResult[i].flags[3] = shiftDataOut[i][DATA_WIDTH-1]; // N
                flagsResult[i].flags[2] = (shiftDataOut[i] == '0);       // Z
                flagsResult[i].flags[1] = 1'b0;                          // V (shifts: no overflow)
                flagsResult[i].flags[0] = shiftCarryOut[i];              // C
            end
            default: begin
                flagsResult[i].flags = '0;
            end
            endcase

            // If invalid registers are read, regValid is negated and this op must be replayed.
            regValid[i] =
                (intSubInfo[i].operandTypeA != OOT_REG || fuOpA[i].valid ) &&
                (intSubInfo[i].operandTypeB != OOT_REG || fuOpB[i].valid ) &&
                (!iqData[i].opSrc.readFlags || fuOpFlags[i].valid );
            dataOut[i].valid = regValid[i];
            flagsResult[i].valid = regValid[i];

            //
            // --- Bypass
            //
            bypass.intCtrlIn[i] = pipeReg[i].bCtrl;
            bypass.intDstRegDataOut[i] = dataOut[i];
            bypass.intDstFlagDataOut[i] = flagsResult[i];

            //
            // --- 分岐
            //
            bPred[i] = brSubInfo[i].bPred;
            isBranch[i] = ( iqData[i].opType inside { INT_MOP_TYPE_BR, INT_MOP_TYPE_RIJ } );
            isJump[i] = 
                (iqData[i].opType == INT_MOP_TYPE_BR && iqData[i].cond == COND_AL)
                    || iqData[i].opType == INT_MOP_TYPE_RIJ;

            // 分岐orレジスタ間接分岐で，条件が有効ならTaken
            brTaken[i] = pipeReg[i].valid && isBranch[i] && isCondEnabled[i];

            // Whether this branch is conditional one or not.
            brResult[i].isCondBr = !isJump[i];
            
            // The address of a branch.
            brResult[i].brAddr = ToPC_FromAddr(pc[i]);

            // m65832 branch target computation
            if (brTaken[i]) begin
                if (iqData[i].opType == INT_MOP_TYPE_BR) begin
                    // B21: PC + 4 + signext(off21) << 2
                    brResult[i].nextAddr = ToPC_FromAddr(
                        pc[i] + PC_OPERAND_OFFSET + ExtendBranchDisplacement(brSubInfo[i].brDisp)
                    );
                end
                else if (brSubInfo[i].operandTypeA == OOT_REG) begin
                    // Register-indirect (JMP_REG, JSR_REG, RTS)
                    brResult[i].nextAddr = ToPC_FromAddr(
                        {fuOpA[i].data[31:2], 2'b00}
                    );
                end
                else begin
                    // Absolute jump (JMP_ABS, JSR_ABS) - target from decode prediction
                    brResult[i].nextAddr = bPred[i].predAddr;
                end
            end
            else begin
                brResult[i].nextAddr = ToPC_FromAddr(pc[i] + INSN_BYTE_WIDTH);
            end
            brResult[i].execTaken = brTaken[i];
            brResult[i].predTaken = bPred[i].predTaken;
            brResult[i].valid = isBranch[i] && pipeReg[i].valid && regValid[i];
            brResult[i].globalHistory = bPred[i].globalHistory;
            brResult[i].phtPrevValue = bPred[i].phtPrevValue;
                    
            // 予測ミス判定
            predMiss[i] =
                brResult[i].valid &&
                (
                     (bPred[i].predTaken != brTaken[i]) ||
                     (brTaken[i] == TRUE &&
                      bPred[i].predAddr != brResult[i].nextAddr)
                );

            brResult[i].mispred = predMiss[i];
        end
    end

    //
    // --- Pipeline レジスタ書き込み
    //
    IntegerRegisterWriteStageRegPath nextStage [ INT_ISSUE_WIDTH ];

    always_comb begin
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            `ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = pipeReg[i].opId;
            `endif

            nextStage[i].intQueueData = pipeReg[i].intQueueData;

            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i]) ? FALSE : pipeReg[i].valid;

            nextStage[i].dataOut = dataOut[i];
            nextStage[i].flagsOut = flagsResult[i];

            nextStage[i].brResult    = brResult[i];
            nextStage[i].brMissPred  = predMiss[i];
        end

        // Output
        port.nextStage = nextStage;

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            debug.intExReg[i].valid = pipeReg[i].valid;
            debug.intExReg[i].flush = flush[i];
            debug.intExReg[i].opId = pipeReg[i].opId;
`ifdef RSD_FUNCTIONAL_SIMULATION
            debug.intExReg[i].dataOut = dataOut[i];
            debug.intExReg[i].fuOpA   = fuOpA[i].data;
            debug.intExReg[i].fuOpB   = fuOpB[i].data;
            debug.intExReg[i].aluCode  = aluCode[i];
            debug.intExReg[i].opType  = iqData[i].opType;
            debug.intExReg[i].brPredMiss = predMiss[i];
`endif
        end
    `endif
end

endmodule : IntegerExecutionStage
