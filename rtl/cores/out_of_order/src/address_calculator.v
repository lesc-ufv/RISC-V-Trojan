/** @module : address_calculator
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

/*
 * Recieves a register and an immediate from a reservation station, and from them
 * computes an address. Registers a single instruction and passes it on.
 */
module address_calculator #(
    parameter XLEN                = 64,
              ROB_INDEX_WIDTH     = 8   // Number of ROB address bits
) (
    input clock,
    input reset,
    // Dispatch port: when a slot is occupied and has both Qj and Qk values, sends out the decoded instruction,
    // ROB destination, and the operands
    output                               dispatch_ready,
    input                                dispatch_valid,
    input [XLEN               -1:0]      dispatch_1st_reg,
    input [XLEN               -1:0]      dispatch_2nd_reg,
    input [XLEN               -1:0]      dispatch_address,
    input [ROB_INDEX_WIDTH    -1:0]      dispatch_ROB_index,
    // ROB port
    // Since we assume that the ROB has a slot reserved, execute_ready is always 1
    input                                execute_ready,
    output                               execute_valid,
    output reg [ROB_INDEX_WIDTH    -1:0] execute_ROB_index,
    output reg [XLEN               -1:0] execute_value,
    output reg [XLEN               -1:0] execute_address,
    // Flush from the ROB
    input                                flush
);

    /*
     * State machine used for the valid / ready protocol
     */
    reg full;
    always @ (posedge clock) begin
        if (reset || flush) begin
            full <= 0;
        end else
            full <= full + (execute_valid && execute_ready) - (dispatch_valid && dispatch_ready);
    end

    always @ (posedge clock) begin
        if (dispatch_valid && dispatch_ready) begin
            execute_value               <= dispatch_2nd_reg;
            execute_address             <= dispatch_1st_reg + dispatch_address;
            execute_ROB_index           <= dispatch_ROB_index;
        end
    end

    /*
     * Output ports
     */
    assign execute_valid  = full;
    assign dispatch_ready = ~full || execute_ready;

endmodule
