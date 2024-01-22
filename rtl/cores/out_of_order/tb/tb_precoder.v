/** @module : tb_precoder
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

module tb_precoder;

    parameter XLEN       = 64;
    parameter INPUT_INST = 4;

   `include "../rtl/cores/out_of_order/functions/log2.v"
   `include "../rtl/cores/out_of_order/functions/decode_function.v"

    reg clock;
    reg reset;
    reg flush;

    reg                         fetch_response_valid;
    wire                        fetch_response_ready;
    reg [16*INPUT_INST    -1:0] fetch_response_data;
    reg [XLEN             -1:0] fetch_response_PC;

    wire                        precoder_valid;
    reg                         precoder_ready;
    wire [32*INPUT_INST   -1:0] precoder_instructions;
    wire [log2(INPUT_INST)  :0] precoder_instruction_count;
    wire [64*INPUT_INST   -1:0] precoder_PCs;

    wire [31:0] instructions [INPUT_INST-1:0];
    wire [159:0] instructions_ascii [INPUT_INST-1:0];
    wire [63:0] PCs [INPUT_INST-1:0];

    genvar i;
    generate
        for (i=0; i<INPUT_INST; i=i+1) begin
            assign instructions[i] = precoder_instructions[32*(i+1)-1-:32];
            assign instructions_ascii[i] = decode(precoder_instructions[32*(i+1)-1-:32]);
            assign PCs[i] = precoder_PCs[i*64+63-:64];
        end
    endgenerate

    precoder #(
        .XLEN                      (XLEN                      ),
        .INPUT_INST                (INPUT_INST                )
    ) DUT (
        .clock                     (clock                     ),
        .reset                     (reset                     ),
        .flush                     (flush                     ),
        .fetch_response_valid      (fetch_response_valid      ),
        .fetch_response_ready      (fetch_response_ready      ),
        .fetch_response_data       (fetch_response_data       ),
        .fetch_response_PC         (fetch_response_PC         ),
        .precoder_valid            (precoder_valid            ),
        .precoder_ready            (precoder_ready            ),
        .precoder_instructions     (precoder_instructions     ),
        .precoder_instruction_count(precoder_instruction_count),
        .precoder_PCs              (precoder_PCs              )
    );


always
    #1 clock = ~clock;

integer idx;

initial begin

  clock                <= 1;
  reset                <= 0;
  flush                <= 0;
  fetch_response_valid <= 0;
  fetch_response_data  <= 0;
  fetch_response_PC    <= 0;
  precoder_ready       <= 1;

  #10 reset <= 1;

  #10
  reset                <= 0;
  fetch_response_valid <= 1;
  fetch_response_PC    <= 100;
  precoder_ready       <= 1;

  repeat (1) @ (posedge clock);

  if(fetch_response_ready !== 1'b1 |
     precoder_valid       !== 1'b0 ) begin
    $display("\ntb_precoder --> Test Failed!\n\n");
    $stop;
  end


  fetch_response_data  <= {
      16'b100_1_10_110_01010_01,                // C.ANDI, rs1/rd=110 (x14), imm=101010
      32'b101010101010_00110_000_11001_0010011, // ADDI, imm = 101010101010, rs1 = 00110, rd = 11001
      16'b010_011_111_01_101_00                 // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
  };

  #2
  fetch_response_PC    <= fetch_response_PC + 8;
  fetch_response_data  <= {
      16'b100_1_10_110_01010_01,                // C.ANDI, rs1/rd=110 (x14), imm=101010
      16'b010_011_111_01_101_00,                // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
      32'b101010101010_00110_000_11001_0010011  // ADDI, imm = 101010101010, rs1 = 00110, rd = 11001
  };

  #2
  fetch_response_PC    <= fetch_response_PC + 8;
  fetch_response_data  <= {
      16'b                 0_000_11001_0010011, // ADDI, BROKEN!
      32'b101010101010_00110_000_11001_0010011, // ADDI, imm = 101010101010, rs1 = 00110, rd = 11001
      16'b010_011_111_01_101_00                 // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
  };

  #2
  fetch_response_PC    <= fetch_response_PC + 8;
  fetch_response_data  <= {
      16'b010_011_111_01_101_00,                // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
      16'b100_1_10_110_01010_01,                // C.ANDI, rs1/rd=110 (x14), imm=101010
      16'b010_011_111_01_101_00,                // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
      16'b101010101010_0011                     // ADDI, second half
  };

  #2
  fetch_response_PC    <= fetch_response_PC + 8;
  fetch_response_data  <= {
      16'b100_1_10_110_01010_01,                // C.ANDI, rs1/rd=110 (x14), imm=101010
      16'b010_011_111_01_101_00,                // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
      16'b100_1_10_110_01010_01,                // C.ANDI, rs1/rd=110 (x14), imm=101010
      16'b010_011_111_01_101_00                 // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
  };

  #2
  fetch_response_PC    <= fetch_response_PC + 8;
  fetch_response_data  <= {
      16'b                 0_000_11001_0010011, // ADDI, BROKEN!
      32'b101010101010_00110_000_11001_0010011, // ADDI, imm = 101010101010, rs1 = 00110, rd = 11001
      16'b010_011_111_01_101_00                 // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
  };

  #2
  fetch_response_PC    <= fetch_response_PC + 8;
  fetch_response_data  <= {
      16'b010_011_111_01_101_00,                // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
      16'b100_1_10_110_01010_01,                // C.ANDI, rs1/rd=110 (x14), imm=101010
      16'b010_011_111_01_101_00,                // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
      16'b101010101010_0011                     // ADDI, second half
  };

  #2
  fetch_response_PC    <= fetch_response_PC + 8;
  fetch_response_data  <= {
      16'b100_1_10_110_01010_01,                // C.ANDI, rs1/rd=110 (x14), imm=101010
      16'b010_011_111_01_101_00,                // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
      16'b100_1_10_110_01010_01,                // C.ANDI, rs1/rd=110 (x14), imm=101010
      16'b010_011_111_01_101_00                 // C.LW, rs1 = 111, rd = 101 (x13), uimm = 10101, note that uimm is all broken up in the spec
  };


  repeat (1) @ (posedge clock);
  $display("\ntb_precoder --> Test Passed!\n\n");
  $stop;
end

endmodule
