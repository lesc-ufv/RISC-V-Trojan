/** @module : precoder
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

/**
 * We can't load instruction cache lines directly into the decoder because:
 *   1. There are multiple instructions per cache line
 *   2. Some instructions may be compressed, so we can't split the cache line at 32b boundaries
 *   3. Some 32b instructions may be broken over a cache line, and need to be buffered until we load the next cache line.
 *
 * Precoder (Pre-decoder) accepts a cache line from the Icache, and performs simple
 * decoding in order to output whole 32-bit instructions. It:
 *   1. Decompresses compressed instructions into their 32b counterparts,
 *   2. Fixes 32-bit instructions broken over a cache line
 *   3. TODO: Determines if the instruction is a jump or a branch, in order to inform the fetch unit ASAP
 *
 */
module precoder #(
    parameter XLEN       = 64,
    parameter INPUT_INST = 4
) (
    input                          clock,
    input                          reset,
    input                          flush,
    // I-cache fetch response port
    input                          fetch_response_valid,
    output                         fetch_response_ready,
    input [16*INPUT_INST     -1:0] fetch_response_data,
    input [XLEN              -1:0] fetch_response_PC,
    // Decode stage port
    output                         precoder_valid,
    input                          precoder_ready,
    output reg [32*INPUT_INST-1:0] precoder_instructions, // Since Icache may return C instructions, after conversion we need 2x the width
    output [log2(INPUT_INST)   :0] precoder_instruction_count, // number of valid instructions
    output reg [64*INPUT_INST-1:0] precoder_PCs
);

   `include "../rtl/cores/out_of_order/functions/log2.v"
   `include "../rtl/cores/out_of_order/functions/cext.v"

    reg [log2(INPUT_INST):0] instruction_count, pointer;

    //
    // Keeps track of a 16b buffer for broken instructions
    //
    reg half_full; // high if the previous cache line had a broken 32-bit instruction at the end
    reg [15:0] instruction_half; // content of the last 16 bits of the previous cache line

    always @ (posedge clock) begin
        if (reset || flush) begin
            half_full <= 0;
        end
        else begin
            if (fetch_response_valid && precoder_ready) begin
                // If the pointer doesn't point past the end of the fetch data, there's a broken instruction
                half_full <= pointer != INPUT_INST + half_full;
                instruction_half <= fetch_response_data[INPUT_INST*16-1:(INPUT_INST-1)*16];
            end
        end
    end

    //
    // 16 bit sections, with a possibly appended broken instruction from last cache line
    //
    wire [(INPUT_INST+1)*16-1:0] section_16b;
    assign section_16b = half_full ? {fetch_response_data, instruction_half} : {16'b0, fetch_response_data};

    //
    // Figure out if any of the 16-bit sections in the cache line are possibly compressed instructions
    //
    genvar i;
    wire [INPUT_INST-1:0] possibly_compressed;
    generate
        for (i=0; i<INPUT_INST; i=i+1) begin: POSSIBLY_COMPRESSED_BITS
            assign possibly_compressed[i] = is_compressed(fetch_response_data[i*16+15:i*16]);
        end
    endgenerate

    //
    // If there is a broken instruction, shift the compressed instructions by one
    //
    wire [INPUT_INST:0] possibly_compressed_shifted;
    assign possibly_compressed_shifted = half_full ? {possibly_compressed, 1'b0} : {1'b0, possibly_compressed};

    //
    // Traverse the cache line from low to high bits:
    //     1. decompress compressed instructions,
    //     2. assign each one to the appropriate 32-bit output lane,
    //     3. calculate the PC of each instruction,
    //     4. and count the instructions
    //
    integer cnt;

    generate
    always @*
    begin
        pointer = 0;
        instruction_count = 0;

        for (cnt=0; cnt<=INPUT_INST; cnt=cnt+1) begin
            if (possibly_compressed_shifted[pointer] && pointer < INPUT_INST + half_full) begin
                precoder_instructions[cnt*32+31-:32] = c2i(section_16b[pointer*16+15-:16]);
                precoder_PCs         [cnt*64+63-:64] = fetch_response_PC + pointer * 2 - (half_full ? 2 : 0);
                instruction_count                    = instruction_count + 1;
                pointer                              = pointer + 1;
            end else if (pointer < INPUT_INST-1 + half_full) begin
                precoder_instructions[cnt*32+31-:32] = section_16b[pointer*16+31-:32];
                precoder_PCs         [cnt*64+63-:64] = fetch_response_PC + pointer * 2 - (half_full ? 2 : 0);
                instruction_count                    = instruction_count + 1;
                pointer                              = pointer + 2;
            end else begin // NOOP
                precoder_instructions[cnt*32+31-:32] = 32'b000000000000_00000_000_00000_0010011; // ADDI x0, x0, 0
            end
        end
    end
    endgenerate

    //
    // This whole module is relatively stateless (other than the broken instruction),
    // so the valid and ready signals go right through it.
    //
    assign precoder_valid = fetch_response_valid;
    assign fetch_response_ready = precoder_ready;
    assign precoder_instruction_count = instruction_count;

endmodule
