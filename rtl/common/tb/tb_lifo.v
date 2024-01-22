/** @module : tb_lifo
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

module tb_lifo();

parameter DATA_WIDTH = 32;
parameter LIFO_DEPTH =  4;

reg    clk;
reg    reset;
reg    [DATA_WIDTH-1:0] data_i;
reg    push_i;
reg    pop_i;
reg    read_lifo_i;
wire   empty_o;
wire   full_o;
wire   [DATA_WIDTH-1:0] data_o;

LIFO #(
  .DATA_WIDTH(DATA_WIDTH),
  .LIFO_DEPTH(LIFO_DEPTH)
) DUT (
  .clk(clk),
  .reset(reset),
  .data_i(data_i),
  .push_i(push_i),
  .pop_i(pop_i),
  .read_lifo_i(read_lifo_i),
  .empty_o(empty_o),
  .full_o(full_o),
  .data_o(data_o)
);


always #5 clk = ~clk;


initial begin
  clk   = 1'b1;
  reset = 1'b1;
  data_i = 0;
  push_i = 1'b0;
  pop_i  = 1'b0;
  read_lifo_i = 1'b0;

  repeat (3) @ (posedge clk);
  reset = 1'b0;

  repeat (1) @ (posedge clk);
  #1
  if(empty_o !== 1'b1 |
     full_o  !== 1'b0 ) begin
    $display("\ntb_lifo --> Test Failed!\n\n");
    $stop;

  end



  repeat (1) @ (posedge clk);
  $display("\ntb_lifo --> Test Passed!\n\n");
  $stop;
end

endmodule

