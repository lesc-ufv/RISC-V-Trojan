/** @module : reservation_station
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
 * I-cache MSHR registers which accept incoming I-cache responses, and potentially
 * reorder them and flush any in-flight loads that gor around the flush signal.
 */
module fetch_receive_ooo #(
    parameter XLEN       = 64,
    parameter SLOT_WIDTH = 3
) (
    input             clock,
    input             reset,
    // Fetch issue port
    input             fetch_issue_valid,          // High if FI wants to send out a request to I-cache
    output            fetch_issue_ready,          // High if FR has slots to accept a new PC
    input [XLEN-1:0]  fetch_issue_PC,             // PC of the I-cache request
    input             fetch_issue_NLP_BTB_hit,    // If there was BTB hit in Fetch issue
    // I-cache fetch  receive port
    input             fetch_response_valid,       // High if I-cache responding
    output            fetch_response_ready,       // High if FR ready to accept response
    input [XLEN-1:0]  fetch_response_instruction, // Instruction from I-cache
    input [XLEN-1:0]  fetch_response_PC,          // PC of the response
    // Decode port
    output            decode_issue_valid,         // High if has an instruction for decode
    input             decode_issue_ready,         // High if decode is ready to accept an instruction
    output [31    :0] decode_issue_instruction,   // Instruction to be decoded
    output [XLEN-1:0] decode_issue_PC,            // PC of the instruction
    output            decode_issue_NLP_BTB_hit,   // Send the BTB hit information to Decode
    // Flush port port
    input             flush                       // High if FR should disregard all outstanding requests
);

    localparam SLOTS = 1 << SLOT_WIDTH;

    /*
     * Head and tail pointers
     */
    reg [SLOT_WIDTH-1:0] head, tail;

    /*
     * MSHR registers
     */
    reg            issued       [0:SLOTS-1]; // High if instruction at PC sent out to I-cache, used to match incoming responses
    reg            received     [0:SLOTS-1]; // High if I-cache responded, used to allow head to send out instructions
    reg [XLEN-1:0] PCs          [0:SLOTS-1]; // Issued PCs
    reg [31    :0] instructions [0:SLOTS-1]; // Instruction responses
    reg            NLP_BTB_hit  [0:SLOTS-1]; // High if I-cache responded, used to allow head to send out instructions

    /*
     * CAM logic for PCs
     */
    wire [XLEN*SLOTS-1:0] PCs_flat;
    wire [SLOTS     -1:0] issued_flat;
    wire [SLOTS     -1:0] received_flat;
    wire                  lookup_match;
    wire [SLOT_WIDTH-1:0] lookup_index;

    genvar x;
    generate
        for (x=0; x<SLOTS; x=x+1) begin: PC_ARRAY
            assign PCs_flat[(x+1)*XLEN-1-:XLEN] = PCs[x];
            assign issued_flat[x]               = issued[x];
            assign received_flat[x]             = received[x];
        end
    endgenerate

    matching_encoder #(
        .INDEX_WIDTH (SLOT_WIDTH       ),
        .VALUE_WIDTH (XLEN             )
    ) CAM_LOGIC (
        .array_values(PCs_flat                    ),
        .array_valids(issued_flat & ~received_flat),
        .lookup_value(fetch_response_PC           ),
        .lookup_match(lookup_match                ),
        .lookup_index(lookup_index                )
    );

    /*
     * Head an tail fetch issue and decode issue logic:
     * new, fetched instructions get added at the tail,
     * and instructions sent to decode are read from the head
     */
    integer i;
    always @ (posedge clock) begin
        if (reset || flush) begin
            head <= 0;
            tail <= 0;
            for (i=0; i<SLOTS; i=i+1) begin
                issued  [i]    <= 0;
                received[i]    <= 0;
                PCs[i]         <= 0;
                NLP_BTB_hit[i] <= 1'b0;
            end
        end
        else begin
            /*
             * Fetch issue port: if the tail instruction is received and decode is ready, send it out
             */
            if (fetch_issue_ready && fetch_issue_valid) begin
                issued     [tail] <= 1;
                received   [tail] <= 0;
                PCs        [tail] <= fetch_issue_PC;
                NLP_BTB_hit[tail] <= fetch_issue_NLP_BTB_hit;
                tail              <= tail + 1;
            end
            /*
             * Fetch response port: I-cache responses with instructions and PCs.
             * Only updates if the PC is expected (i.e., previously issued and not flushed in the meantime)
             *
             * Note: lookup_match should never match tail, used to help synthesis
             */
            if (fetch_response_ready && fetch_response_valid && lookup_match && lookup_index != tail) begin
                received    [lookup_index] <= 1;
                instructions[lookup_index] <= fetch_response_PC[2]
                                            ? fetch_response_instruction[63:32]
                                            : fetch_response_instruction[31: 0];
            end
            /*
             * Decode issue port: if the head instruction is received and decode is ready, send it out
             *
             * Note: head should never match lookup_match or tail, used to help synthesis
             */
            if (decode_issue_valid && decode_issue_ready && head != tail) begin// &&
                // either lookup shouldn't be matching anything, or if it is, it shouldn't match head
                //(~(lookup_match && fetch_response_ready && fetch_response_valid) || (head != lookup_index))) begin
                issued  [head] <= 0;
                received[head] <= 0;
                head           <= head + 1;
            end
        end
    end

    /*
     * Outputs
     */
    assign fetch_issue_ready        = tail+1'b1 != head; // Wastes a slot to simplify logic

    assign fetch_response_ready     = 1'b1; // Always ready, but may ignore unmatched loads

    assign decode_issue_valid       = received    [head];
    assign decode_issue_instruction = instructions[head];
    assign decode_issue_PC          = PCs         [head];
    assign decode_issue_NLP_BTB_hit = NLP_BTB_hit [head];

endmodule
