/** @module : tb_fifo_priority_encoder
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

module tb_fifo_priority_encoder;

    parameter ADDR_WIDTH = 3;
    parameter SLOTS = 1 << ADDR_WIDTH;

    reg  [(1 << ADDR_WIDTH)-1:0] inputs;  // Set of wires we are searching through
    reg  [ADDR_WIDTH-1       :0] head;    // Head pointer, everything after  this up to tail should be searched
    reg  [ADDR_WIDTH-1       :0] tail;    // Tail pointer, everything before this up to head should be searched
    wire                         valid;   // High if found a match
    wire [ADDR_WIDTH-1       :0] index;   // Index of the match

    reg [31:0] CLOSEST_TO = "tail"; //  <─────┐
                                    //        │
    fifo_priority_encoder #(         //        │ These need to match!
        .ADDR_WIDTH(ADDR_WIDTH),    //        │
        .CLOSEST_TO("tail")         //  <─────┘
    ) DUT (
        .inputs(inputs),
        .head  (head  ),
        .tail  (tail  ),
        .valid (valid ),
        .index (index )
    );


    always #2 head <= head + 1;
    always #16 tail <= tail + 1;

    integer i;

    reg test_failed = 0;
    reg found;
    reg [SLOTS-1:0] x;

    initial begin
        head <= 0;
        tail <= 3;
        inputs <= 8'b10101011;

        #100
        if (test_failed) begin
            //$display("\033[0;31m");
            $display("\ntb_fifo_priority_encoder --> Test Failed!\n\n");
            //$display("\033[0m");
        end
        else begin
            //$display("\033[0;32m");
            $display("\ntb_fifo_priority_encoder --> Test Passed!\n\n");
            //$display("\033[0m");
        end

        $stop;
    end

    always #1 begin
        found = 0;
        for (i=0; i<SLOTS; i=i+1) begin
            if (CLOSEST_TO == "head") begin
                x <= head + i;
                if (~found && (inputs & (1 << x) == 1)) begin
                    if (x != index && valid) begin
                        $display("Error:");
                        $display("\tInputs:    %b", inputs);
                        $display("\thead:      %d", head);
                        $display("\ttail:      %d", tail);
                        $display("\tIndex:     %d", index);
                        $display("\tValid:     %d", valid);
                        $display("\tExpected: %0d", x);
                        test_failed <= 1;
                    end
                    found <= 1;
                end
            end else begin
                x <= tail - i - 1;
                if (~found && (inputs & (1 << x) == 1)) begin
                    $display("X: %0d", x);
                    if (x != index && valid) begin
                        $display("Error:");
                        $display("\tInputs:   %b", inputs);
                        $display("\thead:     %d", head);
                        $display("\ttail:     %d", tail);
                        $display("\tIndex:    %d", index);
                        $display("\tValid:    %d", valid);
                        $display("\tExpected: %0d", x);
                        test_failed <= 1;
                    end
                    found <= 1;
                end
            end
        end
    end

endmodule
