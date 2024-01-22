/** @module : matching_encoder
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
 * Given an array of values and valid signals for each value, returns the index
 * of the last matching and valid value.
 *
 * Mostly used for implementing content addressable memory (CAM).
 */
module matching_encoder #(
    parameter INDEX_WIDTH = 10,
    parameter VALUE_WIDTH = 10,
    parameter SLOTS       = 1 << INDEX_WIDTH
) (
    input [SLOTS*VALUE_WIDTH    -1:0] array_values, // array of values to be searched
    input [SLOTS                -1:0] array_valids, // 1 bit per value, high if value should be matched against
    input [VALUE_WIDTH          -1:0] lookup_value, // value to search for in the array
    output reg                        lookup_match, // high if value found
    output reg [INDEX_WIDTH     -1:0] lookup_index  // index of the last slot where a match occured
);

    integer idx;
    always @* begin
        lookup_match = 0;
        lookup_index = 0;
        for (idx=0; idx<SLOTS; idx=idx+1) begin: MATCHING_ENCODER_LOOP
            if (array_valids[idx] && array_values[(idx+1)*VALUE_WIDTH-1-:VALUE_WIDTH] == lookup_value) begin
                lookup_match = 1;
                lookup_index = idx;
            end
        end
    end

endmodule
