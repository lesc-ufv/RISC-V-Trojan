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

/* Reservation station is used for storing in-order issued instructions of a certain
 * type (regular / stores / loads, later FP, etc.), and dispatching them out-of-order
 * once all operands are ready.
 *
 * The logic is split into several parts:
 *     1. The buffer setup, containing several register arrays
 *     2. The issue logic, placing instructions into the first available slot
 *     3. The ROB forward logic, accepting any matching updates from previous instructions
 *     4. The dispatch logic, dispatching any ready instructions
 *
 * The reservation station is parametrizable with the:
 *     1. number of reservation station slots
 *     2. number of execution unit busses that can be read in parallel
 *     3. optional address storage (used for instructions that use both operands and
 *            the immediate)
 */

// Reservation station with parametrizable:


module reservation_station #(
    parameter XLEN                    = 64,
    parameter RS_SLOTS_INDEX_WIDTH    = 5,   // log2(Number of RS slots)
    parameter FORWARD_BUSSES          = 4,   // Right now we only have 4 lanes: the integer lane, memory lane, and two ROB forward lanes
    parameter ROB_INDEX_WIDTH         = 8,   // Number of ROB address bits
    parameter DECODED_INSTR_WIDTH     = 32   // Size of the decoded instruction - probably should be smaller than 32 since
                                             // we don't have to store the registers and possibly a part of opcode
) (
    input clock_i,
    input reset_i,
    /*
     * Issue port: accepts a decoded instruction, two registers (either values, or ROB ID's that
     * will be used to forward values once they are calculated), two bits specifying if the registers
     * are renamed or not, and an address (used only for the load and store reservation stations).
     *
     * All of the issue signals come from the issue queue except for the issue_rd_ROB_index_i, which
     * comes from the ROB, and represents the tail of the ROB, i.e., the first free spot in the circular buffer.
     */
    output                          issue_ready_o,               // high if can accept an instruction
    input                           issue_valid_i,               // valid if an instruction present at input
    input [DECODED_INSTR_WIDTH-1:0] issue_decoded_instruction_i, // decoded instruction. RS should not care about it's internals
    input [ROB_INDEX_WIDTH    -1:0] issue_rd_ROB_index_i,        // index in the ROB where the result of this instructions should be stored
    input [XLEN               -1:0] issue_rs1_data_or_ROB_i,     // The ROB index of instruction that will update this register
    input                           issue_rs1_is_renamed_i,      // High if ROB index is set
    input [XLEN               -1:0] issue_rs2_data_or_ROB_i,     // The value of the second register specified by the instruction
    input                           issue_rs2_is_renamed_i,      // High if ROB index is set
    input [XLEN               -1:0] issue_address_i,             // Address used for stores and loads
`ifdef TEST
    input [XLEN               -1:0] issue_PC_i,
`endif

    /*
     * Forwards ports: consists of N execution lane ports and two ROB ports.
     * When an instruction is issued and the register file contains renamed registers (i.e., the register contents
     * are yet to be calculated), the reservation station issues one request per renamed register to the ROB, checking
     * whether the ROB already has the results, but has not committed them yet. If so, the ROB will broadcast these
     * results in the same manner as how lanes broadcast their results. Note that the results the ROB will (potentially)
     * broadcast have already been broadcast by the lane that calculated the results, hence correctness is preserved.
     * TODO: we should check whether 2 lanes are really needed, and potentially create an arbiter that will share the
     * busses between the integer, load, two forward, and FP lanes.
     */
    input [FORWARD_BUSSES-1:0]                 forward_valids_i,  // valid flag of all forward ports
    input [FORWARD_BUSSES*ROB_INDEX_WIDTH-1:0] forward_indexes_i, // forward port index lines
    input [FORWARD_BUSSES*XLEN           -1:0] forward_values_i,  // forward port register lines

    /*
     * Dispatch port: when a slot is occupied and has both Qj and Qk values, that instruction can be dispatched.
     * Right now, we use a decoder that selects the (rightmost?) ready instruction and dispatches it.
     *
     * TODO: ideally, the priority encoder should select the oldest, not the rightmost instruction. The benefits of this
     * approach might be meager however, while the extra area would be substantial. We should investigate this.
     */
    input                            dispatch_ready_i,
    output                           dispatch_valid_o,
    output [XLEN               -1:0] dispatch_1st_reg_o,
    output [XLEN               -1:0] dispatch_2nd_reg_o,
    output [XLEN               -1:0] dispatch_address_o,
    output [DECODED_INSTR_WIDTH-1:0] dispatch_decoded_instruction_o,
    output [ROB_INDEX_WIDTH    -1:0] dispatch_ROB_destination_o,
`ifdef TEST
    output [XLEN               -1:0] dispatch_PC_o,
`endif
    // flush_i from the ROB
    input flush_i
);

    function integer log2;
    input integer value;
    begin
      value = value-1;
      for (log2=0; value>0; log2=log2+1)
        value = value >> 1;
    end
    endfunction

    localparam SLOTS = 1 << RS_SLOTS_INDEX_WIDTH;

    /*
     * Registers composing the contents of the reservation station.
     * Upon reset_i_i, occupied should be set to zeros.
     */
    reg [DECODED_INSTR_WIDTH-1:0] instructions   [0:SLOTS-1]; // decoded instructions
    reg [ROB_INDEX_WIDTH    -1:0] dest_ROB_index [0:SLOTS-1]; // renamed destination register's position in the ROB
    reg [XLEN               -1:0] Qj_or_Vj       [0:SLOTS-1]; // First real or renamed register. Renamed register uses bottom n bits.
    reg [SLOTS              -1:0] j_renamed;                  // If high, Qj is stored, otherwise Vj is.
    reg [XLEN               -1:0] Qk_or_Vk       [0:SLOTS-1]; // Second real or renamed register. Renamed register uses bottom n bits.
    reg [SLOTS              -1:0] k_renamed;                  // If high, Qk is stored, otherwise Vk is.
    reg [XLEN               -1:0] addresses      [0:SLOTS-1]; // Address slots used in stores & loads
    reg [SLOTS              -1:0] occupied;                   // Flag specifying if slot is occupied.
