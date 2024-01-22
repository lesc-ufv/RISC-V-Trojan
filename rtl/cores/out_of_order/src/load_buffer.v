/** @module : load_buffer
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
 * Load buffer stores the ROB id's and addresses of load requests sent to memory,
 * so that once the responses arrive (which contain only the address and value),
 * we can figure out which ROB id to assign to them. This is necessary when load
 * responses can potentially arrive out-of-order, e.g., due to cache misses.
 * Note that in the case where there are multiple loads with the same address in
 * the load buffer (LB), the LB should return the _oldest_ requested ROB.
 * This is because we  have to assume that loads to the same address return in
 * the same order that they were issued. This creates implementational
 * difficulties we describe later.
 *
 * An additional responsability of the load buffer is to detect RAW hazards. More
 * specifically, the current implementation eagerly sends out load requests, even
 * though the store buffer may contain stores that should be forwarded. While
 * forwarding stores is easy when stores in SB contain an address, there is a
 * possibility that a ready load should forward a value from an earlier, unready
 * store. We then either have to wait for all previous stores to be resolved to
 * be sure if we can forward the value or not (which hurts IPC), or we can send
 * out loads, and flush the value (and any instructions using the load, or even
 * all subsequent instructions) if we detect RAW hazard.
 *
 *
 * Implementation: this is a strange FIFO. When an load is executed, i.e.,
 * we calculate the load address and send it to memory, we save that loads address
 * and ROB index at the tail of the FIFO, and mark that slot as sent out and
 * uncommitted. The tail can progress until it hits a slot which is uncommitted,
 * after which it must stall.
 * When the load response comes in, we search the FIFO for slots with a matching
 * address, and we pick the FIRST slot LEFT of the tail, since that is the
 * earliest load that accessed that address. This is due to the assumption we make
 * that load requests to the same address arrive in the same address they were
 * sent out. When we find the matching slot, we again pair the address with the
 * ROB, as well as the loaded value, and send them off to the reorder buffer.
 * We also mark the same slot as no longer sent out, but still uncommitted.
 * As the ROB head commits instructions, we check whether any instructions in the
 * buffer match the ROB head (we have to check them all since the buffer is
 * filled out of order), and if so, mark these instructions as committed. As
 * committed instructions can no longer cause RAW hazards with the store buffer,
 * we are safe to overwrite them.
 *
 * We briefly describe the five ports of the module:
 *
 * Address receive port: accepts the ROB id and the newly calculated memory
 * address, and stores the address and ROB pair at the tail of the buffer.
 *
 * Load request port: simply forwards the inputs received from the execute port
 * to the memory, so as to avoid issues with three-way connections.
 *
 * Load response port: accepts the load response address, and finds the
 * oldest matching address. LB sends out the (oldest matching) ROB index, which
 * paired with the loaded value can be sent on the common data bus as any other
 * executed instruction.
 *
 * Load execute port: once we have received a load response, we find the
 * appropriate ROB and register the value and the ROB.
 *
 * Load commit port: load buffer needs to store all ROB-address pairs until each
 * load is committed, in order to detect potential RAW memory hazards. This port
 * accepts a commit flag and the current ROB head. If a match is found, the LB
 * marks the ROB-address pair as committed, so that it can be overwritten by the
 * tail pointer.
 *
 * Store commit port: accepts the address of the store that is being committed,
 * and checks if there exists a single load in the buffer that has the matching
 * address. Since all loads in the buffer have not been committed yet, the store
 * is guaranteed to be older and if their addresses are matching, is guaranteed
 * to cause a RAW hazard (unless the store was forwarded or has the same value
 * as the load).
 *
 */
