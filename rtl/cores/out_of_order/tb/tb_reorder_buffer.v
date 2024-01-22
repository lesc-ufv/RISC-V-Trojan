/** @module : tb_reorder_buffer
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

module tb_reorder_buffer();

    parameter XLEN            = 32; // Register value size
    parameter ROB_INDEX_WIDTH = 8;  // Number of ROB address bits
    parameter SB_INDEX_WIDTH  = 5;  // Number of SB address bits
    parameter EXECUTION_LANES = 1;  // For testing purposes
    parameter NLP_UPDATE      = 135;// NLP Update signals width

    reg clock;
    reg reset;

    // Issue port
    wire                       issue_ROB_ready; // ROB can accept new instruction
    reg                        issue_ROB_valid; // new instruction present at ROB
    reg  [5              -1:0] issue_ROB_dest_reg_index; // the instruction's destination register
    reg  [2                :0] issue_ROB_op_type; // Type of instruction, one of the OP_* values
    reg  [XLEN           -1:0] issue_ROB_imm; // Immediate of the issued instruction, used for JAL and branches
    reg  [XLEN           -1:0] issue_ROB_PC; // Address of the issued instruction, used for jumps
    wire [ROB_INDEX_WIDTH-1:0] issue_ROB_index; // the ROB assigned to the new instruction; sent to RS and register file

    // Branch prediction update port to ROB
    reg                                            issue_ROB_update_rs1_is_link;// high if rs1 register is x1 or x5
    reg                                            issue_ROB_update_rd_is_link; // high if rd register is x1 or x5
    reg                                            issue_ROB_update_rs1_is_rd;  // high if rd register is x1 or x5
    reg                                            issue_ROB_update_BTB_hit;    // high if the instruction now in execute hit BTB when it was in fetch issue

    // ROB forward port: 2 forward busses to the reservation stations; one per operand
    reg [ROB_INDEX_WIDTH-1:0] forward_request_ROB_index_1; // the instruction's first needed ROB - ROB checks if it has the results for it
    reg [ROB_INDEX_WIDTH-1:0] forward_request_ROB_index_2; // the instruction's second needed ROB
    reg                       forward_request_ROB_valid_1; // the ROB only broadcasts issue_1st_ROB value if the register is renamed
    reg                       forward_request_ROB_valid_2; // the ROB only broadcasts issue_2nd_ROB value if the register is renamed
    //
    // ROB forward response port outputs
    wire [1                  :0] forward_response_valids;     // valid flag of all forward ports
    wire [2*ROB_INDEX_WIDTH-1:0] forward_response_indexes;    // forward port index lines
    wire [2*XLEN           -1:0] forward_response_values;     // forward port register lines

    // Execute unit ports
    wire [(EXECUTION_LANES)               -1:0] execute_unit_readys;  // ready flag of all forward ports
    reg [(EXECUTION_LANES)                -1:0] execute_unit_valids;  // valid flag of all forward ports
    reg [(EXECUTION_LANES)*ROB_INDEX_WIDTH-1:0] execute_unit_indexes; // forward port index lines
    reg [(EXECUTION_LANES)*XLEN           -1:0] execute_unit_values;  // forward port register lines

    // Commit port
    wire                       commit_valid;     // commit message is valid
    wire [5              -1:0] commit_dest_reg;  // commit destination register
    wire [XLEN           -1:0] commit_value;     // value to place in destination register
    wire [ROB_INDEX_WIDTH-1:0] commit_ROB_index; // Index of the ROB head

    // Store buffer commit port
    reg  store_commit_ready;  // Store buffer is ready to commit a store
    wire store_commit_valid;  // Store buffer commit is valid
    reg  store_commit_hazard; // Store commit caused a hazard since a load to the same address was already sent out

    // PC update port
    wire                  fetch_update_valid;
    reg                   fetch_update_ready;
    wire [NLP_UPDATE-1:0] fetch_update_data;

    wire flush;

    reorder_buffer #(
        .XLEN           (XLEN           ),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .SB_INDEX_WIDTH (SB_INDEX_WIDTH ),
        .EXECUTION_LANES(EXECUTION_LANES),
        .NLP_UPDATE(NLP_UPDATE)
    ) DUT (
        .clock                      (clock                      ),
        .reset                      (reset                      ),
        // Issue port
        .issue_ROB_ready            (issue_ROB_ready            ),
        .issue_ROB_valid            (issue_ROB_valid            ),
        .issue_ROB_dest_reg_index   (issue_ROB_dest_reg_index   ),
        .issue_ROB_op_type          (issue_ROB_op_type          ),
        .issue_ROB_imm              (issue_ROB_imm              ),
        .issue_ROB_PC               (issue_ROB_PC               ),
        .issue_ROB_index            (issue_ROB_index            ),
        .issue_ROB_update_rs1_is_link(issue_ROB_update_rs1_is_link),
        .issue_ROB_update_rd_is_link (issue_ROB_update_rd_is_link ),
        .issue_ROB_update_rs1_is_rd (issue_ROB_update_rs1_is_rd ),
        .issue_ROB_update_BTB_hit    (issue_ROB_update_BTB_hit    ),

        // ROB forward request port
        .forward_request_ROB_index_1(forward_request_ROB_index_1),
        .forward_request_ROB_index_2(forward_request_ROB_index_2),
        .forward_request_ROB_valid_1(forward_request_ROB_valid_1),
        .forward_request_ROB_valid_2(forward_request_ROB_valid_2),
        // ROB forward response port
        .forward_response_valids    (forward_response_valids    ),
        .forward_response_indexes   (forward_response_indexes   ),
        .forward_response_values    (forward_response_values    ),
        // Execute unit ports
        .execute_unit_readys        (execute_unit_readys        ),
        .execute_unit_valids        (execute_unit_valids        ),
        .execute_unit_indexes       (execute_unit_indexes       ),
        .execute_unit_values        (execute_unit_values        ),
        // Commit port
        .commit_valid               (commit_valid               ),
        .commit_dest_reg            (commit_dest_reg            ),
        .commit_value               (commit_value               ),
        .commit_ROB_index           (commit_ROB_index           ),
        // Store buffer commit port
        .store_commit_ready         (store_commit_ready         ),
        .store_commit_valid         (store_commit_valid         ),
        .store_commit_hazard        (store_commit_hazard        ),
        // PC update port
        .fetch_update_valid         (fetch_update_valid         ),
        .fetch_update_ready         (fetch_update_ready         ),
        .fetch_update_data          (fetch_update_data          ),
        .flush                      (flush                      )
    );


always #1
    clock <= ~clock;

integer idx;

initial begin
  clock                       <= 0;
  reset                       <= 0;

  issue_ROB_valid             <= 0;
  issue_ROB_dest_reg_index    <= 0;
  issue_ROB_op_type           <= 0;
  issue_ROB_imm               <= 0;
  issue_ROB_PC                <= 0;
  forward_request_ROB_index_1 <= 0;
  forward_request_ROB_index_2 <= 0;
  forward_request_ROB_valid_1 <= 0;
  forward_request_ROB_valid_2 <= 0;
  execute_unit_valids         <= 0;
  execute_unit_indexes        <= 0;
  execute_unit_values         <= 0;
  store_commit_ready          <= 0;
  store_commit_hazard         <= 0;
  fetch_update_ready          <= 0;

  issue_ROB_update_rs1_is_link <= 1'b0;
  issue_ROB_update_rd_is_link  <= 1'b0;
  issue_ROB_update_rs1_is_rd   <= 1'b0;
  issue_ROB_update_BTB_hit     <= 1'b0;

  #10 reset <= 1;
  #10 reset <= 0;

  repeat (1) @ (posedge clock);

  if(issue_ROB_ready         !== 1'b1  |
     forward_response_valids !== 2'b00 |
     execute_unit_readys     !== 1'b1  |
     commit_valid            !== 1'b0  |
     store_commit_valid      !== 1'b0  |
     fetch_update_valid      !== 1'b0  |
     flush                   !== 1'b0  ) begin
    $display("\ntb_reorder_buffer --> Test Failed!\n\n");
    $stop;
  end


  #10 // Let's issue several instructions
  issue_ROB_valid          <= 1;
  issue_ROB_dest_reg_index <= 11;
  issue_ROB_op_type        <= 3'd6; // OP_OTHER
  #2
  issue_ROB_valid          <= 0;

  #10
  issue_ROB_valid          <= 1;
  issue_ROB_dest_reg_index <= 12;
  issue_ROB_op_type        <= 3'd6; // OP_OTHER
  #2
  issue_ROB_valid          <= 0;

  #20
  issue_ROB_valid          <= 1;
  issue_ROB_dest_reg_index <= 13;
  issue_ROB_op_type        <= 3'd6; // OP_OTHER
  #2
  issue_ROB_valid          <= 1;
  issue_ROB_dest_reg_index <= 14;
  issue_ROB_op_type        <= 3'd6; // OP_OTHER
  #2
  issue_ROB_valid          <= 1;
  issue_ROB_dest_reg_index <= 15;
  issue_ROB_op_type        <= 3'd6; // OP_OTHER
  #2
  issue_ROB_valid          <= 0;


  #20 // Let's update all but the first instruction
  execute_unit_valids      <= 1;
  execute_unit_indexes     <= 1;
  execute_unit_values      <= 101;

  #2
  execute_unit_valids      <= 1;
  execute_unit_indexes     <= 2;
  execute_unit_values      <= 102;

  #2
  execute_unit_valids      <= 1;
  execute_unit_indexes     <= 3;
  execute_unit_values      <= 103;

  #2
  execute_unit_valids      <= 1;
  execute_unit_indexes     <= 4;
  execute_unit_values      <= 104;
  #2
  execute_unit_valids      <= 0;


  #10 // let's check if forwarding works
  $display("Cycle %d, Requesting value at ROB 3", $time);
  forward_request_ROB_valid_1 <= 1;
  forward_request_ROB_index_1 <= 3;
  #2
  forward_request_ROB_valid_1 <= 0;

  #6 // let's check if forwarding works
  $display("Cycle %d, Requesting value at ROB 4", $time);
  forward_request_ROB_valid_2 <= 1;
  forward_request_ROB_index_2 <= 4;
  #2
  forward_request_ROB_valid_2 <= 0;


  #20 // Let's test out if committing works
  execute_unit_valids  <= 1;
  execute_unit_indexes <= 0;
  execute_unit_values  <= 100;
  #2
  execute_unit_valids  <= 0;

  repeat (1) @ (posedge clock);
  $display("\ntb_reorder_buffer --> Test Passed!\n\n");
  $stop;
end

always @ (posedge clock) begin

  if (issue_ROB_valid && issue_ROB_ready)
    $display("Cycle %d, Issued new instruction with ROB index %d writing back to ", $time, issue_ROB_index, issue_ROB_dest_reg_index);

  if (execute_unit_valids && execute_unit_readys)
    $display("Cycle %d, Executed instruction with ROB index %d and value %d", $time, execute_unit_indexes, execute_unit_values);

  if (forward_response_valids[0])
    $display("Cycle %d, ROB just forwarded value %d at ROB index %d", $time, forward_response_values[XLEN-1:0], forward_response_indexes[ROB_INDEX_WIDTH-1:0]);

  if (forward_response_valids[1])
    $display("Cycle %d, ROB just forwarded value %d at ROB index %d", $time, forward_response_values[2*XLEN-1 :XLEN], forward_response_indexes[2*ROB_INDEX_WIDTH-1:ROB_INDEX_WIDTH]);

  if (commit_valid)
    $display("Cycle %d, ROB just committed value %d to register", $time, commit_value, commit_dest_reg);
end


endmodule