`ifdef TEST
    reg [XLEN               -1:0] PCs            [0:SLOTS-1]; // Program counters, used only for tracking instructions for testing purposes
`endif


    /*
     * Useful functions
     */
    function automatic [log2(FORWARD_BUSSES):0] find_matching_bus;
        input [FORWARD_BUSSES*ROB_INDEX_WIDTH-1:0] forward_indexes_i; // forward port index lines
        input [FORWARD_BUSSES                -1:0] forward_valids_i;  // high if element valid
        input [ROB_INDEX_WIDTH-1:0] index;

        reg valid;
        reg [log2(FORWARD_BUSSES)-1:0] matching_bus;
        //reg [log2(FORWARD_BUSSES):0] idx;
        integer idx;

        begin
            matching_bus = 0;
            valid = 0;
            for (idx=0; idx<FORWARD_BUSSES; idx=idx+1) begin
                if (forward_valids_i[idx] && (forward_indexes_i[ROB_INDEX_WIDTH*(idx+1)-1-:ROB_INDEX_WIDTH] == index)) begin
                    valid = 1;
                    matching_bus = idx;
                end
            end

            find_matching_bus = {valid, matching_bus};
        end
    endfunction


    /*
     * Selects the first unoccupied reservation station
     */
    wire [RS_SLOTS_INDEX_WIDTH-1:0] issue_index;

    priority_encoder #(
        .WIDTH   (SLOTS),
        .PRIORITY("MSB")
    ) issue_select (
        .decode(~occupied  ),
        .encode(issue_index),
        .valid (issue_ready_o)
    );

    /*
     * Dispatch logic: selects the first (rightmost?) ready slot and feeds it to the output.
     * Once both sides agree (dispatch_valid_o_o && dispatch_ready_i_i), that slot is marked as unoccupied.
     */

    // Selects first RS which is ready to start computation
    wire [RS_SLOTS_INDEX_WIDTH-1:0] dispatch_index;

    priority_encoder #(
        .WIDTH   (SLOTS),
        .PRIORITY("MSB")
    ) dispatch_select (
        .decode(occupied & ~j_renamed & ~k_renamed),
        .encode(dispatch_index                    ),
        .valid (dispatch_valid_o                    )
    );

    assign dispatch_decoded_instruction_o = instructions  [dispatch_index];
    assign dispatch_ROB_destination_o     = dest_ROB_index[dispatch_index];
    assign dispatch_1st_reg_o             = Qj_or_Vj      [dispatch_index];
    assign dispatch_2nd_reg_o             = Qk_or_Vk      [dispatch_index];
    assign dispatch_address_o             = addresses     [dispatch_index];
