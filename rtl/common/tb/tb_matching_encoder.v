/** @module : tb_matching_encoder
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

module tb_matching_encoder;

    parameter INDEX_WIDTH = 2;
    parameter VALUE_WIDTH = 4;
    parameter SLOTS       = 1 << INDEX_WIDTH;

    reg [SLOTS*VALUE_WIDTH    -1:0] array_values; // array of values to be searched 
    reg [SLOTS                -1:0] array_valids; // 1 bit per value, high if value should be matched against
    reg [VALUE_WIDTH          -1:0] lookup_value; // value to search for in the array
    wire                            lookup_match; // high if value found
    wire [INDEX_WIDTH         -1:0] lookup_index; // index of the last slot where a match occured

    matching_encoder #(
        .INDEX_WIDTH(INDEX_WIDTH),
        .VALUE_WIDTH(VALUE_WIDTH)
    ) DUT (
        .array_values(array_values),
        .array_valids(array_valids),
        .lookup_value(lookup_value),
        .lookup_match(lookup_match),
        .lookup_index(lookup_index)
    );

    reg pass = 1;

    initial begin

        array_values = {4'b0001, 4'b0010, 4'b0011, 4'b0100};
        array_valids = {   1'b1,    1'b1,    1'b1,    1'b1};
        lookup_value = 4'b0100;

        // Lookup found
        #1 if (!lookup_match || lookup_index != 0) pass = 0;

        // Lookup found
        #10 lookup_value = 4'b0011;
        #1 if (!lookup_match || lookup_index != 1) pass = 0;

        // Lookup found
        #10 lookup_value = 4'b0010;
        #1 if (!lookup_match || lookup_index != 2) pass = 0;

        // Lookup found
        #10 lookup_value = 4'b0001;
        #1 if (!lookup_match || lookup_index != 3) pass = 0;

        // Lookup not found
        #10 lookup_value = 4'b0000;
        #1 if (lookup_match) pass = 0;

        // Lookup found, but invalid
        #10 lookup_value = 4'b0001;
        array_valids = {   1'b0,    1'b1,    1'b1,    1'b1};
        #1 if (lookup_match) pass = 0;

        #10
        #1 if (pass) $display("\ntb_matching_encoder --> Test Passed!\n\n");
        else      $display("\ntb_matching_encoder --> Test Failed!\n\n");

        $stop;
    end

endmodule
