/** @module : store_buffer
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
 * Store Buffer (SB): a circular buffer that in parallel to the ROB stores the
 * store instruction addresses and values. As the ROB head progresses committing
 * instructions to the register file, ideally, so does the SB commit instructions
 * to memory. However, to increase IPC, the DMemArbiter prioritizes loads over
 * stores. Hence, the ROB at the store buffer head trails behind the ROB head.
 * In order for the current implementation to support precise interrupts,
 * we need to implement functionality that flushes everything in SB past the ROB
 * head, but commits to memory everything between SB head and ROB head.
 *
 *     _____  _                        ____           __   __
 *    / ____|| |                      |  _ \         / _| / _|             _
 *   | (___  | |_  ___   _ __  ___    | |_) | _   _ | |_ | |_  ___  _ __  (_)
 *    \___ \ | __|/ _ \ | '__|/ _ \   |  _ < | | | ||  _||  _|/ _ \| '__|
 *    ____) || |_| (_) || |  |  __/   | |_) || |_| || |  | | |  __/| |     _
 *   |_____/  \__|\___/ |_|   \___|   |____/  \__,_||_|  |_|  \___||_|    (_)
 *
 *
 *          store                 commit
 *           head                  head   tail
 *            |                      |     |
 *  __________V______________________V_____V_________
 *  |     |     |     |     |     |     |     |     |  - stores that have received an address are ready.
 *  |     | rdy | rdy | rdy | rdy |     | rdy |     |    stores receive the addresses OUT OF ORDER
 *  |     |     |     |     |     |     |     |     |  - all stores behind ROB head should by definition be ready
 *  |_____|_____|_____|_____|_____|_____|_____|_____|
 *  |     | cmt | cmt | cmt | cmt |     |     |     |  - When the ROB commits a store instruction, we mark the slot
 *  |_____|_____|_____|_____|_____|_____|_____|_____|    at the commit head as committable
 *
 *        |                       |
 *        |___________  __________|
 *                    \/
 *               don't flush!
 * While still in the buffer, these instructions
 *   should have been committed to memory but
 *     weren't due to the lack of bandwidth.
 *
 *
 *
 * We briefly outline three transactions:
 *
 * Store issue: when the issue queue (IQ) is issuing an instruction, we mark the
 * first free spot (tail) in the store buffer (SB) with the ROB's head, and set
 * the ready flag at that slot to 0. The issued instruction recieves the SB tail
 * index, and carries it around until it executes.
 *
 * Store execute: when the execute stage calculates the store address, we receive
 * the store SB index, as well as the store address and value. We place the value
 * and address at the recieved SB index, and mark the store as ready to be sent
 * out.
 *
 * Mark as committable: when the ROB head changes and non-store instructions are
 * committed, we should check if any stores in the SB have become older than the
 * ROB head. If so, we mark those stores as committable, and they will get sent
 * out to memory once the bandwidth is available. At the same time, we mark the
 * slot of the newest committable store as the place where the SB tail should be
 * reset to on a flush. Since multiple stores may have the same ROB, this index
 * can jump multiple slots on a single commit.
 *
 * Store commit: when the ROB head is greater than the store_ROB[SB head], the
 * store at the SB head is ready, and the memory interface needs to be available,
 * we can safely commit the store to memory.
 *
 * TODO: recently, I have discovered an issue where a store to an address A may
 * get committed, but not stored. After the store, a load to the same address may
 * be sent out, and since the store is already committed, the load will also be
 * committed without a hazard being raised. However, since the store hasn't
 * actually been sent to memory yet, the load will return the wrong value. Memory
 * forwarding fixes this, but we should implement this later. We should update
 * the documentation for now.
 *
 */
