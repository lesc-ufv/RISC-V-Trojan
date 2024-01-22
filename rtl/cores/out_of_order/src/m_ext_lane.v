/** @module : m_extension_lane
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

module m_ext_lane #(
    parameter XLEN                = 64,
    parameter ROB_INDEX_WIDTH     = 8,  // Number of ROB address bits
    parameter DECODED_INSTR_WIDTH = 6   // Size of the decoded instruction
) (
    input clock_i,
    input reset_i,
    // Dispatch port: when a slot is occupied and has both Qj and Qk values, sends out the decoded instruction,
    // ROB destination, and the operands
    output                            dispatch_ready_o,
    input                             dispatch_valid_i,
    input [XLEN                -1:0]  dispatch_1st_reg_i,
    input [XLEN                -1:0]  dispatch_2nd_reg_i,
    input [DECODED_INSTR_WIDTH -1:0]  dispatch_decoded_instruction_i,
    input [ROB_INDEX_WIDTH     -1:0]  dispatch_ROB_index_i,
    // ROB port
    // Since we assume that the ROB has a slot reserved, execute_ready_i is always 1
    input                             execute_ready_i,
    output                            execute_valid_o,
    output  [ROB_INDEX_WIDTH-1:0]     execute_ROB_index_o,
    output  [XLEN           -1:0]     execute_value_o,
    // flush_i from the ROB
    input flush_i
);

    wire [XLEN-1:0] MLU_output;
    wire            dispatch_ready;
    wire            valid_result;

    reg  [XLEN                -1:0]     dispatch_1st_reg;
    reg  [XLEN                -1:0]     dispatch_2nd_reg;
    reg  [DECODED_INSTR_WIDTH -1:0]     dispatch_decoded_instruction;
    reg  [ROB_INDEX_WIDTH     -1:0]     dispatch_ROB_index;
    wire [XLEN                -1:0]     dispatch_1st_register;
    wire [XLEN                -1:0]     dispatch_2nd_register;
    wire [DECODED_INSTR_WIDTH -1:0]     dispatch_MLU_operation;
    wire [ROB_INDEX_WIDTH     -1:0]     ROB_index;

    reg  [ROB_INDEX_WIDTH-1:0] execute_ROB_index;
    reg  [XLEN           -1:0] execute_value;

    reg valid_result_r;

    // dispatch_signals coming in are held only for one cycle and hence need to
    // capture them in a register as for a Divide we need to hold the values
    // for multiple cycles till the division is complete.
    // This is a requirement of MLU module.
    always @ (posedge clock_i) begin
        if (reset_i | flush_i | valid_result_r) begin
            dispatch_1st_reg             <= 0;
            dispatch_2nd_reg             <= 0;
            dispatch_decoded_instruction <= 0;
            dispatch_ROB_index           <= 0;
        end else if (dispatch_valid_i & ~valid_result_r) begin
            dispatch_1st_reg             <= dispatch_1st_reg_i;
            dispatch_2nd_reg             <= dispatch_2nd_reg_i;
            dispatch_decoded_instruction <= dispatch_decoded_instruction_i;
            dispatch_ROB_index           <= dispatch_ROB_index_i;
        end
    end

    // Or of input dispatch signals and the registered dispatch signals
    // so that we don't lose a cycle and send the result to the MLU module
    assign dispatch_1st_register  = dispatch_1st_reg_i             | dispatch_1st_reg;
    assign dispatch_2nd_register  = dispatch_2nd_reg_i             | dispatch_2nd_reg;
    assign dispatch_MLU_operation = dispatch_decoded_instruction_i | dispatch_decoded_instruction;
    assign ROB_index              = dispatch_ROB_index             | dispatch_ROB_index_i;

    /*
     * MLU module
     */
    MLU #(
      .DATA_WIDTH(XLEN)
    ) MLU (
        .clock        (clock_i                     ),
        .reset        (reset_i | flush_i           ),
        .ALU_operation(dispatch_MLU_operation[5:0] ),
        .operand_A    (dispatch_1st_register       ),
        .operand_B    (dispatch_2nd_register       ),
        .ready_i      (execute_ready_i             ),
        .ready_o      (dispatch_ready              ),
        .MLU_result   (MLU_output                  ),
        .valid_result (valid_result                )
    );


    /*
     * State machine used for the valid / ready protocol
     */
    reg full;

    always @ (posedge clock_i) begin
        if (reset_i || flush_i) begin
            full <= 0;
            execute_value <= 0;
            execute_ROB_index <= 0;
            valid_result_r <= 1'b0;
        end
        else begin
            execute_value     <= MLU_output;
            valid_result_r <= valid_result;
            if (full) begin
                if (execute_ready_i & ~dispatch_valid_i & valid_result_r) begin
                    full              <= ~dispatch_ready;
                    execute_ROB_index <= ROB_index;
                end
                else begin
                    full              <= 1'b1;
                end
            end
            else begin
                if (dispatch_valid_i) begin
                    full              <= 1'b1;
                    execute_ROB_index <= ROB_index;
                end
                else begin
                    full              <= 1'b0;
                end
            end
        end
    end

    /*
     * Output ports
     */
    assign execute_value_o     = execute_value;
    assign execute_ROB_index_o = execute_ROB_index;
    assign execute_valid_o     = full & valid_result_r;
    assign dispatch_ready_o    = dispatch_ready & (~full | valid_result);

endmodule
