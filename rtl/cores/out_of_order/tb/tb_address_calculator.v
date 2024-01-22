/** @module : tb_address_calculator
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

module tb_address_calculator();

parameter XLEN                = 64;
parameter ROB_INDEX_WIDTH     = 8;  // Number of ROB address bits

reg clock;
reg reset;
// Dispatch port: when a slot is occupied and has both Qj and Qk values, sends out the decoded instruction,
// ROB destination, and the operands
wire                               dispatch_ready;
reg                                dispatch_valid;
reg [XLEN               -1:0]      dispatch_1st_reg;
reg [XLEN               -1:0]      dispatch_2nd_reg;
reg [XLEN               -1:0]      dispatch_address;
reg [ROB_INDEX_WIDTH    -1:0]      dispatch_ROB_index;
// ROB port
// Since we assume that the ROB has a slot reserved, execute_ready is always 1
reg                            execute_ready;
wire                           execute_valid;
wire [ROB_INDEX_WIDTH    -1:0] execute_ROB_index;
wire [XLEN               -1:0] execute_value;
wire [XLEN               -1:0] execute_address;
// Flush from the ROB
reg                            flush;

address_calculator #(
 .XLEN(XLEN),
 .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH)
) DUT (
  .clock(clock),
  .reset(reset),
  // Dispatch port: when a slot is occupied and has both Qj and Qk values, sends out the decoded instruction,
  // ROB destination, and the operands
  .dispatch_ready(dispatch_ready),
  .dispatch_valid(dispatch_valid),
  .dispatch_1st_reg(dispatch_1st_reg),
  .dispatch_2nd_reg(dispatch_2nd_reg),
  .dispatch_address(dispatch_address),
  .dispatch_ROB_index(dispatch_ROB_index),
  // ROB port
  // Since we assume that the ROB has a slot reserved, execute_ready is always 1
  .execute_ready(execute_ready),
  .execute_valid(execute_valid),
  .execute_ROB_index(execute_ROB_index),
  .execute_value(execute_value),
  .execute_address(execute_address),
  // Flush from the ROB
  .flush(flush)
);

always #5 clock = ~clock;


initial begin
  clock = 1'b1;
  reset = 1'b1;
  dispatch_valid = 1'b0;
  dispatch_1st_reg = 0;
  dispatch_2nd_reg = 0;
  dispatch_address = 0;
  dispatch_ROB_index = 0;
  execute_ready = 1'b0;
  flush = 1'b0;


  repeat (3) @ (posedge clock);
  reset = 1'b0;

  if(execute_valid !== 1'b0) begin
    $display("\ntb_address_calculator --> Test Failed!\n\n");
    $stop;
  end

  repeat (1) @ (posedge clock);
  $display("\ntb_address_calculator --> Test Passed!\n\n");
  $stop;
end

endmodule
