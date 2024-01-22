/** @module : tb_decode_stage64
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

module tb_decode_stage64;

parameter XLEN                = 64;
parameter LANE_INDEX_WIDTH    = 2;   // Selects between the $EXECUTION_LANES reservation stations
parameter FULL_DECODE_WIDTH   = 158; // Width of a decoded instruction

reg                          fetch_response_valid_i;
wire                         fetch_response_ready_o;
wire [31:0]                  fetch_response_instruction_i;
wire [63:0]                  fetch_response_PC_i;
reg                          fetch_NLP_BTB_hit_i;
// Issue stage port
wire                         decode_valid_o;
reg                          decode_ready_i;
wire [FULL_DECODE_WIDTH-1:0] decode_instruction_o;

reg           clock;
reg [31:0]    instructions [0:1023];
reg [31:0]    PC;

decode_stage64 #(
    .XLEN(XLEN),
    .LANE_INDEX_WIDTH(LANE_INDEX_WIDTH),  // Selects between the $EXECUTION_LANES reservation stations
    .FULL_DECODE_WIDTH(FULL_DECODE_WIDTH) // Width of a decoded instruction
) DUT (
    // Instruction fetch port
    .fetch_response_valid_i(fetch_response_valid_i),
    .fetch_response_ready_o(fetch_response_ready_o),
    .fetch_response_instruction_i(fetch_response_instruction_i),
    .fetch_response_PC_i(fetch_response_PC_i),
    .fetch_NLP_BTB_hit_i(fetch_NLP_BTB_hit_i),
    // Issue stage port
    .decode_valid_o(decode_valid_o),
    .decode_ready_i(decode_ready_i),
    .decode_instruction_o(decode_instruction_o)
);

always #5 clock = ~clock;
assign fetch_response_instruction_i = instructions[PC];
assign fetch_response_PC_i = PC;

integer i;

initial begin
  clock = 1'b1;
  //$readmemh("./binaries/hanoi.vmh", instructions);
  instructions[0] = 32'h00000013;
  PC = 0;

  fetch_response_valid_i = 1'b1;
  decode_ready_i = 1'b1;
  fetch_NLP_BTB_hit_i = 1'b0;

  repeat (1) @ (posedge clock);

  if(decode_valid_o    !== 1'b1 |
     DUT.ALU_operation !== 6'd0 ) begin
     $display("%b %b", decode_valid_o, DUT.ALU_operation);
    $display("\ntb_decode_stage64 --> Test Failed!\n\n");
    $stop;
  end


  /*
  // Step through the instructions
  for (i=0; i<100; i=i+1)
      #2 PC = PC + 1;
  */

  repeat (1) @ (posedge clock);
  $display("\ntb_decode_stage64 --> Test Passed!\n\n");
  $stop;
end


endmodule
