/** @module : fetch_issue_ooo
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

module fetch_issue_ooo #(
    parameter XLEN       = 64,
    parameter NLP_UPDATE = 71
) (
    input clock,
    input reset,
    // Fetch request port
    input                  fetch_request_ready,
    output                 fetch_request_valid,
    output [XLEN-1:0]      fetch_request_PC,
    // Fetch request to fetch receive port
    output                 fetch_issue_valid,        // High if FI wants to send out a request to I-cache
    input                  fetch_issue_ready,        // High if FR has slots to accept a new PC
    output [XLEN-1:0]      fetch_issue_PC,           // PC of the I-cache request
    output                 fetch_issue_NLP_BTB_hit,  // high if valid entry already found in BTB
    // PC update port
    input                  fetch_update_valid,
    output                 fetch_update_ready,
    input [NLP_UPDATE-1:0] fetch_update_data
);

    reg  [XLEN-1:0] PC;
    wire [XLEN-1:0] PC_plus_4 = PC + 4;

    wire [XLEN-1:0] NLP_target_PC;
    wire            NLP_target_take;
    wire            fetch_next_PC;
    wire [XLEN-1:0] fetch_update_PC;
    wire [XLEN-1:0] next_PC;
    wire            update_valid_control;  // high if update is valid
    wire [XLEN-1:0] update_instruction_PC; // address of the instruction that caused the update
    wire [XLEN-1:0] update_target_PC;      // Target PC of the branch/jump instruction
    wire            update_is_branch;      // high if instruction is a branch
    wire            update_branch_taken;   // high if branch is taken
    wire            update_rs1_is_link;    // high if rs1 register is x1 or x5
    wire            update_rd_is_link;     // high if rd register is x1 or x5
    wire            update_rs1_is_rd;      // high if rs1 = rd and they are link
    wire            update_BTB_hit;        // high if the instruction already hit the BTB

    assign {update_valid_control,  // high if update is valid
            update_instruction_PC, // address of the instruction that caused the update
            update_target_PC,      // Target PC of the branch/jump instruction
            update_is_branch,      // high if instruction is a branch
            update_branch_taken,   // high if branch is taken
            update_BTB_hit,
            update_rs1_is_rd,      // high if rs1 = rd and they are link
            update_rd_is_link,     // high if rd register is x1 or x5
            update_rs1_is_link} = fetch_update_data;   // high if rs1 register is x1 or x5


  next_line_predictor #(
      .XLEN       (XLEN),
      .INDEX_WIDTH(5 )
  ) NLP (
      .clock                (clock                  ),
      .reset                (reset                  ),
      // Prediction port
      .fetch_PC             (fetch_issue_PC         ), // PC of the instruction causing a PC change
      .fetch_valid          (fetch_issue_valid      ), // TODO: should this always be high?
      .target_PC            (NLP_target_PC          ), // target of the jump / branch
      .target_take          (NLP_target_take        ), // prediction if the target should be taken
      .BTB_hit              (fetch_issue_NLP_BTB_hit), // high if valid entry already found in BTB
      // Update port
      .update_valid         (update_valid_control   ), // high if update is valid
      .update_fetch_PC      (update_instruction_PC  ), // address of the instruction that caused the update
      .update_target_PC     (update_target_PC       ), // address of the instruction we're jumping to
      .update_is_branch     (update_is_branch       ), // high if instruction is a branch
      .update_branch_taken  (update_branch_taken    ), // high if branch is taken
      .update_rs1_is_link   (update_rs1_is_link     ), // high if rs1 register is x1 or x5
      .update_rd_is_link    (update_rd_is_link      ), // high if rd register is x1 or x5
      .update_rs1_is_rd     (update_rs1_is_rd       ), // high if rs1 = rd and they are link
      .update_BTB_hit       (update_BTB_hit         )  // high if update has previously hit BTB
  );


  assign fetch_next_PC   = (fetch_request_valid & fetch_request_ready & fetch_issue_valid & fetch_issue_ready);
  assign fetch_update_PC = update_valid_control & update_is_branch ? (update_branch_taken ? update_target_PC : update_instruction_PC + 3'd4) : update_target_PC;

  assign next_PC = (fetch_update_valid & fetch_update_ready)  ? fetch_update_PC :
                   (fetch_next_PC & ~NLP_target_take)         ? PC_plus_4       :
                   (fetch_next_PC &  NLP_target_take)         ? NLP_target_PC   :
                                                                PC;

  always @ (posedge clock) begin
      if (reset) begin
          PC <= 0;
      end else begin
          PC <= next_PC;
      end
  end

  /*
   * Output signals
   */
  wire issue = ~reset && fetch_request_ready && fetch_issue_ready;
  assign fetch_request_valid = issue;
  assign fetch_request_PC    = PC;

  assign fetch_issue_valid   = issue;
  assign fetch_issue_PC      = PC;

  assign fetch_update_ready  = ~reset;

endmodule
