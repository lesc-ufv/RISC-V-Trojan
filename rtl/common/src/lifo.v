/** @module : LIFO
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

module LIFO #(
              parameter DATA_WIDTH = 32,
              parameter LIFO_DEPTH =  4
	           )
  (
   input  wire clk,
   input  wire reset,
   input  wire [DATA_WIDTH-1:0] data_i,
   input  wire push_i,
   input  wire pop_i,
   input  wire read_lifo_i,
   output wire empty_o,
   output wire full_o,
   output wire [DATA_WIDTH-1:0] data_o
  );

  //Localparams
  localparam LIFO_BITS = $clog2(LIFO_DEPTH);

  //Intermediate signals
  integer            i;
  wire               empty;
  wire               full;
  reg  [LIFO_BITS:0] lifo_pointer;
  wire [LIFO_BITS:0] next_lifo_pointer;
  reg  [DATA_WIDTH-1:0] lifo_memory [LIFO_DEPTH-1:0];
  wire [DATA_WIDTH-1:0] data;

  //Actual logic code
  always @ (posedge clk) begin
    if (reset) begin
      lifo_pointer                 <= {(LIFO_BITS+1){1'b0}};
    end
    else begin
      lifo_pointer                 <= next_lifo_pointer;
    end
  end

  always @ (posedge clk) begin
    if (push_i)
      lifo_memory [next_lifo_pointer-1]   <= data_i;
  end

  always@(posedge clk) begin
    if (push_i & full) begin
      $display ("ERROR: Trying to push data: %h  on a full LIFO!",  data_i);
      $display ("INFO:  LIFO depth %d",LIFO_DEPTH);
      $display ("INFO:  LIFO Pointer %d", lifo_pointer);
      for (i = 0; i < LIFO_DEPTH; i=i+1) begin
        $display ("INFO: Index [%d] data [%h]",i, lifo_memory[i]);
      end
    end
  end

  always@(posedge clk) begin
    if (pop_i & empty) begin
      $display ("ERROR: Trying to pop data: %h  on a empty LIFO!",  pop_i);
      $display ("INFO:  LIFO depth %d",LIFO_DEPTH);
      $display ("INFO:  LIFO Pointer %d", lifo_pointer);
      for (i = 0; i < LIFO_DEPTH; i=i+1) begin
        $display ("INFO: Index [%d] data [%h]",i, lifo_memory[i]);
      end
    end
  end

  assign next_lifo_pointer = (pop_i & push_i)                                   ? lifo_pointer           :
                             (push_i & (lifo_pointer != (LIFO_DEPTH)))          ? lifo_pointer + 1'b1    :
                             (pop_i  & (lifo_pointer != {(LIFO_BITS+1){1'b0}})) ? lifo_pointer - 1'b1    :
                             (push_i & (lifo_pointer == (LIFO_DEPTH)))          ? {{LIFO_BITS{1'b0}},1'b1} :
                                                                                  lifo_pointer;
  assign data              = read_lifo_i ? lifo_memory [lifo_pointer-1] : {DATA_WIDTH{1'bx}};
  assign full              = (lifo_pointer == LIFO_DEPTH);
  assign empty             = (lifo_pointer == {(LIFO_BITS+1){1'b0}});

  // Output assignments
  assign full_o  = full;
  assign empty_o = empty;
  assign data_o  = data;

endmodule