`ifdef TEST
    assign dispatch_PC_o                  = PCs           [dispatch_index];
`endif

    /*
     * A large, per-slot state machine with issue, forward and dispatch logic
     */

    // If issuing at the same time one of the source registers is broadcasted, forward it
    wire forward_issue_rs1_match, forward_issue_rs2_match; // Whether any of the lanes has a result
    wire [log2(FORWARD_BUSSES)-1:0] forward_issue_rs1_index, forward_issue_rs2_index; // Get indexes of the ones in the one hot vectors
    assign {forward_issue_rs1_match, forward_issue_rs1_index} = find_matching_bus(forward_indexes_i, forward_valids_i, issue_rs1_data_or_ROB_i[ROB_INDEX_WIDTH-1:0]);
    assign {forward_issue_rs2_match, forward_issue_rs2_index} = find_matching_bus(forward_indexes_i, forward_valids_i, issue_rs2_data_or_ROB_i[ROB_INDEX_WIDTH-1:0]);

    // Forward ports - RS slot matching logic
    wire forward_RS_rs1_match [0:SLOTS-1];
    wire forward_RS_rs2_match [0:SLOTS-1];
    wire [log2(FORWARD_BUSSES)-1:0] forward_RS_rs1_index [0:SLOTS-1];
    wire [log2(FORWARD_BUSSES)-1:0] forward_RS_rs2_index [0:SLOTS-1];


    genvar slot_idx;
    generate
        for (slot_idx=0; slot_idx<SLOTS; slot_idx=slot_idx+1) begin: SLOT_STATE_MACHINE
            // Forward-slot matching logic
            assign {forward_RS_rs1_match[slot_idx], forward_RS_rs1_index[slot_idx]} = find_matching_bus(forward_indexes_i, forward_valids_i, Qj_or_Vj[slot_idx][ROB_INDEX_WIDTH-1:0]);
            assign {forward_RS_rs2_match[slot_idx], forward_RS_rs2_index[slot_idx]} = find_matching_bus(forward_indexes_i, forward_valids_i, Qk_or_Vk[slot_idx][ROB_INDEX_WIDTH-1:0]);

            always @ (posedge clock_i) begin
                if (reset_i || flush_i) begin
                    instructions  [slot_idx] <= 0;
                    dest_ROB_index[slot_idx] <= 0;
                    Qj_or_Vj      [slot_idx] <= 0;
                    j_renamed     [slot_idx] <= 0;
                    Qk_or_Vk      [slot_idx] <= 0;
                    k_renamed     [slot_idx] <= 0;
                    addresses     [slot_idx] <= 0;
                    occupied      [slot_idx] <= 0;
                end
                /*
                 * Issue port: place the issued instruction at a free slot, and in case the
                 * TODO: don't remember why we needed to check the forward port, if we're also issuing
                 * the forward request at the same time
                 */
                else if (issue_valid_i && issue_ready_o && slot_idx==issue_index) begin
                    instructions  [slot_idx] <= issue_decoded_instruction_i;
                    dest_ROB_index[slot_idx] <= issue_rd_ROB_index_i;
                    Qj_or_Vj      [slot_idx] <= (forward_issue_rs1_match && issue_rs1_is_renamed_i)
                                                    ? forward_values_i[(forward_issue_rs1_index+1)*XLEN-1-:XLEN]
                                                    : issue_rs1_data_or_ROB_i;
                    j_renamed     [slot_idx] <= issue_rs1_is_renamed_i && ~forward_issue_rs1_match;
                    Qk_or_Vk      [slot_idx] <= (forward_issue_rs2_match && issue_rs2_is_renamed_i)
                                                    ? forward_values_i[(forward_issue_rs2_index+1)*XLEN-1-:XLEN]
                                                    : issue_rs2_data_or_ROB_i;
                    k_renamed     [slot_idx] <= issue_rs2_is_renamed_i && ~forward_issue_rs2_match;
                    addresses     [slot_idx] <= issue_address_i;
                    occupied      [slot_idx] <= 1'b1;
`ifdef TEST
                    PCs           [slot_idx] <= issue_PC_i;
`endif
                end
                /*
                 * Dispatch logic
                 */
                else if (dispatch_valid_o && dispatch_ready_i && slot_idx==dispatch_index) begin
                    occupied      [slot_idx] <= 0;
                end
                /*
                 * Forward logic
                 */
                else begin
                    if (occupied[slot_idx] && j_renamed[slot_idx] && forward_RS_rs1_match[slot_idx]) begin
                        Qj_or_Vj  [slot_idx] <= forward_values_i[(forward_RS_rs1_index[slot_idx]+1)*XLEN-1-:XLEN];
                        j_renamed [slot_idx] <= 1'b0;
                    end
                    if (occupied[slot_idx] && k_renamed[slot_idx] && forward_RS_rs2_match[slot_idx]) begin
                        Qk_or_Vk  [slot_idx] <= forward_values_i[(forward_RS_rs2_index[slot_idx]+1)*XLEN-1-:XLEN];
                        k_renamed [slot_idx] <= 1'b0;
                    end
                end
            end
        end
    endgenerate

endmodule
