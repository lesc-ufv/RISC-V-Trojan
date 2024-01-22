/** @module : m_extension_lane
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

module tb_m_ext_lane();

parameter XLEN                = 64;
parameter ROB_INDEX_WIDTH     = 8;  // Number of ROB address bits
parameter DECODED_INSTR_WIDTH = 6;  // Size of the decoded instruction

reg clock;
reg reset_i;
// Dispatch port: when a slot is occupied and has both Qj and Qk values, sends out the decoded instruction,
// ROB destination, and the operands
wire                            dispatch_ready_o;
reg                             dispatch_valid_i;
reg [XLEN                -1:0]  dispatch_1st_reg_i;
reg [XLEN                -1:0]  dispatch_2nd_reg_i;
reg [DECODED_INSTR_WIDTH -1:0]  dispatch_decoded_instruction_i;
reg [ROB_INDEX_WIDTH     -1:0]  dispatch_ROB_index_i;
// ROB port
// Since we assume that the ROB has a slot reserved, execute_ready_i is always 1
reg                             execute_ready_i;
wire                            execute_valid_o;
wire  [ROB_INDEX_WIDTH-1:0]     execute_ROB_index_o;
wire  [XLEN           -1:0]     execute_value_o;
// flush_i from the ROB
reg flush_i;


m_ext_lane #(
  .XLEN(XLEN),
  .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
  .DECODED_INSTR_WIDTH(DECODED_INSTR_WIDTH)
) DUT (
  .clock_i(clock),
  .reset_i(reset_i),
  .dispatch_ready_o(dispatch_ready_o),
  .dispatch_valid_i(dispatch_valid_i),
  .dispatch_1st_reg_i(dispatch_1st_reg_i),
  .dispatch_2nd_reg_i(dispatch_2nd_reg_i),
  .dispatch_decoded_instruction_i(dispatch_decoded_instruction_i),
  .dispatch_ROB_index_i(dispatch_ROB_index_i),
  .execute_ready_i(execute_ready_i),
  .execute_valid_o(execute_valid_o),
  .execute_ROB_index_o(execute_ROB_index_o),
  .execute_value_o(execute_value_o),
  .flush_i(flush_i)
);


always #5 clock = ~clock;

initial begin
  clock <= 1'b1;
  reset_i <= 1'b1;
  // Dispatch port: when a slot is occupied and has both Qj and Qk values, sends out the decoded instruction,
  // ROB destination, and the operands
  dispatch_valid_i <= 1'b0;
  dispatch_1st_reg_i <= 0;
  dispatch_2nd_reg_i <= 0;
  dispatch_decoded_instruction_i <= 0;
  dispatch_ROB_index_i <= 0;
  // ROB port
  // Since we assume that the ROB has a slot reserved, execute_ready_i is always 1
  execute_ready_i <= 1'b1;
  // flush_i from the ROB
  flush_i <= 1'b1;

  repeat (1) @ (posedge clock);
  reset_i <= 1'b0;

  repeat (1) @ (posedge clock);

  if(dispatch_ready_o !== 1'b1 |
     execute_valid_o  !== 1'b0 ) begin
     $display("%b $b", dispatch_ready_o, execute_valid_o);
    $display("\ntb_m_ext_lane--> Test Failed!\n\n");
    $stop;
  end

  repeat (1) @ (posedge clock);
  $display("\ntb_m_ext_lane --> Test Passed!\n\n");
  $stop;

end


endmodule
