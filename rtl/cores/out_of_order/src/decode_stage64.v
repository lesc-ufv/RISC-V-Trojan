/** @module : decode_stage64
 *  @author : Secure, Trusted, and Assured Microelectronics (STAM) Center

 *  Copyright (c) 2022 Trireme (STAM/SCAI/ASU)
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to deal
 *  in the Software without restriction, including without limitation the rights
 *  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.

 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 *  THE SOFTWARE.
 */

/*
 * We assume that the decode is completely combinational and has can decode an instruction at every cycle
 */

module decode_stage64 #(
    parameter XLEN                = 64,
    parameter LANE_INDEX_WIDTH    = 2,  // Selects between the $EXECUTION_LANES reservation stations
    parameter FULL_DECODE_WIDTH   = 158 // Width of a decoded instruction
) (
    // Instruction fetch port
    input                          fetch_response_valid_i,
    output                         fetch_response_ready_o,
    input [31:0]                   fetch_response_instruction_i,
    input [63:0]                   fetch_response_PC_i,
    input                          fetch_NLP_BTB_hit_i,
    // Issue stage port
    output                         decode_valid_o,
    input                          decode_ready_i,
    output [FULL_DECODE_WIDTH-1:0] decode_instruction_o
);
    wire [31:0] instruction = fetch_response_instruction_i;

    /*
     * RISC-V opcodes
     */
    localparam [6:0] R_TYPE   = 7'b0110011,
                     R32_TYPE = 7'b0111011,
                     I_TYPE   = 7'b0010011,
                     I32_TYPE = 7'b0011011,
                     STORE    = 7'b0100011,
                     LOAD     = 7'b0000011,
                     BRANCH   = 7'b1100011,
                     JALR     = 7'b1100111,
                     JAL      = 7'b1101111,
                     AUIPC    = 7'b0010111,
                     LUI      = 7'b0110111,
                     FENCES   = 7'b0001111,
                     SYSCALL  = 7'b1110011;

    /*
     * More general operation descriptors
     */
    localparam [2:0] OP_STORE  = 3'd0,
                     OP_LOAD   = 3'd1,
                     OP_AUIPC  = 3'd2,
                     OP_JAL    = 3'd3,
                     OP_JALR   = 3'd4,
                     OP_BRANCH = 3'd5,
                     OP_OTHER  = 3'd6;

    function [63:0] sign_extend;
        input [31:0] value;
        begin
            sign_extend = {{32{value[31]}}, value};
        end
    endfunction

    wire [6:0] opcode = instruction[6:0];
    wire [4:0] rs1    = opcode != LUI ? instruction[19:15] : 0;
    wire [4:0] rs2    = instruction[24:20];
    wire [4:0] rd     = instruction[11:7];
    wire [6:0] funct7 = instruction[31:25];
    wire [2:0] funct3 = instruction[14:12];

    wire [31:0] u_imm_32      = {instruction[31:12], 12'b0};
    wire [31:0] i_imm_32      = {{21{instruction[31]}}, instruction[31:20]};
    wire [31:0] s_imm_32      = {{21{instruction[31]}}, instruction[31:25], instruction[11:7]};
    wire [31:0] is            = instruction;
    wire [63:0] branch_target = fetch_response_PC_i + sign_extend({{21{is[31]}}, is[7], is[30:25], is[11:8], 1'b0});
    wire [63:0] JAL_target    = fetch_response_PC_i + sign_extend({{13{is[31]}}, is[19:12], is[20], is[30:21], 1'b0});

    wire [63:0] extend_imm = (opcode == STORE ) ? sign_extend(s_imm_32     )
                           : (opcode == AUIPC ) ? sign_extend(u_imm_32     )
                           : (opcode == LUI   ) ? sign_extend(u_imm_32     )
                           : (opcode == BRANCH) ? branch_target
                           : (opcode == JAL   ) ? JAL_target
                           :                      sign_extend(i_imm_32     );

    wire [5:0] ALU_operation =
        (opcode == JAL)                                                    ? 6'd1             : // JAL   : Pass through
        (opcode == JALR     & funct3 == 3'b000)                            ? 6'd0             : // JALR  : Pass through
        (opcode == AUIPC)                                                  ? 6'd0             : // AUIPC : add PC and (immediate << 12)
        (opcode == BRANCH   & funct3 == 3'b000)                            ? 6'd2             : // BEQ   : equal
        (opcode == BRANCH   & funct3 == 3'b001)                            ? 6'd3             : // BNE   : not equal
        (opcode == BRANCH   & funct3 == 3'b100)                            ? 6'd4             : // BLT   : signed less than
        (opcode == BRANCH   & funct3 == 3'b101)                            ? 6'd5             : // BGE   : signed greater than, equal
        (opcode == BRANCH   & funct3 == 3'b110)                            ? 6'd6             : // BLTU  : unsigned less than
        (opcode == BRANCH   & funct3 == 3'b111)                            ? 6'd7             : // BGEU  : unsigned greater than, equal
        (opcode == I_TYPE   & funct3 == 3'b010)                            ? 6'd4             : // SLTI  : signed less than
        (opcode == I_TYPE   & funct3 == 3'b011)                            ? 6'd6             : // SLTIU : unsigned less than
        (opcode == I_TYPE   & funct3 == 3'b100)                            ? 6'd8             : // XORI  : xor
        (opcode == I_TYPE   & funct3 == 3'b110)                            ? 6'd9             : // ORI   : or
        (opcode == I_TYPE   & funct3 == 3'b111)                            ? 6'd10            : // ANDI  : and
        (opcode == I_TYPE   & funct3 == 3'b001 & funct7[6:1] == 6'b000000) ? 6'd11            : // SLLI  : logical left shift
        (opcode == I_TYPE   & funct3 == 3'b101 & funct7[6:1] == 6'b000000) ? 6'd12            : // SRLI  : logical right shift
        (opcode == I_TYPE   & funct3 == 3'b101 & funct7[6:1] == 6'b010000) ? 6'd13            : // SRAI  : arithemtic right shift
        (opcode == R_TYPE   & funct3 == 3'b000 & funct7 == 7'b0100000)     ? 6'd14            : // SUB   : subtract
        (opcode == R_TYPE   & funct3 == 3'b001 & funct7 == 7'b0000000)     ? 6'd11            : // SLL   : logical left shift
        (opcode == R_TYPE   & funct3 == 3'b010 & funct7 == 7'b0000000)     ? 6'd4             : // SLT   : signed less than
        (opcode == R_TYPE   & funct3 == 3'b011 & funct7 == 7'b0000000)     ? 6'd6             : // SLTU  : signed less than
        (opcode == R_TYPE   & funct3 == 3'b100 & funct7 == 7'b0000000)     ? 6'd8             : // XOR   : xor
        (opcode == R_TYPE   & funct3 == 3'b101 & funct7 == 7'b0000000)     ? 6'd12            : // SRL   : logical right shift
        (opcode == R_TYPE   & funct3 == 3'b101 & funct7 == 7'b0100000)     ? 6'd13            : // SRA   : arithmetic right shift
        (opcode == R_TYPE   & funct3 == 3'b110 & funct7 == 7'b0000000)     ? 6'd9             : // OR    : or
        (opcode == R_TYPE   & funct3 == 3'b111 & funct7 == 7'b0000000)     ? 6'd10            : // AND   : and
        (opcode == LOAD )                                                  ? {3'b000, funct3} : // LD, LW, LWU, LH, LHU, LB, LBU
        (opcode == STORE)                                                  ? {3'b000, funct3} : // SD, SW, SWU, SH, SHU, SB, SBU
        // 64-bit instructions
        (opcode == I32_TYPE & funct3 == 3'b000)                            ? 6'd15            : // ADDIW : 32-bit sign-extended ADDI
        (opcode == I32_TYPE & funct3 == 3'b001 & funct7 == 7'b0000000)     ? 6'd16            : // SLLIW : 32-bit sign-extended logical left shift
        (opcode == I32_TYPE & funct3 == 3'b101 & funct7 == 7'b0000000)     ? 6'd17            : // SRLIW : 32-bit sign-extended logical right shift
        (opcode == I32_TYPE & funct3 == 3'b101 & funct7 == 7'b0100000)     ? 6'd18            : // SRAIW : 32-bit sign-extended arithemtic right shift
        (opcode == R32_TYPE & funct3 == 3'b000 & funct7 == 7'b0000000)     ? 6'd15            : // ADDW  : 32-bit sign-extended ADD
        (opcode == R32_TYPE & funct3 == 3'b001 & funct7 == 7'b0000000)     ? 6'd16            : // SLLW  : 32-bit sign-extended SLL
        (opcode == R32_TYPE & funct3 == 3'b101 & funct7 == 7'b0000000)     ? 6'd17            : // SRLW  : 32-bit sign-extended SRLW
        (opcode == R32_TYPE & funct3 == 3'b101 & funct7 == 7'b0100000)     ? 6'd18            : // SRAW  : 32-bit sign-extended SRAW
        (opcode == R32_TYPE & funct3 == 3'b000 & funct7 == 7'b0100000)     ? 6'd19            : // SUBW  : 32-bit sign-extended SUB
        // 32-bit M-Extension
        (opcode == R_TYPE   & funct3 == 3'b000 & funct7 == 7'b0000001)     ? 6'd20            : // MUL   : Multiply XLEN*XLEN (Lower XLEN in destination register)
        (opcode == R_TYPE   & funct3 == 3'b001 & funct7 == 7'b0000001)     ? 6'd21            : // MULH  : Multiply XLEN*XLEN (Upper XLEN in destination register - signed   * signed)
        (opcode == R_TYPE   & funct3 == 3'b011 & funct7 == 7'b0000001)     ? 6'd22            : // MULHU : Multiply XLEN*XLEN (Upper XLEN in destination register - signed   * unsigned)
        (opcode == R_TYPE   & funct3 == 3'b010 & funct7 == 7'b0000001)     ? 6'd23            : // MULHSU: Multiply XLEN*XLEN (Upper XLEN in destination register - unsigned * unsigned)
        (opcode == R_TYPE   & funct3 == 3'b100 & funct7 == 7'b0000001)     ? 6'd24            : // DIV   : Divide   XLEN/XLEN (signed  )
        (opcode == R_TYPE   & funct3 == 3'b101 & funct7 == 7'b0000001)     ? 6'd25            : // DIVU  : Divide   XLEN/XLEN (unsigned)
        (opcode == R_TYPE   & funct3 == 3'b110 & funct7 == 7'b0000001)     ? 6'd26            : // REM   : Remainder of the corresponding divide (signed  )
        (opcode == R_TYPE   & funct3 == 3'b111 & funct7 == 7'b0000001)     ? 6'd27            : // REMU  : Remainder of the corresponding divide (unsigned)
        // 64-bit M-Extension
        (opcode == R32_TYPE & funct3 == 3'b000 & funct7 == 7'b0000001)     ? 6'd28            : // MULW  : Multiply lower 32 bits of the source registers, places sign-extended lower 32 bits of the result in rd
        (opcode == R32_TYPE & funct3 == 3'b100 & funct7 == 7'b0000001)     ? 6'd29            : // DIVW  : Divide lower 32 bits of rs1 by lower 32 bits of rs2, place sign-extended 32 bits of quotient in rd (signed)
        (opcode == R32_TYPE & funct3 == 3'b101 & funct7 == 7'b0000001)     ? 6'd30            : // DIVUW : Divide lower 32 bits of rs1 by lower 32 bits of rs2, place sign-extended 32 bits of quotient in rd (unsigned)
        (opcode == R32_TYPE & funct3 == 3'b110 & funct7 == 7'b0000001)     ? 6'd31            : // REMW  : Remainder of the corresponding divide (signed  )
        (opcode == R32_TYPE & funct3 == 3'b111 & funct7 == 7'b0000001)     ? 6'd32            : // REMUW : Remainder of the corresponding divide (unsigned)
                                                                             6'd0             ; // Use addition by default

    // Used in the ROB for deciding on the type of commit
    wire [2:0] op_type = opcode == STORE  ? OP_STORE
                       : opcode == LOAD   ? OP_LOAD
                       : opcode == AUIPC  ? OP_AUIPC
                       : opcode == JAL    ? OP_JAL
                       : opcode == JALR   ? OP_JALR
                       : opcode == BRANCH ? OP_BRANCH
                       :                    OP_OTHER;

    wire rs1_sel = opcode == AUIPC;
    wire rs2_sel = opcode == I_TYPE
                 | opcode == I32_TYPE
                 | opcode == AUIPC
                 | opcode == LUI
                 | opcode == JALR;  /*| opcode == STORE | opcode == LOAD */

    wire [LANE_INDEX_WIDTH-1:0] lane = opcode == STORE                            ? 1
                                     : opcode == LOAD                             ? 2
                                     : opcode == R_TYPE   && funct7 == 7'b0000001 ? 3 // M-extension
                                     : opcode == R32_TYPE && funct7 == 7'b0000001 ? 3 // M-extension
                                     :                                              0;

    /*
     * Concatenate the outputs into a single signal
     */
    assign decode_instruction_o = {
        rs1,
        rs2,
        extend_imm,
        rd,
        fetch_response_PC_i,
        rs1_sel,
        rs2_sel,
        ALU_operation,
        op_type,
        lane,
        fetch_NLP_BTB_hit_i
    };

    assign decode_valid_o         = fetch_response_valid_i;
    assign fetch_response_ready_o = decode_ready_i;

endmodule
