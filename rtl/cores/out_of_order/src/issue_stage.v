/** @module : issue_stage
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

// The issue stage recieves instructions one-by-one from the decode stage, and
// stores them in a FIFO. As reservation stations become free, it feeds instructions
// from the top of the FIFO into them, and tags them with the ROB assigned to hold
// the destination register.

module issue_stage #(
    parameter XLEN                = 64,
    parameter REG_INDEX_WIDTH     = 5,  // Register index size
    parameter IQ_ADDR_WIDTH       = 4,  // log2(number of slots in the issue queue)
    parameter DECODED_INSTR_WIDTH = 8,  // Size of the decoded instruction
    parameter ROB_INDEX_WIDTH     = 8,  // log2(number of ROB slots)
    parameter EXECUTION_LANES     = 3,  // Number of execution lanes and reservation stations
    parameter LANE_INDEX_WIDTH    = 1,  // Selects between the $EXECUTION_LANES reservation stations
    parameter FULL_DECODE_WIDTH   = 158 // Width of a decoded instruction
) (
    input                                            clock,
    input                                            reset,
    // Decode unit port
    input                                            decode_valid,
    output                                           decode_ready,
    input [FULL_DECODE_WIDTH                   -1:0] decode_data,
    // ROB commit port
    // The value of head of ROB is written to the destination index at ROB head, and ROB index is removed if matching
    input                                            commit_valid,
    input [REG_INDEX_WIDTH                     -1:0] commit_dest_reg_index,
    input [XLEN                                -1:0] commit_data,
    input [ROB_INDEX_WIDTH                     -1:0] commit_ROB_index,
    // Issue ports to reservation stations (RS)
    // Note: there are $EXECUTION_LANES RS's, so we mux/demux a single port w.r.t. to the instructions lane index.
    // The lane index is a value set in the decode stage and specifies which lane should the instruction take.
    input  [EXECUTION_LANES                    -1:0] issue_RS_demux_ready,     // the concatenated ready signals from all RS stations
    output [EXECUTION_LANES                    -1:0] issue_RS_demux_valid,
    output [EXECUTION_LANES*DECODED_INSTR_WIDTH-1:0] issue_RS_demux_decoded_instruction,
    output [EXECUTION_LANES*XLEN               -1:0] issue_RS_demux_rs1_data_or_ROB,
    output [EXECUTION_LANES                    -1:0] issue_RS_demux_rs1_is_renamed,
    output [EXECUTION_LANES*XLEN               -1:0] issue_RS_demux_rs2_data_or_ROB,
    output [EXECUTION_LANES                    -1:0] issue_RS_demux_rs2_is_renamed,
    output [EXECUTION_LANES*XLEN               -1:0] issue_RS_demux_address,
`ifdef TEST
    output [EXECUTION_LANES*XLEN               -1:0] issue_RS_demux_PC,
`endif
    // ROB forward request port:
    // When issuing an instruction, if any of the registers are renamed, check if they are ready in the ROB
    output [ROB_INDEX_WIDTH                    -1:0] forward_request_ROB_index_1,
    output                                           forward_request_ROB_valid_1,
    output [ROB_INDEX_WIDTH                    -1:0] forward_request_ROB_index_2,
    output                                           forward_request_ROB_valid_2,
    // Issue to ROB the new destination register
    // When issuing an instruction, the instruction's destination register should get updated with the new ROB
    // Note: issue_ROB_valid should be low when issuing stores
    input                                            issue_ROB_ready,
    output                                           issue_ROB_valid,
    output [REG_INDEX_WIDTH                    -1:0] issue_ROB_dest_reg_index, // the destination register index ROB should commit to
    output [2                                    :0] issue_ROB_op_type,
    output [XLEN                               -1:0] issue_ROB_imm,
    output [XLEN                               -1:0] issue_ROB_PC,
    input  [ROB_INDEX_WIDTH                    -1:0] issue_ROB_index,          // the ROB index of the newly renamed destination register
    // Branch prediction update port to ROB
    output                                           issue_ROB_update_rs1_is_link,    // high if rs1 register is x1 or x5
    output                                           issue_ROB_update_rd_is_link,     // high if rd register is x1 or x5
    output                                           issue_ROB_update_rs1_is_rd,      // high if rd register is x1 or x5
    output                                           issue_ROB_update_BTB_hit,        // high if the instruction now in execute hit BTB when it was in fetch issue
    // Issue to load buffer
    input                                            issue_LB_ready,
    output                                           issue_LB_valid,
    output [XLEN                               -1:0] issue_LB_PC,
    // Issue to store buffer
    // Since store words don't write back, we shouldn't create an empty slot in the reorder buffer
    input                                            issue_SB_ready,
    output                                           issue_SB_valid,
    output [XLEN                               -1:0] issue_SB_PC,
    // Flush from the ROB
    input                                            flush
);

    localparam [2:0] OP_STORE  = 3'd0,
                     OP_LOAD   = 3'd1,
                     OP_AUIPC  = 3'd2,
                     OP_JAL    = 3'd3,
                     OP_JALR   = 3'd4,
                     OP_BRANCH = 3'd5,
                     OP_OTHER  = 3'd6;
    /*
     * Issue FIFO
     */
    wire IQ_full, IQ_empty;
    wire [FULL_DECODE_WIDTH-1:0] IQ_top;

    /*
     * Deconcatenate the IQ's top instruction
     */
    wire [4:0] IQ_top_rs1, IQ_top_rs2, IQ_top_rd;
    wire [XLEN-1:0] IQ_top_imm, IQ_top_PC;
    wire [DECODED_INSTR_WIDTH-1:0] IQ_top_ALU_op;
    wire IQ_top_rs1_sel, IQ_top_rs2_sel;
    wire [2:0] IQ_top_op_type;
    wire [LANE_INDEX_WIDTH-1:0] IQ_top_lane_idx;
    wire IQ_top_NLP_BTB_hit;

    /*
     * Circuit for sending out to reservation stations
     * Note: instead of exposing multiple lanes of the same type (e.g., multiple FP units) here,
     * one RS should serve all of them and just have multiple dispatch ports.
     * Note: the only reason why this is here and not at the bottom is so that these wires are defined
     * before the FIFO and register file where issue is used.
     */
    wire RS_ready    = issue_RS_demux_ready[IQ_top_lane_idx];
    wire issue       = RS_ready && ~IQ_empty && issue_ROB_ready &&
                       ((IQ_top_op_type != OP_STORE && IQ_top_op_type != OP_LOAD ) || // issue if both the appropriate RS, and the
                        (issue_SB_ready             && IQ_top_op_type == OP_STORE) || // appropriate buffer (ROB or SB) is ready
                        (issue_LB_ready             && IQ_top_op_type == OP_LOAD));   // or both the ROB and LB are ready
    wire writes_back = IQ_top_op_type != OP_STORE && IQ_top_op_type != OP_BRANCH;


    // TODO: this is a hacky way of preventing the in-flight instruction from avoiding a flush
    // We should have an request-response queue reordering instructions, which can be used for when
    // instruction memory is not guaranteed to return instructions in-order.
    reg flush_last_cycle;

    always @(posedge clock)
        flush_last_cycle <= flush;

    vr_fifo #(
        .DATA_WIDTH  (FULL_DECODE_WIDTH),
        .Q_DEPTH_BITS(IQ_ADDR_WIDTH      ),
        .Q_IN_BUFFERS(2                  ) // TODO: check?
    ) ISSUE_QUEUE (
        .clk       (clock                                            ),
        .reset     (reset || flush                                   ),
        .write_data(decode_data                                      ),
        .wrtEn     (decode_valid && decode_ready && ~flush_last_cycle),
        .rdEn      (issue                                            ),
        .peek      (1'b1                                             ),
        .read_data (IQ_top                                           ),
        .valid     (                                                 ), // Ignore, since we always peek and get the neccessary info from .empty
        .full      (IQ_full                                          ),
        .empty     (IQ_empty                                         )
    );

    assign decode_ready = ~IQ_full;

    /*
     * Deconcatenate the IQ's top instruction
     */
    assign {IQ_top_rs1,
            IQ_top_rs2,
            IQ_top_imm,
            IQ_top_rd,
            IQ_top_PC,
            IQ_top_rs1_sel,
            IQ_top_rs2_sel,
            IQ_top_ALU_op,
            IQ_top_op_type,
            IQ_top_lane_idx,
            IQ_top_NLP_BTB_hit} = IQ_top;

    /*
     * Register file and commit port
     */
    wire [XLEN-1:0] regfile_data_1, regfile_data_2;
    wire [ROB_INDEX_WIDTH-1:0] regfile_ROB_idx_1, regfile_ROB_idx_2;
    wire regfile_is_renamed_1, regfile_is_renamed_2;

    register_file #(
        .XLEN           (XLEN           ),
        .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH)
    ) regfile (
        .clock               (clock                ),
        .reset               (reset                ),
        .flush               (flush                ),
        // ROB commit port
        .commit_enable       (commit_valid         ),
        .commit_sel          (commit_dest_reg_index),
        .commit_data         (commit_data          ),
        .commit_ROB_index    (commit_ROB_index     ),
        // ROB update port (used when a new instruction is issued and only a register's ROB id needs to be updated)
        .update_enable       (issue && writes_back ),
        .update_dest_reg     (IQ_top_rd            ),
        .update_ROB_index    (issue_ROB_index      ),
        // First read port: value + ROB id + ROB valid
        .read_sel1           (IQ_top_rs1           ),
        .read_data1          (regfile_data_1       ),
        .read_ROB1           (regfile_ROB_idx_1    ),
        .read_ROB1_is_renamed(regfile_is_renamed_1 ),
        // Second read port: value + ROB id + ROB valid
        .read_sel2           (IQ_top_rs2           ),
        .read_data2          (regfile_data_2       ),
        .read_ROB2           (regfile_ROB_idx_2    ),
        .read_ROB2_is_renamed(regfile_is_renamed_2 )
    );

    /*
     * Mux between Rs1, PC, and ROB index
     */
    wire [XLEN-1:0] Vj_or_Qj, Vk_or_Qk;
    wire rs1_is_renamed, rs2_is_renamed;

    assign Vj_or_Qj = IQ_top_rs1_sel       ? IQ_top_PC :
                      regfile_is_renamed_1 ? {{(XLEN-ROB_INDEX_WIDTH){1'b0}}, regfile_ROB_idx_1} :
                      regfile_data_1;

    /*
     * Mux rs1_is_renamed signal to set value to 0 if data/PC is stored in
     * Vj_or_Qj
     */
    assign rs1_is_renamed = IQ_top_rs1_sel ? 1'b0 : regfile_is_renamed_1;

    /*
     * Mux between Rs2, immediate, and ROB index
     */
    assign Vk_or_Qk = IQ_top_rs2_sel ? IQ_top_imm :
                      regfile_is_renamed_2 ? {{(XLEN-ROB_INDEX_WIDTH){1'b0}}, regfile_ROB_idx_2} :
                      regfile_data_2;

    /*
     * Mux rs2_is_renamed signal to set value to 0 if data/imm is stored in
     * Vj_or_Qj
     */
    assign rs2_is_renamed = IQ_top_rs2_sel ? 1'b0 : regfile_is_renamed_2;


    /*
     * Issue port to reservation stations.
     */
    genvar lane;
    generate
        for (lane=0; lane<EXECUTION_LANES; lane=lane+1) begin: ISSUE_PORT_LANE
            assign issue_RS_demux_valid[lane] = (lane == IQ_top_lane_idx) ? issue : 1'b0;
            assign issue_RS_demux_decoded_instruction[(lane+1)*DECODED_INSTR_WIDTH-1:lane*DECODED_INSTR_WIDTH] = IQ_top_ALU_op;
            assign issue_RS_demux_rs1_data_or_ROB    [(lane+1)*XLEN-1:lane*XLEN]                               = Vj_or_Qj;
            assign issue_RS_demux_rs1_is_renamed     [lane]                                                    = rs1_is_renamed;
            assign issue_RS_demux_rs2_data_or_ROB    [(lane+1)*XLEN-1:lane*XLEN]                               = Vk_or_Qk;
            assign issue_RS_demux_rs2_is_renamed     [lane]                                                    = rs2_is_renamed;
            assign issue_RS_demux_address            [(lane+1)*XLEN-1:lane*XLEN]                               = IQ_top_imm;
`ifdef TEST
            assign issue_RS_demux_PC                 [(lane+1)*XLEN-1:lane*XLEN]                               = IQ_top_PC;
`endif
        end
    endgenerate


    /*
     * ROB forward request port
     */
    assign forward_request_ROB_index_1 = regfile_ROB_idx_1;
    assign forward_request_ROB_index_2 = regfile_ROB_idx_2;
    assign forward_request_ROB_valid_1 = issue && regfile_is_renamed_1 && ~IQ_top_rs1_sel;
    assign forward_request_ROB_valid_2 = issue && regfile_is_renamed_2 && ~IQ_top_rs2_sel;

    /*
     * Issue port to ROB
     */
    assign issue_ROB_valid               = issue;
    assign issue_ROB_dest_reg_index      = IQ_top_rd;
    assign issue_ROB_op_type             = IQ_top_op_type;
    assign issue_ROB_imm                 = IQ_top_imm;
    assign issue_ROB_PC                  = IQ_top_PC;

    assign issue_ROB_update_rs1_is_link  = (IQ_top_op_type == OP_JALR) & ((IQ_top_rs1 == 5'd1) | (IQ_top_rs1 == 5'd5));  // high if rs1 register is x1 or x5
    assign issue_ROB_update_rd_is_link   = (((IQ_top_op_type == OP_JALR) | (IQ_top_op_type == OP_JAL)) & ((IQ_top_rd == 5'd1) | (IQ_top_rd == 5'd5)));    // high if rd  register is x1 or x5
    assign issue_ROB_update_rs1_is_rd    = (IQ_top_op_type == OP_JALR) & (IQ_top_rs1 == IQ_top_rd) & issue_ROB_update_rs1_is_link; // high if rs1 = rd and they are link
    assign issue_ROB_update_BTB_hit      = IQ_top_NLP_BTB_hit;
    /*
     * Issue port to store buffer
     */
    assign issue_SB_valid           = issue && IQ_top_op_type == OP_STORE;
    assign issue_SB_PC              = IQ_top_PC;

    /*
     * Issue port to load buffer
     */
    assign issue_LB_valid           = issue && IQ_top_op_type == OP_LOAD;
    assign issue_LB_PC              = IQ_top_PC;

endmodule
