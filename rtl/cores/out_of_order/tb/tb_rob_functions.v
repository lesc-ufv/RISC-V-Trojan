/** @module : tb_rob_functions
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

module tb_rob_functions;

    localparam EXECUTION_LANES = 4;
    localparam ROB_INDEX_WIDTH = 4;

    function integer log2;
    input integer value;
    begin
      value = value-1;
      for (log2=0; value>0; log2=log2+1)
        value = value >> 1;
    end
    endfunction

    /*
     * A function that given a number of execute lane indexes of width ROB_INDEX_WIDTH,
     * checks whether any matches the provided index (second argument)
     */
    function automatic execute_lane_match;
        input [EXECUTION_LANES*ROB_INDEX_WIDTH-1:0] execute_unit_indexes; // execute lane indexes
        input [EXECUTION_LANES                -1:0] execute_unit_valids;  // high if lane valid
        input [ROB_INDEX_WIDTH                -1:0] index;           // slot index

        reg valid;
        integer idx;

        begin
            valid = 0;
            for (idx=0; idx<EXECUTION_LANES; idx=idx+1)
                if (execute_unit_valids[idx] && (execute_unit_indexes[ROB_INDEX_WIDTH*(idx+1)-1-:ROB_INDEX_WIDTH] == index))
                    valid = 1;

            execute_lane_match = valid;
        end
    endfunction

    /*
     * A function that given a number of execute lane indexes of width ROB_INDEX_WIDTH, checks whether
     * any matches the provided index (second argument), and returns the index of the last matching lane.
     */
    function automatic [log2(EXECUTION_LANES)-1:0] matching_lane_index;
        input [EXECUTION_LANES*ROB_INDEX_WIDTH-1:0] execute_indexes; // forward port index lines
        input [EXECUTION_LANES                -1:0] execute_valids;  // high if lane valid
        input [ROB_INDEX_WIDTH-1:0] index;

        reg [log2(EXECUTION_LANES)-1:0] matching_lane;
        integer idx;

        begin
            matching_lane = 0;
            for (idx=0; idx<EXECUTION_LANES; idx=idx+1)
                if (execute_valids[idx] && execute_indexes[ROB_INDEX_WIDTH*(idx+1)-1-:ROB_INDEX_WIDTH] == index)
                    matching_lane = idx;

            matching_lane_index = matching_lane;
        end
    endfunction

    reg [EXECUTION_LANES*ROB_INDEX_WIDTH-1:0] execute_unit_indexes; // execute lane indexes
    reg [EXECUTION_LANES                -1:0] execute_unit_valids;  // high if lane valid
    reg [ROB_INDEX_WIDTH                -1:0] index;                // slot index

    initial begin
      if (execute_lane_match({4'b1010, 4'b1111, 4'b0000, 4'b1000}, 4'b1111, 4'b1010) != 1) begin
        $display("Failed 1st assertion");
        $display("\ntb_rob_functions --> Test Failed!\n\n");
      end

      #10
      if (execute_lane_match({4'b1010, 4'b1111, 4'b0000, 4'b1000}, 4'b0111, 4'b1010) == 1) begin
        $display("Failed 2nd assertion");
        $display("\ntb_rob_functions --> Test Failed!\n\n");
      end

      #10
      if (execute_lane_match({4'b1010, 4'b1111, 4'b1010, 4'b1000}, 4'b1111, 4'b1010) != 1) begin
         $display("Failed 1st assertion");
         $display("\ntb_rob_functions --> Test Failed!\n\n");
       end

       #10
      if (execute_lane_match({4'b1010, 4'b1111, 4'b1010, 4'b1000}, 4'b0111, 4'b1010) != 1) begin
         $display("Failed 2nd assertion");
         $display("\ntb_rob_functions --> Test Failed!\n\n");
       end

       #10

       if (matching_lane_index({4'b1010, 4'b1111, 4'b0000, 4'b1000}, 4'b1111, 4'b1010) != 3) begin
         $display("Failed 3rd assertion");
         $display("\ntb_rob_functions --> Test Failed!\n\n");
       end

       #10
       if (matching_lane_index({4'b1000, 4'b1010, 4'b0000, 4'b1000}, 4'b1111, 4'b1010) != 2) begin
         $display("Failed 4th assertion");
         $display("\ntb_rob_functions --> Test Failed!\n\n");
       end

       #10
       if (matching_lane_index({4'b0010, 4'b1111, 4'b1010, 4'b1000}, 4'b1111, 4'b1010) != 1) begin
         $display("Failed 4th assertion");
         $display("\ntb_rob_functions --> Test Failed!\n\n");
       end

       #10
       if (matching_lane_index({4'b0010, 4'b1111, 4'b1000, 4'b1010}, 4'b1111, 4'b1010) != 0) begin
         $display("Failed 5th assertion");
         $display("\ntb_rob_functions --> Test Failed!\n\n");
       end

       #10
       if (matching_lane_index({4'b0010, 4'b1111, 4'b1010, 4'b1010}, 4'b1111, 4'b1010) != 1) begin
         $display("Failed 6th assertion");
         $display("\ntb_rob_functions --> Test Failed!\n\n");
       end

       #10
       if (matching_lane_index({4'b1010, 4'b1010, 4'b1010, 4'b1010}, 4'b1111, 4'b1010) != 3) begin
         $display("Failed 7th assertion");
         $display("\ntb_rob_functions --> Test Failed!\n\n");
       end

       #10
       $display("\ntb_rob_functions --> Test Passed!\n\n");
       $stop;
    end

endmodule
