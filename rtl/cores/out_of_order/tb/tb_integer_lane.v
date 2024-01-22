/** @module : tb_integer_lane
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

module tb_integer_lane;
    parameter ROB_INDEX_WIDTH     = 8;
    parameter REG_DATA_WIDTH      = 32;
    parameter DECODED_INSTR_WIDTH = 8;

    reg clock;
    reg reset;
    wire                          dispatch_ready;
    reg                           dispatch_valid;
    reg [REG_DATA_WIDTH-1:0]      dispatch_1st_reg;
    reg [REG_DATA_WIDTH-1:0]      dispatch_2nd_reg;
    reg [DECODED_INSTR_WIDTH-1:0] dispatch_decoded_instruction;
    reg [ROB_INDEX_WIDTH-1:0]     dispatch_ROB_index;
    reg [REG_DATA_WIDTH-1:0]      dispatch_PC_i;
    reg                           execute_ready;
    wire                          execute_valid;
    wire [ROB_INDEX_WIDTH-1:0]    execute_ROB_index;
    wire [REG_DATA_WIDTH -1:0]    execute_value;
    reg                           flush;


    integer_lane #(
        .XLEN               (REG_DATA_WIDTH     ),
        .ROB_INDEX_WIDTH    (ROB_INDEX_WIDTH    ),
        .DECODED_INSTR_WIDTH(DECODED_INSTR_WIDTH)
    ) DUT (
        .clock                       (clock                       ),
        .reset                       (reset                       ),
        .dispatch_ready              (dispatch_ready              ),
        .dispatch_valid              (dispatch_valid              ),
        .dispatch_1st_reg            (dispatch_1st_reg            ),
        .dispatch_2nd_reg            (dispatch_2nd_reg            ),
        .dispatch_decoded_instruction(dispatch_decoded_instruction),
        .dispatch_ROB_index          (dispatch_ROB_index          ),
        .dispatch_PC_i               (dispatch_PC_i               ),
        .execute_ready               (execute_ready               ),
        .execute_valid               (execute_valid               ),
        .execute_ROB_index           (execute_ROB_index           ),
        .execute_value               (execute_value               ),
        .flush                       (flush                       )
    );


    always #1 clock <= ~clock;


    initial begin
        clock <= 1;
        reset <= 1;

        dispatch_valid               <= 0;
        dispatch_1st_reg             <= 17;
        dispatch_2nd_reg             <= 18;
        dispatch_decoded_instruction <= 0;
        dispatch_PC_i                <= 0;
        execute_ready                <= 0;
        flush                        <= 0;

        #10
        reset <= 0;

        if(dispatch_ready !== 1'b1) begin
            $display("\ntb_address_calculator --> Test Failed!\n\n");
            $stop;
        end

        #10 // dispatch first instruction
        dispatch_valid <= 1;
        #2
        dispatch_valid <= 0;

        #10 // read out the result
        execute_ready <= 1;
        // Leave the ready port on

        #10 // dispatch the second instruction
        dispatch_1st_reg <= 7;
        dispatch_2nd_reg <= 6;
        dispatch_decoded_instruction <= 14; // -
        dispatch_valid <= 1;
        #2
        dispatch_valid <= 0;

        #10 // Keep dispatching and reading out
        dispatch_1st_reg <= 7;
        dispatch_2nd_reg <= 8;
        dispatch_decoded_instruction <= 9; // |
        dispatch_valid <= 1;

        repeat (1) @ (posedge clock);
        $display("\ntb_address_calculator --> Test Passed!\n\n");
        $stop;
    end

    always @ (posedge clock) begin
        if (reset) begin
            dispatch_ROB_index <= 11;
        end
        else begin
            if (dispatch_ready && dispatch_valid) begin
                dispatch_ROB_index <= dispatch_ROB_index + 1;
                $display("Time: %0d, Executing instruction %0d with operands %0d and %0d, to be stored into ROB %0d",
                    $time, dispatch_decoded_instruction, dispatch_1st_reg, dispatch_2nd_reg, dispatch_ROB_index);
            end

            if (execute_ready && execute_valid)
            //if (execute_valid)
                $display("Time: %0d, Reading out result %0d to be stored at ROB %0d", $time, execute_value, execute_ROB_index);
        end
    end

endmodule
