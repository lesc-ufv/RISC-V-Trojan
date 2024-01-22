/** @module : tb_register_file
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

module tb_register_file();

    localparam REG_DATA_WIDTH  = 32;
    localparam REG_SEL_BITS    = 5;
    localparam ROB_INDEX_WIDTH = 8;

    reg clock;
    reg reset;
    reg flush;

    // ROB commit port
    reg                        commit_enable;
    reg [REG_SEL_BITS-1:0]     commit_sel;
    reg [REG_DATA_WIDTH-1:0]   commit_data;
    reg [ROB_INDEX_WIDTH-1:0]  commit_ROB_index;

    // ROB update port (used when a new instruction is issued and only a register's ROB id needs to be updated)
    reg                        update_enable;
    reg [REG_SEL_BITS-1:0]     update_dest_reg;
    reg [ROB_INDEX_WIDTH-1:0]  update_ROB_index;

    // First read port: value + ROB id + ROB valid
    reg [REG_SEL_BITS-1:0]     read_sel1;
    wire [REG_DATA_WIDTH-1:0]  read_data1;
    wire [ROB_INDEX_WIDTH-1:0] read_ROB1;
    wire                       read_ROB1_is_renamed;

    // Second read port: value + ROB id + ROB valid
    reg [REG_SEL_BITS-1:0]     read_sel2;
    wire [REG_DATA_WIDTH-1:0]  read_data2;
    wire [ROB_INDEX_WIDTH-1:0] read_ROB2;
    wire                       read_ROB2_is_renamed;

    register_file #(
      .XLEN           (REG_DATA_WIDTH ),
      .REG_INDEX_WIDTH(REG_SEL_BITS   ),
      .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH)
    ) DUT (
        .clock               (clock               ),
        .reset               (reset               ),
        .flush               (flush               ),
        .commit_enable       (commit_enable       ),
        .commit_sel          (commit_sel          ),
        .commit_data         (commit_data         ),
        .commit_ROB_index    (commit_ROB_index    ),
        .update_enable       (update_enable       ),
        .update_dest_reg     (update_dest_reg     ),
        .update_ROB_index    (update_ROB_index    ),
        .read_sel1           (read_sel1           ),
        .read_data1          (read_data1          ),
        .read_ROB1           (read_ROB1           ),
        .read_ROB1_is_renamed(read_ROB1_is_renamed),
        .read_sel2           (read_sel2           ),
        .read_data2          (read_data2          ),
        .read_ROB2           (read_ROB2           ),
        .read_ROB2_is_renamed(read_ROB2_is_renamed)
    );


always #1
    clock = ~clock;

integer idx;

initial begin

  clock <= 0;
  reset <= 0;
  flush <= 0;

  commit_enable    <= 0;
  commit_sel       <= 0;
  commit_data      <= 0;
  commit_ROB_index <= 0;

  update_enable    <= 0;
  update_dest_reg  <= 0;
  update_ROB_index <= 0;

  read_sel1        <= 0;
  read_sel2        <= 0;


  #20 reset <= 1;
  #20 reset <= 0;


  #20  // First let's issue some of the instructions
  update_enable <= 1;
  update_dest_reg <= 1;
  update_ROB_index <= 1;

  #2
  update_enable <= 1;
  update_dest_reg <= 2;
  update_ROB_index <= 4;

  #2
  update_enable <= 1;
  update_dest_reg <= 3;
  update_ROB_index <= 7;

  #2
  update_enable <= 0;

  #10  // First let's now let's commit them
  commit_enable    <= 1;
  commit_sel       <= 1;
  commit_data      <= 15;
  commit_ROB_index <= 5;

  #2

  if(DUT.register_file[1] !== 32'd15) begin
    $display("\ntb_register_file --> Test Failed!\n\n");
    $stop;
  end


  commit_enable    <= 1;
  commit_sel       <= 2;
  commit_data      <= 30;
  commit_ROB_index <= 4; // This should cause the valid to go down

  #2
  commit_enable    <= 1;
  commit_sel       <= 3;
  commit_data      <= 40;
  commit_ROB_index <= 6; // This should cause the valid to go down

  #2 commit_enable <= 0;

  #10 // Now let's test committing and updating the same address
  update_enable    <= 1;
  commit_enable    <= 1;
  commit_sel       <= 3;
  update_dest_reg  <= 3;
  update_ROB_index <= 9;
  commit_data      <= 50;
  commit_ROB_index <= 7;

  #2 update_enable <= 0;
     commit_enable <= 0;

  #10 // Let's test reading
  read_sel1        <= 1;
  read_sel2        <= 2;

  #2
  read_sel1        <= 3;
  read_sel2        <= 4;

  #2
  read_sel1        <= 5;
  read_sel2        <= 6;

  repeat (1) @ (posedge clock);
  $display("\ntb_register_file --> Test Passed!\n\n");
  $stop;
end


endmodule
