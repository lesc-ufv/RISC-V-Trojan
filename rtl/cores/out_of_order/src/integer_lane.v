/** @module : integer_lane
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

module integer_lane #(
    parameter XLEN                = 64,
    parameter ROB_INDEX_WIDTH     = 8,  // Number of ROB address bits
    parameter DECODED_INSTR_WIDTH = 6   // Size of the decoded instruction
) (
    input clock,
    input reset,
    // Dispatch port: when a slot is occupied and has both Qj and Qk values, sends out the decoded instruction,
    // ROB destination, and the operands
    output                           dispatch_ready,
    input                            dispatch_valid,
    input [XLEN                -1:0] dispatch_1st_reg,
    input [XLEN                -1:0] dispatch_2nd_reg,
    input [DECODED_INSTR_WIDTH -1:0] dispatch_decoded_instruction,
    input [ROB_INDEX_WIDTH     -1:0] dispatch_ROB_index,
    input [XLEN                -1:0] dispatch_PC_i,
    // ROB port
    // Since we assume that the ROB has a slot reserved, execute_ready is always 1
    input                            execute_ready,
    output                           execute_valid,
    output reg [ROB_INDEX_WIDTH-1:0] execute_ROB_index,
    output reg [XLEN           -1:0] execute_value,
    // Flush from the ROB
    input flush
);

    /*
     * ALU module
     */
    wire [XLEN-1:0] ALU_output;
    wire [DECODED_INSTR_WIDTH -1:0] dispatch_decoded_instruction_final;
    wire [XLEN                -1:0] dispatch_1st_reg_final;
    wire [XLEN                -1:0] dispatch_2nd_reg_final;

    ALU #(
        .DATA_WIDTH(XLEN)
    ) ALU (
        .ALU_operation(dispatch_decoded_instruction_final[5:0]),
        .operand_A    (dispatch_1st_reg_final                 ),
        .operand_B    (dispatch_2nd_reg_final                 ),
        .ALU_result   (ALU_output                             )
    );

    assign dispatch_decoded_instruction_final = (dispatch_decoded_instruction[5:0] == 6'd1) ? 6'd0          : dispatch_decoded_instruction[5:0];
    assign dispatch_1st_reg_final             = (dispatch_decoded_instruction[5:0] == 6'd1) ? 3'd4          : dispatch_1st_reg;
    assign dispatch_2nd_reg_final             = (dispatch_decoded_instruction[5:0] == 6'd1) ? dispatch_PC_i : dispatch_2nd_reg;

    /*
     * State machine used for the valid / ready protocol
     */
    reg full;

    always @ (posedge clock) begin
        if (reset || flush) begin
            full <= 0;
        end else begin
            if (full) begin
                if (execute_ready && dispatch_valid) begin
                    full              <= 1'b1;
                    execute_value     <= ALU_output;
                    execute_ROB_index <= dispatch_ROB_index;
                end
                else if (execute_ready && ~dispatch_valid)
                    full              <= 1'b0;
                else
                    full              <= 1'b1;
            end else begin
                if (dispatch_valid) begin
                    full              <= 1'b1;
                    execute_value     <= ALU_output;
                    execute_ROB_index <= dispatch_ROB_index;
                end
                else
                    full              <= 1'b0;
            end
        end
    end

    /*
     * Output ports
     */
    assign execute_valid  = full;
    assign dispatch_ready = ~full || execute_ready;

endmodule
