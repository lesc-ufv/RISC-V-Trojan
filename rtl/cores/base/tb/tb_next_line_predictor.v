/** @module : tb_next_line_predictor
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

module tb_next_line_predictor();

parameter XLEN=64;
parameter INDEX_WIDTH=5;

reg   clock;
reg   reset;
// Prediction fetch input and target output
reg   [XLEN -1:0] fetch_PC;            // program counter of current instruction in fetch unit
reg               fetch_valid;         // high if valid
wire   [XLEN-1:0] target_PC;           // target of the jump / branch
wire              target_take;         // prediction if the target should be taken
wire              BTB_hit;             // high if valid entry already found in BTB and it is a Jump
// Update port
reg               update_valid;        // high if update is valid
reg   [XLEN -1:0] update_fetch_PC;     // address of the instruction that caused the update
reg   [XLEN -1:0] update_target_PC;    // address of the instruction we're jumping to
reg               update_is_branch;    // high if instruction is a branch
reg               update_branch_taken; // high if branch is taken
reg               update_rs1_is_link;  // high if rs1 register is x1 or x5
reg               update_rd_is_link;   // high if rd register is x1 or x5
reg               update_rs1_is_rd;    // high if rs1 = rd and they are link
reg               update_BTB_hit;      // high if the instruction now in causing the update hit the BTB when it was in fetch issue

next_line_predictor #(
  .XLEN(XLEN),
  .INDEX_WIDTH(INDEX_WIDTH)
) DUT (
  .clock(clock),
  .reset(reset),
  // Prediction fetch input and target output
  .fetch_PC(fetch_PC),            // program counter of current instruction in fetch unit
  .fetch_valid(fetch_valid),         // high if valid
  .target_PC(target_PC),           // target of the jump / branch
  .target_take(target_take),         // prediction if the target should be taken
  .BTB_hit(BTB_hit),             // high if valid entry already found in BTB and it is a Jump
  // Update port
  .update_valid(update_valid),        // high if update is valid
  .update_fetch_PC(update_fetch_PC),     // address of the instruction that caused the update
  .update_target_PC(update_target_PC),    // address of the instruction we're jumping to
  .update_is_branch(update_is_branch),    // high if instruction is a branch
  .update_branch_taken(update_branch_taken), // high if branch is taken
  .update_rs1_is_link(update_rs1_is_link),  // high if rs1 register is x1 or x5
  .update_rd_is_link(update_rd_is_link),   // high if rd register is x1 or x5
  .update_rs1_is_rd(update_rs1_is_rd),    // high if rs1 = rd and they are link
  .update_BTB_hit(update_BTB_hit)       // high if the instruction now in causing the update hit the BTB when it was in fetch issue
);


always #5 clock = ~clock;

initial begin

    clock = 1'b1;
    reset = 1'b1;
    fetch_PC = 0;
    fetch_valid = 1'b0;
    update_valid = 1'b0;
    update_fetch_PC = 0;
    update_target_PC = 0;
    update_is_branch = 1'b0;
    update_branch_taken = 1'b0;
    update_rs1_is_link = 1'b0;
    update_rd_is_link = 1'b0;
    update_rs1_is_rd = 1'b0;
    update_BTB_hit = 1'b0;

  repeat (5) @ (posedge clock);
  reset = 1'b0;

  repeat (1) @ (posedge clock);
  #1
  if(BTB_hit !== 1'b0) begin
    $display("\ntb_next_line_predictor --> Test Failed!\n\n");
    $stop;
  end

  repeat (5) @ (posedge clock);

  $display("\ntb_next_line_predictor --> Test Passed!\n\n");
  $stop;

end

endmodule
