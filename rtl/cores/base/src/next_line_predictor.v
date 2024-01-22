/** @module : next_line_predictor
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

//
// The next line predictor predicts whether branches are taken, and the target
// of branches and jumps.
//
module next_line_predictor #(
    parameter XLEN=64,
    parameter INDEX_WIDTH=5
) (
    input clock,
    input reset,
    // Prediction fetch input and target output
    input [XLEN -1:0] fetch_PC,            // program counter of current instruction in fetch unit
    input             fetch_valid,         // high if valid
    output [XLEN-1:0] target_PC,           // target of the jump / branch
    output            target_take,         // prediction if the target should be taken
    output            BTB_hit,             // high if valid entry already found in BTB and it is a Jump
    // Update port
    input             update_valid,        // high if update is valid
    input [XLEN -1:0] update_fetch_PC,     // address of the instruction that caused the update
    input [XLEN -1:0] update_target_PC,    // address of the instruction we're jumping to
    input             update_is_branch,    // high if instruction is a branch
    input             update_branch_taken, // high if branch is taken
    input             update_rs1_is_link,  // high if rs1 register is x1 or x5
    input             update_rd_is_link,   // high if rd register is x1 or x5
    input             update_rs1_is_rd,    // high if rs1 = rd and they are link
    input             update_BTB_hit       // high if the instruction now in causing the update hit the BTB when it was in fetch issue
);

    localparam TAG_WIDTH = XLEN - INDEX_WIDTH - 2;

    //
    // RAS signal declarations, logic, and LIFO Module
    //

    wire            BTB_hit_jump;
    wire            update_is_push_ras;
    wire            update_is_pop_ras;
    wire [XLEN-1:0] ras_lifo_data_i;
    wire            ras_lifo_push;
    wire            ras_lifo_pop;
    wire            ras_lifo_read;
    wire            ras_lifo_empty;
    wire            ras_lifo_full;
    wire [XLEN-1:0] ras_lifo_data_o;
    wire [XLEN-1:0] target_PC_temp;

    //
    // Branch target buffer: a 2R1W direct-mapped cache with the following fields:
    //
    //     PC tag: fetch_PC[XLEN-1:INDEX_WIDTH+2]                          []
    //     valid: 1b to specify if entry is valid                          [XLEN+5]
    //     target_is_jump[2:0]:
    //           high if instruction is a JAL or JALR                      [XLEN+4]
    //           push high if we need to push from RAS (Only for JAL/(R))  [XLEN+3]
    //           pop  high if we need to pop  from RAS (Only for JALR)     [XLEN+2]
    //     hist: 2-bit histersis used when the instruction is a branch     [XLEN+1:XLEN]
    //     target: XLEN-long target PC                                     [XLEN-1:0]
    //

    localparam BTB_WIDTH = TAG_WIDTH + 1 + 3 + 2 + XLEN;
    reg [BTB_WIDTH-1:0] BTB [0:(1<<INDEX_WIDTH)-1];

    //
    // Prediction port
    // Predictions must be made in the same cycle
    //

    wire [INDEX_WIDTH-1:0] fetch_index;
    wire [TAG_WIDTH  -1:0] fetch_tag;
    wire [TAG_WIDTH  -1:0] target_tag;
    wire target_valid;
    wire [2:0] target_is_jump;
    wire [1:0] target_hist;

    assign  fetch_index = fetch_PC[INDEX_WIDTH+2-1:2] ^ fetch_PC[(2+2*INDEX_WIDTH)-1:2+INDEX_WIDTH];
    assign  fetch_tag   = fetch_PC[XLEN-1:XLEN-TAG_WIDTH];

    assign {target_tag, target_valid, target_is_jump, target_hist, target_PC_temp} = BTB[fetch_index];
    assign target_PC              = ras_lifo_read & ~ras_lifo_empty ? ras_lifo_data_o : target_PC_temp;
    assign target_take            = ras_lifo_read & ~ras_lifo_empty ? 1'b1 :
                                                                     target_valid &&
                                                                     (fetch_tag == target_tag) &&
                                                                     (target_is_jump[2] || target_hist >= 2);

    //
    // Update port
    // Right now, commit stage branches and jumps can update the BTB
    //
    integer i;
    wire [INDEX_WIDTH-1:0] update_index;
    wire [TAG_WIDTH-1:0] update_tag;

    assign update_index = update_fetch_PC[INDEX_WIDTH+2-1:2] ^ update_fetch_PC[(2+2*INDEX_WIDTH)-1:2+INDEX_WIDTH];
    assign update_tag   = update_fetch_PC[XLEN-1:XLEN-TAG_WIDTH];

    // Hysteresis 2-bit saturating counter
    wire [1:0] hysteresis = BTB[update_index][XLEN+1:XLEN];
    wire [1:0] new_hysteresis = update_branch_taken
        ? hysteresis == 2'b11 ? 2'b11 : hysteresis + 1
        : hysteresis == 2'b00 ? 2'b00 : hysteresis - 1;

    always @ (posedge clock) begin
        if (reset) begin
            for (i=0; i<(1<<INDEX_WIDTH); i=i+1) begin
                BTB[i] <=
                    {{XLEN-INDEX_WIDTH{1'b0}}, // top XLEN-INDEX_WIDTH instruction address bits
                    1'b0,                      // new updates are always valid
                    3'b0,                      // high if a jump, push, pop
                    2'b10,                     // 2-bit saturating counter
                    {XLEN{1'b0}}};             // target PC
            end
        end else if (update_valid) begin
            BTB[update_index] <=
                {update_tag,    // top XLEN-INDEX_WIDTH instruction address bits
                1'b1,              // new updates are always valid
                {~update_is_branch, update_is_push_ras, update_is_pop_ras}, // high if a jump
                new_hysteresis,    // 2-bit saturating counter
                update_target_PC}; // target PC
        end
    end

    assign BTB_hit_jump       = target_valid & (target_tag == fetch_PC[XLEN-1:INDEX_WIDTH+2]) & target_is_jump[2];
    assign update_is_push_ras = update_rd_is_link;
    assign update_is_pop_ras  = (~update_rs1_is_rd & update_rs1_is_link);
    assign ras_lifo_push      = update_is_push_ras;
    assign ras_lifo_pop       = update_is_pop_ras;
    assign ras_lifo_read      = BTB_hit_jump ? target_is_jump[0] : update_BTB_hit ? 0 : update_is_pop_ras;
    assign ras_lifo_data_i    = update_fetch_PC+4;

   LIFO #(
          .DATA_WIDTH(XLEN),
          .LIFO_DEPTH(64)
	 ) RAS_Lifo (
      .clk(clock),
      .reset(reset),
      .data_i(ras_lifo_data_i),
      .push_i(ras_lifo_push),
      .pop_i(ras_lifo_pop),
      .read_lifo_i(ras_lifo_read),
      .empty_o(ras_lifo_empty),
      .full_o(ras_lifo_full),
      .data_o(ras_lifo_data_o)
    );

    // RAS push and pop logic:
    //     if already saw PC before, push/pop as BTB says
    //     if just figuring out we should've pushed/popped, push or pop late,
    //     in order to keep pushes&pops in sync.
    //
    // TODO: what happens when we have an update that wants to push, and a BTB that wants to push at the same time??
    //
    //

    assign BTB_hit = BTB_hit_jump;

endmodule
