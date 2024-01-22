/** @module : tb_issue_stage
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

module tb_issue_stage;

    parameter XLEN                = 64;
    parameter REG_INDEX_WIDTH     = 5;  // Register index size
    parameter IQ_ADDR_WIDTH       = 4;  // log2(number of slots in the issue queue)
    parameter DECODED_INSTR_WIDTH = 8;  // Size of the decoded instruction
    parameter ROB_INDEX_WIDTH     = 8;  // log2(number of ROB slots)
    parameter EXECUTION_LANES     = 3;  // Number of execution lanes and reservation stations
    parameter LANE_INDEX_WIDTH    = 1;  // Selects between the $EXECUTION_LANES reservation stations
    parameter FULL_DECODE_WIDTH   = 158; // Width of a decoded instruction

    reg clock;
    reg reset;
    // decode port
    reg                                            decode_valid;
    wire                                           decode_ready;
    reg  [FULL_DECODE_WIDTH-1:0]                   decode_data;
    // commit port from ROB
    reg                                            commit_valid;
    reg  [REG_INDEX_WIDTH-1:0]                     commit_dest_reg_index;
    reg  [XLEN           -1:0]                     commit_data;
    reg  [ROB_INDEX_WIDTH-1:0]                     commit_ROB_index;
    // issue port to reservation stations
    reg  [EXECUTION_LANES-1:0]                     issue_RS_demux_ready;
    wire [EXECUTION_LANES-1:0]                     issue_RS_demux_valid;
    wire [EXECUTION_LANES*DECODED_INSTR_WIDTH-1:0] issue_RS_demux_decoded_instruction;
    wire [EXECUTION_LANES*XLEN-1:0]      issue_RS_demux_j_data_or_ROB;
    wire [EXECUTION_LANES-1:0]                     issue_RS_demux_j_is_renamed;
    wire [EXECUTION_LANES*XLEN-1:0]      issue_RS_demux_k_data_or_ROB;
    wire [EXECUTION_LANES-1:0]                     issue_RS_demux_k_is_renamed;

    wire [EXECUTION_LANES*XLEN               -1:0] issue_RS_demux_address;
`ifdef TEST
    wire [EXECUTION_LANES*XLEN               -1:0] issue_RS_demux_PC;
`endif
    // ROB forward request port:
    // When issuing an instruction, if any of the registers are renamed, check if they are ready in the ROB
    wire   [ROB_INDEX_WIDTH                    -1:0] forward_request_ROB_index_1;
    wire                                             forward_request_ROB_valid_1;
    wire   [ROB_INDEX_WIDTH                    -1:0] forward_request_ROB_index_2;
    wire                                             forward_request_ROB_valid_2;
    // Issue to ROB the new destination register
    // When issuing an instruction, the instruction's destination register should get updated with the new ROB
    // Note: issue_ROB_valid should be low when issuing stores
    reg                                              issue_ROB_ready;
    wire                                             issue_ROB_valid;
    wire   [REG_INDEX_WIDTH                    -1:0] issue_ROB_dest_reg_index; // the destination register index ROB should commit to
    wire   [2                                    :0] issue_ROB_op_type;
    wire   [XLEN                               -1:0] issue_ROB_imm;
    wire   [XLEN                               -1:0] issue_ROB_PC;
    reg    [ROB_INDEX_WIDTH                    -1:0] issue_ROB_index;          // the ROB index of the newly renamed destination register
    // Branch prediction update port to ROB
    wire                                             issue_ROB_update_rs1_is_link;    // high if rs1 register is x1 or x5
    wire                                             issue_ROB_update_rd_is_link;     // high if rd register is x1 or x5
    wire                                             issue_ROB_update_rs1_is_rd;      // high if rd register is x1 or x5
    wire                                             issue_ROB_update_BTB_hit;        // high if the instruction now in execute hit BTB when it was in fetch issue
    // Issue to load buffer
    reg                                              issue_LB_ready;
    wire                                             issue_LB_valid;
    wire   [XLEN                               -1:0] issue_LB_PC;
    // Issue to store buffer
    // Since store words don't write back, we shouldn't create an empty slot in the reorder buffer
    reg                                              issue_SB_ready;
    wire                                             issue_SB_valid;
    wire   [XLEN                               -1:0] issue_SB_PC;
    // Flush from the ROB
    reg                                              flush;



    issue_stage #(
        .REG_INDEX_WIDTH    (REG_INDEX_WIDTH    ),
        .XLEN               (XLEN               ),
        .IQ_ADDR_WIDTH      (IQ_ADDR_WIDTH      ),
        .DECODED_INSTR_WIDTH(DECODED_INSTR_WIDTH),
        .ROB_INDEX_WIDTH    (ROB_INDEX_WIDTH    ),
        .EXECUTION_LANES    (EXECUTION_LANES    ),
        .LANE_INDEX_WIDTH   (LANE_INDEX_WIDTH   ),
        .FULL_DECODE_WIDTH  (FULL_DECODE_WIDTH  )
    ) DUT (
        .clock                             (clock                             ),
        .reset                             (reset                             ),
        .decode_valid                      (decode_valid                      ),
        .decode_ready                      (decode_ready                      ),
        .decode_data                       (decode_data                       ),
        .commit_valid                      (commit_valid                      ),
        .commit_dest_reg_index             (commit_dest_reg_index             ),
        .commit_data                       (commit_data                       ),
        .commit_ROB_index                  (commit_ROB_index                  ),
        .issue_RS_demux_ready              (issue_RS_demux_ready              ),
        .issue_RS_demux_valid              (issue_RS_demux_valid              ),
        .issue_RS_demux_decoded_instruction(issue_RS_demux_decoded_instruction),
        .issue_RS_demux_rs1_data_or_ROB    (issue_RS_demux_j_data_or_ROB      ),
        .issue_RS_demux_rs1_is_renamed     (issue_RS_demux_j_is_renamed       ),
        .issue_RS_demux_rs2_data_or_ROB    (issue_RS_demux_k_data_or_ROB      ),
        .issue_RS_demux_rs2_is_renamed     (issue_RS_demux_k_is_renamed       ),
        .issue_RS_demux_address(issue_RS_demux_address),
    `ifdef TEST
        .issue_RS_demux_PC(issue_RS_demux_PC),
    `endif
        // ROB forward request port:
        // When issuing an instruction, if any of the registers are renamed, check if they are ready in the ROB
        .forward_request_ROB_index_1(forward_request_ROB_index_1),
        .forward_request_ROB_valid_1(forward_request_ROB_valid_1),
        .forward_request_ROB_index_2(forward_request_ROB_index_2),
        .forward_request_ROB_valid_2(forward_request_ROB_valid_2),
        // Issue to ROB the new destination register
        // When issuing an instruction, the instruction's destination register should get updated with the new ROB
        // Note: issue_ROB_valid should be low when issuing stores
        .issue_ROB_ready(issue_ROB_ready),
        .issue_ROB_valid(issue_ROB_valid),
        .issue_ROB_dest_reg_index(issue_ROB_dest_reg_index), // the destination register index ROB should commit to
        .issue_ROB_op_type(issue_ROB_op_type),
        .issue_ROB_imm(issue_ROB_imm),
        .issue_ROB_PC(issue_ROB_PC),
        .issue_ROB_index(issue_ROB_index),          // the ROB index of the newly renamed destination register
        // Branch prediction update port to ROB
        .issue_ROB_update_rs1_is_link(issue_ROB_update_rs1_is_link),    // high if rs1 register is x1 or x5
        .issue_ROB_update_rd_is_link(issue_ROB_update_rd_is_link),     // high if rd register is x1 or x5
        .issue_ROB_update_rs1_is_rd(issue_ROB_update_rs1_is_rd),      // high if rd register is x1 or x5
        .issue_ROB_update_BTB_hit(issue_ROB_update_BTB_hit),        // high if the instruction now in execute hit BTB when it was in fetch issue
        // Issue to load buffer
        .issue_LB_ready(issue_LB_ready),
        .issue_LB_valid(issue_LB_valid),
        .issue_LB_PC(issue_LB_PC),
        // Issue to store buffer
        // Since store words don't write back, we shouldn't create an empty slot in the reorder buffer
        .issue_SB_ready(issue_SB_ready),
        .issue_SB_valid(issue_SB_valid),
        .issue_SB_PC(issue_SB_PC),
        // Flush from the ROB
        .flush(flush)

    );


always #1
    clock <= ~clock;

integer i;

initial begin

  for (i=0; i<32; i=i+1) begin
      DUT.regfile.register_file[i][XLEN-1:0] <= i;
  end

  clock <= 0;
  reset <= 0;

  decode_valid          <= 0;
  decode_data           <= 0;
  commit_valid          <= 0;
  commit_dest_reg_index <= 0;
  commit_data           <= 0;
  commit_ROB_index      <= 0;
  issue_RS_demux_ready  <= 0;
  issue_ROB_index       <= 0;
  issue_ROB_ready       <= 0;

  #10
  reset <= 1;

  #10
  reset <= 0;

  repeat (1) @ (posedge clock);
  if(decode_ready             !== 1'b1 |
     issue_ROB_valid          !== 1'b0 |
     issue_LB_valid           !== 1'b0 |
     issue_SB_valid           !== 1'b0 ) begin
    $display("\ntb_issue_stage --> Test Failed!\n\n");
    $stop;
  end

  /*
   * let's put several instructions in the IQ
   */
  #20
  decode_valid <= 1;
  // rs=10, not a value, rt=111, is a value, instruction is 123, dest reg is 01, lane is 1
  decode_data <= {32'd10, 1'b0, 32'd111, 1'b1, 8'd123, 5'd1, 1'b0};
  #2
  decode_data <= {32'd11, 1'b0, 32'd12,  1'b0, 8'd124, 5'd2, 1'b0};
  #2
  decode_data <= {32'd13, 1'b0, 32'd14,  1'b0, 8'd125, 5'd1, 1'b1}; // overwrite destination ROB since dest reg same as in instr. 1
  #2
  decode_valid <= 0;


  /*
   * let's issue 2 instructions
   */
  #20
  issue_RS_demux_ready <= 2'b01;
  issue_ROB_index      <= 101;
  issue_ROB_ready      <= 1'b1;
  #2
  issue_RS_demux_ready <= 2'b00;
  issue_ROB_ready      <= 1'b0;

  #10
  issue_RS_demux_ready <= 2'b01;
  issue_ROB_index      <= 102;
  issue_ROB_ready      <= 1'b1;
  #2
  issue_RS_demux_ready <= 2'b00;
  issue_ROB_ready      <= 1'b0;

  #10
  issue_RS_demux_ready <= 2'b10;
  issue_ROB_ready      <= 1'b0;
  #2
  issue_RS_demux_ready <= 2'b00;
  issue_ROB_ready      <= 1'b0;

  repeat (1) @ (posedge clock);
  $display("\ntb_issue_stage --> Test Passed!\n\n");
  $stop;
end

endmodule