module store_buffer #(
    parameter XLEN                = 64, // Register value size
              SB_INDEX_WIDTH      = 4,  // log2 of the number of slots in the store buffer
              ROB_INDEX_WIDTH     = 8,  // Number of ROB address bits
              DECODED_INSTR_WIDTH = 6   // Specifies SD, SW, SH or SB
)(
    input                           clock,
    input                           reset,
    input                           flush,
    // Current ROB head and tail
    input  [ROB_INDEX_WIDTH   -1:0] ROB_head,                  // Current head of the ROB. When ROB head > store ROB, it is safe to commit a store to memory
    // Issue queue port
    output                          issue_SB_ready,            // SB ready to receive
    input                           issue_SB_valid,            // IQ issuing a store
    input  [XLEN              -1:0] issue_SB_PC,               // PC of the store
    input [DECODED_INSTR_WIDTH-1:0] issue_decoded_instruction, // Bottom 2 bits determine whether a store is SD, SW, SH or SB
    output [SB_INDEX_WIDTH    -1:0] issue_SB_tail,             // SB tail
    // Store execute port
    input                           execute_valid,             // Store execute valid
    output                          execute_ready,             // Ready for a new store
    input  [SB_INDEX_WIDTH    -1:0] execute_SB_tail,           // SB tail
    input  [XLEN              -1:0] execute_value,             // Value to be stored
    input  [XLEN              -1:0] execute_address,           // Address where to store the value
    // ROB commit port
    input                           store_commit_valid,        // The instruction at the head of the ROB is a store
    output                          store_commit_ready,        // Ready to mark head as commitable
    output [XLEN              -1:0] store_commit_address,      // Address of the store being committed
    // Commit / Memory port
    input                           store_request_ready,       // High if the memory is ready to accept a store
    output                          store_request_valid,       // High if the store request is valid
    output [XLEN              -1:0] store_request_address,     // Address to which we are storing
    output [XLEN              -1:0] store_request_value,       // Value being stored
    output [XLEN/8            -1:0] store_request_byte_en      // Specifies which bytes should be written
);

    localparam SLOTS = 1 << SB_INDEX_WIDTH;

    localparam EMPTY  = 2'd0, // Not assigned yet
               ISSUED = 2'd1, // Not yet received the address + value
               READY  = 2'd2; // Received the address + value, but not committed yet

    /*
     * Store buffer FIFO registers
     */
    reg  [SB_INDEX_WIDTH-1:0] commit_head, tail;        // Store buffer FIFO head and tail
    wire [SB_INDEX_WIDTH-1:0] next_tail = tail + 1;

    reg [1     :0] slot_state   [SLOTS-1:0]; // State of each slot, out of EMPTY, ISSUED & READY
    reg [1     :0] slot_type    [SLOTS-1:0]; // SD, SW, SH or SB
    reg [XLEN-1:0] slot_value   [SLOTS-1:0]; // Value to be written
    reg [XLEN-1:0] slot_address [SLOTS-1:0]; // Address to write to


    /**
     * Used only for testing purposes
     */
    `ifdef TEST
        reg  [XLEN-1:0] PCs [SLOTS-1:0];
        wire [SB_INDEX_WIDTH-1:0] elements_in_SB = tail - commit_head;
    `endif

    /*
     * Pointer logic
     */
    always @ (posedge clock) begin
        if (reset) begin
            tail        <= 0;
            commit_head <= 0;
        end else begin
            if (store_commit_valid && store_commit_ready)
                commit_head <= commit_head + 1;

            if (flush)
                tail <= commit_head;
            else if (issue_SB_ready && issue_SB_valid)
                tail <= next_tail;
        end
    end


    /*
     * Slot state machine:
     *
     *   +-------+      +--------+
     *   | EMPTY +----->+ ISSUED |
     *   +---+---+      +----+---+
     *       ^               |
     *       |               v
     *       |          +----+--+
     *       L----------+ READY |
     *                  +-------+
     *
     */
    genvar i;

    generate
        for (i=0; i<SLOTS; i=i+1) begin: SB_SLOT_STATE_MACHINE
            always @ (posedge clock) begin
                if (reset || flush)
                    slot_state[i] <= EMPTY;
                else begin
                    case (slot_state[i])
                        EMPTY:
                            if (issue_SB_ready && issue_SB_valid && tail == i) begin
                                slot_state[i] <= ISSUED;
                                slot_type [i] <= issue_decoded_instruction[1:0];
                                `ifdef TEST
                                PCs       [i] <= issue_SB_PC;
                                `endif
                            end

                        ISSUED:
                            if (execute_ready && execute_valid && execute_SB_tail == i) begin
                                slot_state  [i] <= READY;
                                slot_address[i] <= execute_address;
                                slot_value  [i] <= execute_value;
                            end

                        READY:
                            if (store_commit_ready && store_commit_valid && commit_head == i)
                                slot_state   [i] <=  EMPTY;

                        default:
                            $display("Invalid state in store buffer");
                    endcase
                end
            end
        end
    endgenerate


    /*
     * Issue port
     */
    assign issue_SB_ready = next_tail[SB_INDEX_WIDTH-1:0] != commit_head;
    assign issue_SB_tail  = tail;


    /*
     * Execute port recieves both the address and the value to write to memory. Since stores can be
     * executed out-of-order, stores carry around the SB tail index which was assigned in-order.
     */
    assign execute_ready = 1; // There's no reason why we couldn't accept a calculated address & value


    /*
     * ROB commit port && store request port:
     * When the memory is ready to accept a store, SB is ready to accept a commit
     */
    assign store_commit_ready    = slot_state[commit_head] == READY && store_request_ready;
    assign store_commit_address  = slot_address[commit_head];

    assign store_request_valid   = store_commit_ready && store_commit_valid;
    assign store_request_address = slot_address[commit_head]; // Address to which we are storing
    /*
     * Value shifting logic
     */
    localparam SD=3, SW=2, SH=1, SB=0;
    assign store_request_value   = slot_type[commit_head] == SD ?    slot_value[commit_head]         :
                                   slot_type[commit_head] == SW ? {2{slot_value[commit_head][31:0]}} :
                                   slot_type[commit_head] == SH ? {4{slot_value[commit_head][15:0]}} :
                                   slot_type[commit_head] == SB ? {8{slot_value[commit_head][ 7:0]}} :
                                                                  0;
    /*                   */
    /* Byte enable logic */
    /*                   */
    wire [7:0] base_byte_en = slot_type[commit_head] == SD ? 8'b11111111:
                              slot_type[commit_head] == SW ? 8'b00001111:
                              slot_type[commit_head] == SH ? 8'b00000011:
                              slot_type[commit_head] == SB ? 8'b00000001
                                                           : 0;
    wire misaligned_store =
        (slot_type[commit_head] == SD && store_request_address[2:0] != 0) ||
        (slot_type[commit_head] == SW && store_request_address[1:0] != 0) ||
        (slot_type[commit_head] == SH && store_request_address[  0] != 0);

    assign store_request_byte_en = misaligned_store ? 0 : base_byte_en << store_request_address[2:0];


endmodule
