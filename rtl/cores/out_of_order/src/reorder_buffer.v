/** @module : reorder_buffer
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
 * Re-order buffer (ROB) serves to rename registers by replacing instruction
 * destination registers with an ROB index.
 *
 * The ROB has several ports:
 *   Issue port: when the issue stage issues an instruction, it renames the
 *   destination register with the tail pointer of the ROB. The ROB stores
 *   the destination register at the tail, so that once the instruction is
 *   complete, it can commit the instruction's result to the register file.
 *
 *   Forward request: when an instruction is issued and the source registers
 *   are renamed, the issue stage sends a forward request to the ROB for each
 *   of the registers that are renamed.
 *
 *   Forward response: for each forward request, if the ROB has received the
 *   results of the requested instructions, it broadcasts those results on
 *   the common data bus (CDB).
 *
 *   Execute port: accepts results from instructions and places them at the
 *   appropriate ROB slots.
 *
 *   Commit port: takes the instruction at the head of the ROB, and if it is
 *   ready, saves the result to the appropriate destination register in case
 *   of non-store / non-branch instructions. TODO: stores?
 *
 *   Fetch update: on a jump or branch, sends a new PC to the fetch stage.
 *
 * TODO: rename forward_response_* to forward_response_ROB_*?
 */

module reorder_buffer #(
    parameter XLEN            = 32,
    parameter ROB_INDEX_WIDTH = 8,  // Number of ROB address bits
    parameter SB_INDEX_WIDTH  = 5,  // Store buffer index width
    parameter EXECUTION_LANES = 3,  // Right now we only have 3 lanes: the integer lane, the m_ext lane, and the memory lane
    parameter REG_INDEX_WIDTH = 5,  // Register index size
    parameter NLP_UPDATE      = 135 // NLP Update signals width
) (
    input                                          clock,
    input                                          reset,
    output reg                                     flush,
    // Issue port
    output                                         issue_ROB_ready,             // ROB can accept new instruction
    input                                          issue_ROB_valid,             // new instruction present at ROB
    input  [4                                  :0] issue_ROB_dest_reg_index,    // the instruction's destination register
    input  [2                                  :0] issue_ROB_op_type,           // Type of instruction, one of the OP_* values
    input  [XLEN                             -1:0] issue_ROB_imm,               // Immediate of the issued instruction, used for JAL and branches
    input  [XLEN                             -1:0] issue_ROB_PC,                // Address of the issued instruction, used for jumps
    output [ROB_INDEX_WIDTH                  -1:0] issue_ROB_index,             // the ROB assigned to the new instruction, sent to RS and register file

    // Branch prediction update port to ROB
    input                                          issue_ROB_update_rs1_is_link,// high if rs1 register is x1 or x5
    input                                          issue_ROB_update_rd_is_link, // high if rd register is x1 or x5
    input                                          issue_ROB_update_rs1_is_rd,  // high if rd register is x1 or x5
    input                                          issue_ROB_update_BTB_hit,    // high if the instruction now in execute hit BTB when it was in fetch issue
    // ROB forward port: 2 forward busses to the reservation stations, one per operand
    // TODO: we could possibly create a FIFO of ROBs to send out just one per cycle
    // TODO: we can also generalize this
    // ROB forward request
    input  [ROB_INDEX_WIDTH                  -1:0] forward_request_ROB_index_1, // the instruction's first needed ROB - ROB checks if it has the results for it
    input  [ROB_INDEX_WIDTH                  -1:0] forward_request_ROB_index_2, // the instruction's second needed ROB
    input                                          forward_request_ROB_valid_1, // the ROB only broadcasts issue_1st_ROB value if the register is renamed
    input                                          forward_request_ROB_valid_2, // the ROB only broadcasts issue_2nd_ROB value if the register is renamed
    // ROB forward response port outputs
    output reg [1                              :0] forward_response_valids,     // valid flag of all forward ports
    output reg [2*ROB_INDEX_WIDTH            -1:0] forward_response_indexes,    // forward port index lines
    output reg [2*XLEN                       -1:0] forward_response_values,     // forward port register lines
    // Execute unit ports
    output [(EXECUTION_LANES)                -1:0] execute_unit_readys,         // ready flag of all forward ports
    input  [(EXECUTION_LANES)                -1:0] execute_unit_valids,         // valid flag of all forward ports
    input  [(EXECUTION_LANES)*ROB_INDEX_WIDTH-1:0] execute_unit_indexes,        // forward port index lines
    input  [(EXECUTION_LANES)*XLEN           -1:0] execute_unit_values,         // forward port register lines
    // Commit port
    output                                         commit_valid,                // commit message is valid
    output [REG_INDEX_WIDTH                  -1:0] commit_dest_reg,             // commit destination register
    output [XLEN                             -1:0] commit_value,                // value to place in destination register
    output [ROB_INDEX_WIDTH                  -1:0] commit_ROB_index,            // Index of the ROB head
    // Store buffer commit port
    input                                          store_commit_ready,          // Store buffer is ready to commit a store
    output                                         store_commit_valid,          // Store buffer commit is valid
    input                                          store_commit_hazard,         // Store commit caused a hazard since a load to the same address was already sent out
    // PC update port
    output                                         fetch_update_valid,
    input                                          fetch_update_ready,
    output reg [NLP_UPDATE                   -1:0] fetch_update_data
);

    localparam SLOTS = 1 << ROB_INDEX_WIDTH;

    localparam [2:0] OP_STORE  = 3'd0,
                     OP_LOAD   = 3'd1,
                     OP_AUIPC  = 3'd2,
                     OP_JAL    = 3'd3,
                     OP_JALR   = 3'd4,
                     OP_BRANCH = 3'd5,
                     OP_OTHER  = 3'd6;

    localparam       EMPTY = 0,
                     FULL  = 1;

    reg                       completed [0:SLOTS-1]; // value present and ready to be commited
    reg [REG_INDEX_WIDTH-1:0] dest_regs [0:SLOTS-1]; // destination register per slot
    reg [XLEN           -1:0] values    [0:SLOTS-1]; // instruction destination register values
    reg [2                :0] op_types  [0:SLOTS-1]; // type of operation with value set to one of the OP_* localparams
    reg [XLEN           -1:0] imms      [0:SLOTS-1]; // immediate, used for branches and jumps.
    reg [XLEN           -1:0] PCs       [0:SLOTS-1];
    // update_btb[SLOT][0] : rs1 is link
    // update_btb[SLOT][1] : rd is link
    // update_btb[SLOT][2] : rs1 is rd
    // update_btb[SLOT][3] : BTB_hit
    reg [3                :0] update_btb[0:SLOTS-1];

                                                     // neccessary for jumps since JALR needs to both return a value and PC

    reg [ROB_INDEX_WIDTH-1:0] head;                  // head points to the next instruction that should be commited
    reg [ROB_INDEX_WIDTH-1:0] tail;                  // tail points to the next open instruction slot that can be filled

    wire            commit_ready;
    wire [XLEN-1:0] commit_PC;                                            // PC of instruction to commit
    reg             num_mispred;
    reg             num_correctpred;
    reg             jal_num_total;
    wire [2     :0] commit_opcode;

    function integer log2;
    input integer value;
    begin
      value = value-1;
      for (log2=0; value>0; log2=log2+1)
        value = value >> 1;
    end
    endfunction

    /*
     * A function that given a number of execute lane indexes of width ROB_INDEX_WIDTH,
     * checks whether any matches the provided index (second argument)
     */
    function automatic execute_lane_match;
        input [EXECUTION_LANES*ROB_INDEX_WIDTH-1:0] execute_unit_indexes; // execute lane indexes
        input [EXECUTION_LANES                -1:0] execute_unit_valids;  // high if lane valid
        input [ROB_INDEX_WIDTH                -1:0] index;                // slot index

        reg valid;
        integer idx;

        begin
            valid = 0;
            for (idx=0; idx<EXECUTION_LANES; idx=idx+1)
                if (execute_unit_valids[idx] && (execute_unit_indexes[ROB_INDEX_WIDTH*(idx+1)-1-:ROB_INDEX_WIDTH] == index))
                    valid = 1;

            execute_lane_match = valid;
        end
    endfunction

    /*
     * A function that given a number of execute lane indexes of width ROB_INDEX_WIDTH, checks whether
     * any matches the provided index (second argument), and returns the index of the last matching lane.
     */
    function automatic [log2(EXECUTION_LANES)-1:0] matching_lane_index;
        input [EXECUTION_LANES*ROB_INDEX_WIDTH-1:0] execute_indexes; // forward port index lines
        input [EXECUTION_LANES                -1:0] execute_valids;  // high if lane valid
        input [ROB_INDEX_WIDTH-1:0] index;

        reg [log2(EXECUTION_LANES)-1:0] matching_lane;
        integer idx;

        begin
            matching_lane = 0;
            for (idx=0; idx<EXECUTION_LANES; idx=idx+1)
                if (execute_valids[idx] && execute_indexes[ROB_INDEX_WIDTH*(idx+1)-1-:ROB_INDEX_WIDTH] == index)
                    matching_lane = idx;

            matching_lane_index = matching_lane;
        end
    endfunction

    /*
     * Head and tail pointer logic
     */
    integer i;
    always @ (posedge clock) begin
        if (reset || flush) begin
            head <= 0;
            tail <= 0;
        end
        else begin
            // Head progression
            if (commit_valid && commit_ready) begin
                head <= completed[head] ? head + 1 : head;
            end
            // Tail progression
            if (issue_ROB_ready && issue_ROB_valid) begin
                tail <= tail + 1; // Keeps wiping the tail clean, no matter what the old value of ready[tail] was
            end
        end
    end


    /*
     * Large per-slot logic covering Issue, Execute and Commit
     */
    genvar slot_idx;
    generate
        for (slot_idx=0; slot_idx<SLOTS; slot_idx=slot_idx+1) begin: SLOT_STATE_MACHINE
            /*
             * State machine
             */
            always @ (posedge clock) begin
                /*
                 * Reset logic
                 */
                if (reset || flush) begin
                    completed [slot_idx] <= 0;
                    dest_regs [slot_idx] <= 0;
                    values    [slot_idx] <= 0;
                    op_types  [slot_idx] <= 0;
                    imms      [slot_idx] <= 0;
                    PCs       [slot_idx] <= 0;
                    update_btb[slot_idx] <= 0;
                end
                /*
                 * Issue port logic
                 */
                else if (issue_ROB_ready && issue_ROB_valid && tail==slot_idx) begin
                    op_types[slot_idx] <= issue_ROB_op_type;
                    PCs       [slot_idx] <= issue_ROB_PC;
                    update_btb[slot_idx] <= {issue_ROB_update_BTB_hit, issue_ROB_update_rs1_is_rd, issue_ROB_update_rd_is_link, issue_ROB_update_rs1_is_link};

                    case (issue_ROB_op_type)
                        OP_OTHER, OP_AUIPC, OP_LOAD: begin
                            completed[slot_idx] <= 0;
                            dest_regs[slot_idx] <= issue_ROB_dest_reg_index;
                        end
                        OP_STORE: begin
                            // Note: the ROB will not get informed of when the store executes (get's it's address calculated),
                            // only the SB will get informed. However, once the store slot reaches the head of the ROB, we
                            // know that the address calculation must have finished, and we are free to send it out.
                            completed[slot_idx] <= 1;
                            imms     [slot_idx] <= issue_ROB_PC + 4;
                        end
                        OP_JAL: begin
                            // Since JAL's have both the rd and PC calculated, no need to execute them
                            completed[slot_idx] <= 1;
                            dest_regs[slot_idx] <= issue_ROB_dest_reg_index;
                            values   [slot_idx] <= issue_ROB_PC + 4;
                            imms     [slot_idx] <= issue_ROB_imm;
                        end
                        OP_JALR: begin
                            completed[slot_idx] <= 0;
                            dest_regs[slot_idx] <= issue_ROB_dest_reg_index;
                            values   [slot_idx] <= issue_ROB_PC + 4;
                        end
                        OP_BRANCH: begin
                            completed[slot_idx] <= 0;
                            dest_regs[slot_idx] <= 0;
                            imms     [slot_idx] <= issue_ROB_imm;
                        end
                        default:
                            $display("Something went wrong in the ROB!");
                    endcase
                end
                /*
                 * Execute port logic
                 */
                else if (execute_lane_match(execute_unit_indexes, execute_unit_valids, slot_idx)) begin

                    case (op_types[slot_idx])
                        // JALRs are more complex since they have two results to write back: the PC and the
                        OP_JALR: begin
                            imms     [slot_idx] <= execute_unit_values[(matching_lane_index(execute_unit_indexes, execute_unit_valids, slot_idx)+1)*XLEN-1-:XLEN];
                            completed[slot_idx] <= 1'b1;
                        end
                        // JAL instructions have everything they need after dispatch, and don't do any work in the execute
                        // stage, so their output shouldn't be broadcasted. TODO: we shouldn't even dispatch JALs, right?
                        // Alternatively, we should calculate PC + offset in the execute stage, in order to save a 20-bit
                        // adder
                        OP_JAL:
                            completed[slot_idx] <= 1;
                        // All other instructions
                        default: begin
                            values   [slot_idx] <= execute_unit_values[(matching_lane_index(execute_unit_indexes, execute_unit_valids, slot_idx)+1)*XLEN-1-:XLEN];
                            completed[slot_idx] <= 1'b1;
                        end
                    endcase

                end
                /*
                 * Commit port logic
                 */
                else if (commit_valid && commit_ready && head==slot_idx) begin
                    completed[slot_idx] <= 1'b0;
                end
            end
        end
    endgenerate


    /**
     * Issue port outputs
     */
    assign issue_ROB_ready = (tail + 1'b1) != head;
    assign issue_ROB_index = tail;


    /**
     * ROB forwarding:
     */
    always @ (posedge clock) begin
        if (reset || flush) begin
            forward_response_valids <= 0;
        end else begin
            // Forward first register
            if (forward_request_ROB_valid_1 && completed[forward_request_ROB_index_1]) begin
                forward_response_valids [                  0]                 <= 1'b1;
                forward_response_values [XLEN           -1:0]                 <= values[forward_request_ROB_index_1];
                forward_response_indexes[ROB_INDEX_WIDTH-1:0]                 <= forward_request_ROB_index_1;
            end else
                forward_response_valids[0]                                    <= 1'b0;

            if (forward_request_ROB_valid_2 && completed[forward_request_ROB_index_2]) begin
                forward_response_valids [1]                                   <= 1'b1;
                forward_response_values [2*XLEN           -1:           XLEN] <= values[forward_request_ROB_index_2];
                forward_response_indexes[2*ROB_INDEX_WIDTH-1:ROB_INDEX_WIDTH] <= forward_request_ROB_index_2;
            end else
                forward_response_valids [1]                                   <= 1'b0;
        end
    end


    /**
     * Execute unit ports: for now, we are always ready to recieve inputs from execute units.
     * Note: some instructions are special cases (e.g., JAL), and shouldn't store results.
     */
    assign execute_unit_readys = {EXECUTION_LANES{1'b1}};


    /**
     * Commit port: assumes that the register file is always able to recieve commits
     */
    assign commit_valid =
        // to check whether stores are ready, we have to ask the SB
        completed[head]
        // TODO: should we commit on a flush?
        && ~flush
        // TODO: is this check necessary, since ready[head] shouldn't be high?
        && (head != tail)
        // on branches & jumps, check if the fetch unit is free
        && ((op_types[head] == OP_JAL || op_types[head] == OP_JALR || op_types[head] == OP_BRANCH) ? fetch_update_ready : 1)
        // on stores, check if the SB is free
        && (op_types[head] == OP_STORE ? store_commit_ready : 1);

    assign commit_dest_reg     = (op_types[head] != OP_STORE && op_types[head] != OP_BRANCH) ? dest_regs[head] : 0;
    assign commit_value        = values   [head];
    assign commit_ROB_index    = head;
    assign commit_ready        = (op_types[head] != OP_STORE) || (op_types[head] == OP_STORE && store_commit_ready);
    assign store_commit_valid  = commit_valid && op_types[head] == OP_STORE;
    assign commit_PC           = PCs      [head];
    assign commit_opcode       = op_types [head];

    wire mispred;
    wire correct_pred;

    assign mispred = (((op_types[head] == OP_JALR | op_types[head] == OP_JAL) &  ((PCs[head+1'b1] != imms[head]) | (head+1'b1 == tail)))                                          |
                      ((op_types[head] == OP_BRANCH)                          &  ((PCs[head+1'b1] != imms[head]) | (head+1'b1 == tail))                      &&  values[head][0]) |
                      ((op_types[head] == OP_BRANCH)                          &  ((PCs[head+1'b1] == imms[head]) | (head+1'b1 == tail))                      && ~values[head][0]));

    assign correct_pred = ~mispred;

    /**
     * Commit port
     */
    always @ (posedge clock) begin
        if (reset || flush ) begin
            flush                             <= 1'b0;
            fetch_update_data                 <= 0;
            num_mispred                       <= 1'b0;
            num_correctpred                   <= 1'b0;
            jal_num_total                     <= 1'b0;
        end
        else begin
            if (commit_valid && commit_ready) begin
                case (op_types[head])
                    OP_JAL,
                    OP_JALR: begin
                        flush                 <= mispred;
                        fetch_update_data     <= {1'b1, PCs[head], imms[head], 1'b0,            1'b0, update_btb[head]};
                        num_mispred           <= mispred;
                        num_correctpred       <= correct_pred;
                        jal_num_total         <= (op_types[head] == OP_JAL);
                    end
                    OP_BRANCH: begin
                        flush                 <= mispred;
                        fetch_update_data     <= {1'b1, PCs[head], imms[head], 1'b1, values[head][0], update_btb[head]};
                        num_mispred           <= mispred;
                        num_correctpred       <= correct_pred;
                        jal_num_total         <= 1'b0;
                    end
                    OP_STORE: begin
                        if (store_commit_ready && store_commit_valid && store_commit_hazard) begin
                          flush               <= 1'b1;
                          fetch_update_data   <= {1'b0, PCs[head], imms[head], 6'b0};
                          num_mispred         <= 1'b0;
                          num_correctpred     <= 1'b0;
                          jal_num_total       <= 1'b0;
                        end else begin
                          flush               <= 1'b0;
                          fetch_update_data   <= 0;
                          num_mispred         <= 1'b0;
                          num_correctpred     <= 1'b0;
                          jal_num_total       <= 1'b0;
                        end
                    end
                    default: begin
                        flush                 <= 1'b0;
                        fetch_update_data     <= 0;
                        num_mispred           <= 1'b0;
                        num_correctpred       <= 1'b0;
                        jal_num_total         <= 1'b0;
                    end
                endcase
            end else begin
                flush                         <= 1'b0;
                fetch_update_data             <= 0;
                num_mispred                   <= 1'b0;
                num_correctpred               <= 1'b0;
                jal_num_total                 <= 1'b0;
            end
        end
    end

    assign fetch_update_valid = flush;

endmodule