module load_buffer #(
    parameter XLEN                = 64,
    parameter ROB_INDEX_WIDTH     = 8,  // log2(number of ROB slots)
    parameter LB_INDEX_WIDTH      = 4,  // log2(number of LB slots)
    parameter DECODED_INSTR_WIDTH = 6
) (
    input                        clock,
    input                        reset,
    input                        flush,
    // Load issue port
    output                       issue_ready,
    input                        issue_valid,
    input [ROB_INDEX_WIDTH -1:0] issue_ROB_index,
    input [DECODED_INSTR_WIDTH-1:0] issue_decoded_instruction,
    // Load execute port
    output                       address_receive_ready,     // Ready to accept a load address
    input                        address_receive_valid,     // Load has gone through the address calculation and can be sent out
    input [ROB_INDEX_WIDTH -1:0] address_receive_ROB_index, // ROB index assigned to the load at issue time
    input [XLEN            -1:0] address_receive_address,   // Address to be loaded from memory
    // Load request port, TODO: rename to memory_request
    input                        load_request_ready,        // Ready to accept a load address
    output                       load_request_valid,        // Load has gone through the address calculation and can be sent out
    output [XLEN           -1:0] load_request_address,      // Address to be loaded from memory
    // Load response port, TODO: rename to memory_response
    output                       load_response_ready,       // Ready to accept load responses. Since the memory can't stall, this should always be high.
    input                        load_response_valid,       // High if receiving a response
    input [XLEN            -1:0] load_response_address,     // Address of the load response that arrived from memory
    input [XLEN            -1:0] load_response_value,       // Value of the load response that arrived from memory
    // ROB accept port
    input                        ROB_accept_ready,          // High if the ROB is ready to accept a value
    output                       ROB_accept_valid,          // High if the LB has a value to send out
    output [XLEN           -1:0] ROB_accept_value,          // Value loaded from memory
    output [ROB_INDEX_WIDTH-1:0] ROB_accept_ROB_index,      // ROB index that was assigned to the load
    // Load commit port
    output                       commit_ready,              // Ready to accept load commit triggers
    input                        commit_valid,              // High when the ROB is about to commit an instruction
    input  [ROB_INDEX_WIDTH-1:0] commit_ROB_index,          // Current head of the ROB
    // Store commit port
    input                        store_commit_valid,        // High if a store is being marked as committable
    input  [XLEN           -1:0] store_commit_address,      // Store address
    output                       store_commit_hazard        // High if there exists an noncommitted load with the same address
);

    localparam SLOTS = 1 << LB_INDEX_WIDTH;

    /*
     * Each slot in the load buffer has a state, with the following state transitions:
     */
    localparam EMPTY                = 3'd0, // slot not allocated yet
               ISSUED               = 3'd1, // slot allocated, not received address yet
               RECEIVED_ADDRESS     = 3'd2, // received address, not yet sent to memory
               SENT_TO_MEMORY       = 3'd3, // received address and sent to memory
               RECEIVED_FROM_MEMORY = 3'd4, // received from memory, not sent to ROB yet
               SENT_TO_ROB          = 3'd5; // sent to ROB, not committed yet


    wire staging_insert, staging_empty;

    wire [LB_INDEX_WIDTH-1:0] load_response_earliest_matching_index;
    wire                      load_response_earliest_matching_index_valid;
    wire [LB_INDEX_WIDTH-1:0] load_request_slot_index; // used to select which slot should get sent out


    reg [LB_INDEX_WIDTH-1:0]  tail, head;  // Tail and head pointers
    `ifdef TEST
    wire [LB_INDEX_WIDTH-1:0] elements_in_LB = tail - head;
    `endif

    reg [XLEN               -1:0] slot_address   [0:SLOTS-1];
    reg [ROB_INDEX_WIDTH    -1:0] slot_ROB_index [0:SLOTS-1];
    reg [2                    :0] slot_state     [0:SLOTS-1];
    reg [DECODED_INSTR_WIDTH-1:0] slot_instr     [0:SLOTS-1];

    reg                       ROB_staging_valid; // High when we can send a value to the ROB
    reg [XLEN           -1:0] ROB_staging_value; // When we receive a value from the memory, we stage it here
    reg [ROB_INDEX_WIDTH-1:0] ROB_staging_index; // ROB index of the value received from memory


    /*
     * Tail logic
     */
    always @ (posedge clock) begin
        if (reset || flush)
            tail <= 0;
        else if (issue_valid && issue_ready)
            tail <= tail + 1;
    end


    /*
     * Head logic
     */
    always @ (posedge clock) begin
        if (reset || flush)
            head <= 0;
        else if (commit_ready && commit_valid)
            head <= head + 1;
    end


    /*
     * ROB staging logic
     */
    assign staging_insert = load_response_ready && load_response_valid && load_response_earliest_matching_index_valid;
    assign staging_empty  = ROB_accept_ready && ROB_accept_valid;

    always @ (posedge clock) begin
        if (reset || flush)
            ROB_staging_valid <= 0;
        else begin
            ROB_staging_valid <= ROB_staging_valid + staging_insert - staging_empty;
        end
    end


    wire [LB_INDEX_WIDTH-1:0] lremi = load_response_earliest_matching_index;
    wire [XLEN-1:0] shifted_load_response_value = load_response_value >> {slot_address[lremi][2:0], 3'b000};

    always @ (posedge clock) begin
        if (staging_insert) begin
            ROB_staging_index <= slot_ROB_index[lremi];
            ROB_staging_value <=
                 slot_instr[lremi][2:0] == 3'b000 ? {{56{shifted_load_response_value[7]}} , shifted_load_response_value[7 :0]} : // LB
                 slot_instr[lremi][2:0] == 3'b001 ? {{48{shifted_load_response_value[15]}}, shifted_load_response_value[15:0]} : // LH
                 slot_instr[lremi][2:0] == 3'b010 ? {{32{shifted_load_response_value[31]}}, shifted_load_response_value[31:0]} : // LW
                 slot_instr[lremi][2:0] == 3'b011 ?                                         shifted_load_response_value        : // LD
                 slot_instr[lremi][2:0] == 3'b100 ? {56'd0                                , shifted_load_response_value[7 :0]} : // LBU
                 slot_instr[lremi][2:0] == 3'b101 ? {48'd0                                , shifted_load_response_value[15:0]} : // LHU
                 slot_instr[lremi][2:0] == 3'b110 ? {32'd0                                , shifted_load_response_value[31:0]} : // LWU
                 64'd0;
        end
    end

    /*
    *     Slot state machine:
    *
    *    +-------------+     +----------------------+     +------------------+
    *    |    EMPTY    +---->+        ISSUED        +---->+ RECEIVED_ADDRESS |
    *    +-----+-------+     +-----------+----------+     +--------+---------+
    *          ^                         |                         |
    *          |                         +--not implemented---+    |
    *          |                                              v    v
    *    +-----+-------+     +----------------------+     +---+----+---------+
    *    | SENT_TO_ROB +<----+ RECEIVED_FROM_MEMORY +<----+  SENT_TO_MEMORY  |
    *    +-------------+     +----------------------+     +------------------+
    *          ^                                                   |
    *          |                                                   |
    *          +------------------not implemented------------------+
    *
    */

    genvar i;

    generate
        for (i=0; i<SLOTS; i=i+1) begin: LB_SLOT_STATE_MACHINE
            always @ (posedge clock) begin
                if (reset || flush)
                    slot_state[i] <= EMPTY;
                else begin
                    case (slot_state[i])
                        EMPTY:
                            if (issue_ready && issue_valid && tail == i) begin
                                slot_ROB_index[i] <= issue_ROB_index;
                                slot_state    [i] <= ISSUED;
                                slot_instr    [i] <= issue_decoded_instruction;
                            end
                        ISSUED:
                            if (address_receive_ready && address_receive_valid &&
                                    address_receive_ROB_index == slot_ROB_index[i]) begin
                                slot_address  [i] <= address_receive_address;
                                slot_state    [i] <= RECEIVED_ADDRESS;
                            end
                        RECEIVED_ADDRESS:
                            if (load_request_ready && load_request_valid && load_request_slot_index == i) begin
                                slot_state    [i] <= SENT_TO_MEMORY;
                            end
                        SENT_TO_MEMORY:
                            if (load_response_ready && load_response_valid
                                && load_response_earliest_matching_index == i
                                && load_response_earliest_matching_index_valid) begin
                                slot_state    [i] <= RECEIVED_FROM_MEMORY;
                            end
                        RECEIVED_FROM_MEMORY:
                            if (ROB_accept_ready && ROB_accept_valid) begin
                                slot_state    [i] <= SENT_TO_ROB; // only one slot can be in this state at a time
                            end
                        SENT_TO_ROB:
                            if (commit_valid && commit_ready && commit_ROB_index == slot_ROB_index[i]) begin
                                slot_state    [i] <= EMPTY;
                            end
                        default: begin
                            $display("Unexpected state in load buffer!");
                        end
                    endcase
                end
            end
        end
    endgenerate


    /*
     * Issue combinational logic
     */
    wire [LB_INDEX_WIDTH-1:0] next_tail = tail + 1;
    assign issue_ready = next_tail != head;


    /*
     * Address receive combinational logic
     */
    assign address_receive_ready = 1;


    /*
     * Load request combinational logic.
     * Uses a FIFO priority encoder to select the earliest load to send to memory.
     *
     * TODO: allow directly sending executed loads to memory
     */
    wire [SLOTS-1:0] slots_with_addresses;

    generate
        for (i=0; i<SLOTS; i=i+1) begin: LOAD_REQUEST_LOGIC
            assign slots_with_addresses[i] = slot_state[i] == RECEIVED_ADDRESS;
        end
    endgenerate

    fifo_priority_encoder #(
        .ADDR_WIDTH(LB_INDEX_WIDTH),
        .CLOSEST_TO("head"        )
    ) LOAD_REQUEST_SLOT_SELECTOR (
        .inputs(slots_with_addresses   ),
        .head  (head                   ),
        .tail  (tail                   ),
        .valid (load_request_valid     ),
        .index (load_request_slot_index)
    );

    assign load_request_address = slot_address[load_request_slot_index];


    /*
     * Load response combinational logic.
     * Uses a FIFO priority encoder to match the loaded value the earliest MATCHING load already sent to memory.
     */
    assign load_response_ready = ~ROB_staging_valid || ROB_accept_ready;

    wire [SLOTS-1:0] matching_response_addresses;

    generate
        for (i=0; i<SLOTS; i=i+1) begin: LOAD_RESPONSE_LOGIC
            assign matching_response_addresses[i] = slot_state[i] == SENT_TO_MEMORY && slot_address[i] == load_response_address;
        end
    endgenerate

    fifo_priority_encoder #(
        .ADDR_WIDTH(LB_INDEX_WIDTH),
        .CLOSEST_TO("head"        )
    ) LOAD_RESPONSE_SLOT_SELECTOR (
        .inputs(matching_response_addresses                ),
        .head  (head                                       ),
        .tail  (tail                                       ),
        .valid (load_response_earliest_matching_index_valid),
        .index (load_response_earliest_matching_index      )
    );


    /*
     * ROB accept port
     */
    assign ROB_accept_valid     = ROB_staging_valid;
    assign ROB_accept_value     = ROB_staging_value;
    assign ROB_accept_ROB_index = ROB_staging_valid ? ROB_staging_index : 0;

    /*
     * Commit port
     */
    assign commit_ready = slot_ROB_index[head] == commit_ROB_index && slot_state[head] == SENT_TO_ROB;


    /*
     * Hazard detection port
     * TODO: we're flushing too often in order to simplify logic:
     * for example, a SW to addr 0x0 followed by a LW to 0x4 will cause a flush,
     * even though these operations don't overlap in memory.
     */
    wire [SLOTS-1:0] hazard_slots;

    generate
        for (i=0; i<SLOTS; i=i+1) begin: LOAD_BUFFER_HAZARD_DETECTION
            // Should include SENT_TO_MEMORY, RECEIVED_FROM MEMORY, and SENT_TO_ROB
            // TODO: this implementation is too aggressive, and will flush for e.g., sw to address 0 followed by lw from address 4
            // We should fix this
            assign hazard_slots[i] = (slot_state[i] >= SENT_TO_MEMORY) && (slot_address[i][XLEN-1:3] == store_commit_address[XLEN-1:3]);
        end
    endgenerate

    assign store_commit_hazard = store_commit_valid && |hazard_slots;


endmodule
