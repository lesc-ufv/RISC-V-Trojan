/** @module : tb_fetch_receive_ooo
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

module tb_fetch_receive_ooo;

    localparam XLEN=64;
    localparam SLOT_WIDTH=3;

    reg             clock;
    reg             reset;
    // Fetch issue port
    reg             fetch_issue_valid;          // High if FI wants to send out a request to I-cache
    wire            fetch_issue_ready;          // High if FR has slots to accept a new PC
    reg [XLEN-1:0]  fetch_issue_PC;             // PC of the I-cache request
    reg             fetch_issue_NLP_BTB_hit;    // If there was BTB hit in Fetch issue
    // I-cache fetch  receive port
    reg             fetch_response_valid;       // High if I-cache responding
    wire            fetch_response_ready;       // High if FR ready to accept response
    reg [XLEN-1:0]  fetch_response_instruction; // Instruction from I-cache
    reg [XLEN-1:0]  fetch_response_PC;          // PC of the response
    // Decode port
    wire            decode_issue_valid;         // High if has an instruction for decode
    reg             decode_issue_ready;         // High if decode is ready to accept an instruction
    wire [31    :0] decode_issue_instruction;   // Instruction to be decoded
    wire [XLEN-1:0] decode_issue_PC;            // PC of the instruction
    wire            decode_issue_NLP_BTB_hit;   // Send the BTB hit information to Decode
    // Flush port port
    reg flush;                                  // High if FR should disregard all outstanding requests

    reg test_pass;


    fetch_receive_ooo #(
        .XLEN      (XLEN      ),
        .SLOT_WIDTH(SLOT_WIDTH)
    ) DUT (
        .clock                      (clock                      ),
        .reset                      (reset                      ),
        // Fetch issue port
        .fetch_issue_valid          (fetch_issue_valid          ), // High if FI wants to send out a request to I-cache
        .fetch_issue_ready          (fetch_issue_ready          ), // High if FR has slots to accept a new PC
        .fetch_issue_PC             (fetch_issue_PC             ), // PC of the I-cache request
        .fetch_issue_NLP_BTB_hit    (fetch_issue_NLP_BTB_hit    ), // If there was BTB hit in Fetch issue
        // I-cache fetch receive port
        .fetch_response_valid       (fetch_response_valid       ), // High if I-cache responding
        .fetch_response_ready       (fetch_response_ready       ), // High if FR ready to accept response
        .fetch_response_instruction (fetch_response_instruction ), // Instruction from I-cache
        .fetch_response_PC          (fetch_response_PC          ), // PC of the response
        // Decode port
        .decode_issue_valid         (decode_issue_valid         ), // High if has an instruction for decode
        .decode_issue_ready         (decode_issue_ready         ), // High if decode is ready to accept an instruction
        .decode_issue_instruction   (decode_issue_instruction   ), // Instruction to be decoded
        .decode_issue_PC            (decode_issue_PC            ), // PC of the instruction
        .decode_issue_NLP_BTB_hit   (decode_issue_NLP_BTB_hit   ),
        // Flush port port
        .flush                      (flush                      )  // High if FR should disregard all outstanding requests
    );

    always #1 clock = ~clock;

    initial begin
        test_pass = 1;

        clock <= 0;
        reset <= 0;
        flush <= 0;

        fetch_issue_valid <= 0;
        fetch_issue_PC    <= 0;
        fetch_issue_NLP_BTB_hit <= 1'b0;

        fetch_response_valid       <= 0;
        fetch_response_instruction <= 0;
        fetch_response_PC          <= 0;

        decode_issue_ready <= 0;

        #10 reset <= 1;
        #10 reset <= 0;

        // issue some instructions
        #10
        fetch_issue_valid <= 1;
        fetch_issue_PC    <= 7; // Issue PC=7
        #2
        fetch_issue_PC    <= 11; // Issue PC=11
        #2
        fetch_issue_PC    <= 13; // Issue PC=13
        #2
        fetch_issue_valid <= 0;

        // respond to the second one (11)
        #10
        fetch_response_valid       <= 1;
        fetch_response_PC          <= 11;
        fetch_response_instruction <= 1011;
        #2
        fetch_response_valid       <= 0;

        // set decode to ready, confirm nothing gets sent out
        #10
        decode_issue_ready <= 1;
        #1 if (decode_issue_valid) test_pass = 0;
        #3 decode_issue_ready <= 0;

        // respond to the first issue (7)
        #10
        fetch_response_valid       <= 1;
        fetch_response_PC          <= 7;
        fetch_response_instruction <= 1007;
        #2
        fetch_response_valid       <= 0;

        // set decode to ready, confirm two instructions leave
        #10
        decode_issue_ready <= 1;
        #1 if (!decode_issue_valid) test_pass = 0;
        #2 if (!decode_issue_valid) test_pass = 0;
        #2 if ( decode_issue_valid) test_pass = 0;
        #2 decode_issue_ready <= 0;

        // Flush the third instruction
        #10 flush <= 1;
        #2  flush <= 0;

        // Respond to third instruction
        #10
        fetch_response_valid       <= 1;
        fetch_response_PC          <= 13;
        fetch_response_instruction <= 1013;
        #2
        fetch_response_valid       <= 0;

        // Confirm third instruction is not sent out
        #10
        decode_issue_ready <= 1;
           if (decode_issue_valid) test_pass = 0;
        #1 if (decode_issue_valid) test_pass = 0;
        #1 if (decode_issue_valid) test_pass = 0;
        #1 if (decode_issue_valid) test_pass = 0;

        repeat (10) @ (posedge clock);
        if(!test_pass) begin
            $display("\ntb_fetch_receive_ooo --> Test Failed!\n\n");
            $stop;
        end

        // TODO: test overflow / underflow

        repeat (1) @ (posedge clock);
        $display("\ntb_fetch_receive_ooo --> Test Passed!\n\n");
        $stop;
    end

endmodule
