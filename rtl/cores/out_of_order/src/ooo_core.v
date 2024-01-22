/** @module : ooo_core
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

module ooo_core #(
    parameter XLEN                 = 64,
              REG_INDEX_WIDTH      = 5,
              ROB_INDEX_WIDTH      = 5,
              IQ_ADDR_WIDTH        = 5,
              RS_SLOTS_INDEX_WIDTH = 5,
              SB_INDEX_WIDTH       = 4,
              LB_INDEX_WIDTH       = 4,
              ASID_BITS            = XLEN == 32 ? 4  : 16,
              PPN_BITS             = XLEN == 32 ? 22 : 44,
              SATP_MODE_BITS       = XLEN == 32 ? 1  : 4
) (
    input clock,
    input reset,
    // Fetch port to memory
    input                       fetch_request_ready,
    output                      fetch_request_valid,
    output [XLEN          -1:0] fetch_request_PC,
    // Fetch port from memory
    input                       fetch_response_valid,
    output                      fetch_response_ready,
    input  [XLEN          -1:0] fetch_response_instruction,
    input  [XLEN          -1:0] fetch_response_PC,
    // To the data memory interface
    output                      memory_read,
    output                      memory_write,
    output [XLEN/8        -1:0] memory_byte_en,
    output [XLEN          -1:0] memory_address_out,
    output [XLEN          -1:0] memory_data_out,
    input  [XLEN          -1:0] memory_data_in,
    input  [XLEN          -1:0] memory_address_in,
    input                       memory_valid,
    input                       memory_ready,
    input                       memory_SC_successful,
    output                      memory_atomic,
    // Exception/Interrupt Trap Signals
    input                       m_ext_interrupt,
    input                       s_ext_interrupt,
    input                       software_interrupt,
    input                       timer_interrupt,
    input                       i_mem_page_fault,
    input                       i_mem_access_fault,
    input                       d_mem_page_fault,
    input                       d_mem_access_fault,
    // Privilege CSRs for Virtual Memory
    output [PPN_BITS      -1:0] PT_base_PPN, // from satp register
    output [ASID_BITS     -1:0] ASID,        // from satp register
    output [1               :0] priv,        // current privilege level
    output [1               :0] MPP,         // from mstatus register
    output [SATP_MODE_BITS-1:0] MODE,        // paging mode
    output                      SUM,         // permit Supervisor User Memory access
    output                      MXR,         // Make eXecutable Readable
    output                      MPRV,        // Modify PRiVilege
    // TLB invalidate signals from sfence.vma
    output                      tlb_invalidate,
    output [1:0]                tlb_invalidate_mode,
    //scan signal
    input                       scan
);

    localparam DECODED_INSTR_WIDTH  = 6; // Width of decoded instructions sent to ALU / LB / SB / M_EXT
    localparam EXECUTION_LANES      = 4; // Integer, load, store and M-ext. Latter we'll add FP
    localparam LANE_INDEX_WIDTH     = 2; // log2(EXECUTION_LANES)
    localparam FULL_DECODE_WIDTH = 5                   // source register 1 index
                                 + 5                   // source register 2 index
                                 + XLEN                // immediate
                                 + 5                   // destination register index
                                 + XLEN                // PC
                                 + 1                   // source register 1 selection
                                 + 1                   // source register 2 selection
                                 + DECODED_INSTR_WIDTH // ALU op
                                 + 3                   // op type
                                 + LANE_INDEX_WIDTH    // assigned lane
                                 + 1;                  // NLP BTB hit bit

    localparam NLP_UPDATE = 1    +  // update_valid : High if valid (incase of JAL/JALR/BRANCH)
                            XLEN +  // update_instruction_PC : value of the instruction that caused update
                            XLEN +  // Target address of the branch/Jump instruction
                            1    +  // update_is branch : If the update is a branch
                            1    +  // update_branch_taken : If the branch is taken
                            1    +  // update_rs1_is_link : rs1 register is x1 or x5
                            1    +  // update_rd_is_link  : rd  register is x1 or x5
                            1    +  // update_rs1_is_rd   : rs1 =rd and they are link
                            1;      // If there was a BTB hit already

    // One forward port / lane minus the store lane, plus two for the two ROB forward ports
    localparam FORWARD_BUSSES = EXECUTION_LANES - 1 + 2;
    // ROB recieves all lanes except the store lane
    localparam ROB_INPUT_LANES = EXECUTION_LANES - 1;

    /*
     * CSR and TLB bits, zeroed out for now
     */
    assign PT_base_PPN         = 0;
    assign ASID                = 0;
    assign priv                = 0;
    assign MPP                 = 0;
    assign MODE                = 0;
    assign SUM                 = 0;
    assign MXR                 = 0;
    assign MPRV                = 0;
    assign tlb_invalidate      = 0;
    assign tlb_invalidate_mode = 0;

    wire                           flush;

    /*
     * Fetch issue stage & wires
     */
    wire                  ROB_fetch_update_valid;
    wire                  ROB_fetch_update_ready;
    wire [NLP_UPDATE-1:0] ROB_fetch_update_data;

    wire                  fetch_issue_valid;       // High if FI wants to send out a request to I-cache
    wire                  fetch_issue_ready;       // High if FR has slots to accept a new PC
    wire [XLEN-1:0]       fetch_issue_PC;          // PC of the I-cache request
    wire                  fetch_issue_NLP_BTB_hit; // High if there was a BTB hit in FI

    fetch_issue_ooo #(
        .XLEN                    (XLEN                    ),
        .NLP_UPDATE              (NLP_UPDATE              )
    ) FI (
        .clock                   (clock                   ),
        .reset                   (reset                   ),
        // Fetch request port
        .fetch_request_ready     (fetch_request_ready     ),
        .fetch_request_valid     (fetch_request_valid     ),
        .fetch_request_PC        (fetch_request_PC        ),
        .fetch_issue_NLP_BTB_hit (fetch_issue_NLP_BTB_hit ), // PC of the I-cache request
        // Fetch request to fetch receive port
        .fetch_issue_valid       (fetch_issue_valid       ), // High if FI wants to send out a request to I-cache
        .fetch_issue_ready       (fetch_issue_ready       ), // High if FR has slots to accept a new PC
        .fetch_issue_PC          (fetch_issue_PC          ), // PC of the I-cache request
        // PC update port
        .fetch_update_valid      (ROB_fetch_update_valid  ),
        .fetch_update_ready      (ROB_fetch_update_ready  ),
        .fetch_update_data       (ROB_fetch_update_data   )
    );


    /*
     * Fetch receive stage
     */
    wire            decode_issue_valid;         // High if has an instruction for decode
    wire            decode_issue_ready;         // High if decode is ready to accept an instruction
    wire [31    :0] decode_issue_instruction;   // Instruction to be decoded
    wire [XLEN-1:0] decode_issue_PC;            // PC of the instruction
    wire            decode_issue_NLP_BTB_hit;   // If there was a BTB hit in fetch issue

    fetch_receive_ooo #(
        .XLEN                       (XLEN                       ),
        .SLOT_WIDTH                 (3                          )
    ) FR (
        .clock                      (clock                      ),
        .reset                      (reset                      ),
        // Fetch issue port
        .fetch_issue_valid          (fetch_issue_valid          ), // High if FI wants to send out a request to I-cache
        .fetch_issue_ready          (fetch_issue_ready          ), // High if FR has slots to accept a new PC
        .fetch_issue_PC             (fetch_issue_PC             ), // PC of the I-cache request
        .fetch_issue_NLP_BTB_hit    (fetch_issue_NLP_BTB_hit    ), // PC of the I-cache request
        // I-cache fetch receive port
        .fetch_response_valid       (fetch_response_valid       ), // High if I-cache responding
        .fetch_response_ready       (fetch_response_ready       ), // High if FR ready to accept response
        .fetch_response_instruction (fetch_response_instruction ), // Instruction from I-cache
        .fetch_response_PC          (fetch_response_PC          ), // PC of the response
        // Decode port
        .decode_issue_valid         (decode_issue_valid         ), // High if has an instruction for decode
        .decode_issue_ready         (decode_issue_ready         ), // High if decode is ready to accept an instruction
        .decode_issue_instruction   (decode_issue_instruction   ), // Instruction to be decoded
        .decode_issue_PC            (decode_issue_PC            ), // PC of the instruction
        .decode_issue_NLP_BTB_hit   (decode_issue_NLP_BTB_hit   ), // PC of the instruction
        // Flush port port
        .flush                      (flush                      )  // High if FR should disregard all outstanding requests
    );


    /**
     * Decode stage & wires
     */
    wire                         DS_decode_valid;
    wire                         DS_decode_ready;
    wire [FULL_DECODE_WIDTH-1:0] DS_decode_instruction;

    decode_stage64 #(
        .XLEN                      (XLEN                    ),
        .LANE_INDEX_WIDTH          (LANE_INDEX_WIDTH        ),
        .FULL_DECODE_WIDTH         (FULL_DECODE_WIDTH       )
    ) DS (
        .fetch_response_valid_i      (decode_issue_valid      ),
        .fetch_response_ready_o      (decode_issue_ready      ),
        .fetch_response_instruction_i(decode_issue_instruction),
        .fetch_response_PC_i         (decode_issue_PC         ),
        .fetch_NLP_BTB_hit_i         (decode_issue_NLP_BTB_hit),
        .decode_valid_o              (DS_decode_valid         ),
        .decode_ready_i              (DS_decode_ready         ),
        .decode_instruction_o        (DS_decode_instruction   )
    );


    /**
     * Issue stage and wires
     */
    // Commit port, ROB -> issue stage
    wire                           ROB_commit_valid;
    wire [REG_INDEX_WIDTH    -1:0] ROB_commit_dest_reg_index;
    wire [XLEN               -1:0] ROB_commit_data;
    wire [ROB_INDEX_WIDTH    -1:0] ROB_commit_ROB_index;
    // Store commit port
    wire                           ROB_store_commit_valid;
    wire                           ROB_store_commit_ready;
    wire [XLEN               -1:0] SB_store_commit_address;
    // Issue port, issue stage -> reservation stations
    wire                           IS_issue_lane_0_ready,               IS_issue_lane_1_ready,               IS_issue_lane_2_ready,               IS_issue_lane_3_ready;
    wire                           IS_issue_lane_0_valid,               IS_issue_lane_1_valid,               IS_issue_lane_2_valid,               IS_issue_lane_3_valid;
    wire [DECODED_INSTR_WIDTH-1:0] IS_issue_lane_0_decoded_instruction, IS_issue_lane_1_decoded_instruction, IS_issue_lane_2_decoded_instruction, IS_issue_lane_3_decoded_instruction;
    wire [XLEN               -1:0] IS_issue_lane_0_rs1_data_or_ROB,     IS_issue_lane_1_rs1_data_or_ROB,     IS_issue_lane_2_rs1_data_or_ROB,     IS_issue_lane_3_rs1_data_or_ROB;
    wire                           IS_issue_lane_0_rs1_is_renamed,      IS_issue_lane_1_rs1_is_renamed,      IS_issue_lane_2_rs1_is_renamed,      IS_issue_lane_3_rs1_is_renamed;
    wire [XLEN               -1:0] IS_issue_lane_0_rs2_data_or_ROB,     IS_issue_lane_1_rs2_data_or_ROB,     IS_issue_lane_2_rs2_data_or_ROB,     IS_issue_lane_3_rs2_data_or_ROB;
    wire                           IS_issue_lane_0_rs2_is_renamed,      IS_issue_lane_1_rs2_is_renamed,      IS_issue_lane_2_rs2_is_renamed,      IS_issue_lane_3_rs2_is_renamed;
    wire [XLEN               -1:0] IS_issue_lane_0_address,             IS_issue_lane_1_address,             IS_issue_lane_2_address,             IS_issue_lane_3_address;
    wire [XLEN               -1:0] IS_issue_lane_0_PC,                  IS_issue_lane_1_PC,                  IS_issue_lane_2_PC,                  IS_issue_lane_3_PC;
    // Forward request port; issue stage -> ROB
    wire [ROB_INDEX_WIDTH    -1:0] forward_request_ROB_index_1;
    wire                           forward_request_ROB_valid_1;
    wire [ROB_INDEX_WIDTH    -1:0] forward_request_ROB_index_2;
    wire                           forward_request_ROB_valid_2;
    // Issue ROB port
    wire                           IS_issue_ROB_ready;
    wire                           IS_issue_ROB_valid;
    wire [REG_INDEX_WIDTH    -1:0] IS_issue_ROB_dest_reg_index;
    wire [2                    :0] IS_issue_ROB_op_type;
    wire [XLEN               -1:0] IS_issue_ROB_imm;
    wire [XLEN               -1:0] IS_issue_ROB_PC;
    wire [ROB_INDEX_WIDTH    -1:0] IS_issue_ROB_index;
    wire                           IS_issue_ROB_update_rs1_is_link;
    wire                           IS_issue_ROB_update_rd_is_link;
    wire                           IS_issue_ROB_update_rs1_is_rd;
    wire                           IS_issue_ROB_update_BTB_hit;
    // Issue store buffer port
    wire                           issue_SB_ready;
    wire                           issue_SB_valid;
    wire [SB_INDEX_WIDTH     -1:0] issue_SB_tail;
    wire [XLEN               -1:0] issue_SB_PC;
    // Issue load buffer port
    wire                           IS_issue_LB_ready;
    wire                           IS_issue_LB_valid;
    wire [XLEN               -1:0] IS_issue_LB_PC;

    issue_stage #(
        .XLEN                              (XLEN                                                                                                                                                ),
        .IQ_ADDR_WIDTH                     (IQ_ADDR_WIDTH                                                                                                                                       ),
        .DECODED_INSTR_WIDTH               (6                                                                                                                                                   ),
        .ROB_INDEX_WIDTH                   (ROB_INDEX_WIDTH                                                                                                                                     ),
        .EXECUTION_LANES                   (EXECUTION_LANES                                                                                                                                     ),
        .LANE_INDEX_WIDTH                  (LANE_INDEX_WIDTH                                                                                                                                    ),
        .FULL_DECODE_WIDTH                 (FULL_DECODE_WIDTH                                                                                                                                   )
    ) IS (
        .clock                             (clock                                                                                                                                               ),
        .reset                             (reset                                                                                                                                               ),
        .decode_valid                      (DS_decode_valid                                                                                                                                     ),
        .decode_ready                      (DS_decode_ready                                                                                                                                     ),
        .decode_data                       (DS_decode_instruction                                                                                                                               ),
        .commit_valid                      (ROB_commit_valid                                                                                                                                    ),
        .commit_dest_reg_index             (ROB_commit_dest_reg_index                                                                                                                           ),
        .commit_data                       (ROB_commit_data                                                                                                                                     ),
        .commit_ROB_index                  (ROB_commit_ROB_index                                                                                                                                ),
        .issue_RS_demux_ready              ({IS_issue_lane_3_ready,               IS_issue_lane_2_ready,               IS_issue_lane_1_ready,               IS_issue_lane_0_ready              }),
        .issue_RS_demux_valid              ({IS_issue_lane_3_valid,               IS_issue_lane_2_valid,               IS_issue_lane_1_valid,               IS_issue_lane_0_valid              }),
        .issue_RS_demux_decoded_instruction({IS_issue_lane_3_decoded_instruction, IS_issue_lane_2_decoded_instruction, IS_issue_lane_1_decoded_instruction, IS_issue_lane_0_decoded_instruction}),
        .issue_RS_demux_rs1_data_or_ROB    ({IS_issue_lane_3_rs1_data_or_ROB,     IS_issue_lane_2_rs1_data_or_ROB,     IS_issue_lane_1_rs1_data_or_ROB,     IS_issue_lane_0_rs1_data_or_ROB    }),
        .issue_RS_demux_rs1_is_renamed     ({IS_issue_lane_3_rs1_is_renamed,      IS_issue_lane_2_rs1_is_renamed,      IS_issue_lane_1_rs1_is_renamed,      IS_issue_lane_0_rs1_is_renamed     }),
        .issue_RS_demux_rs2_data_or_ROB    ({IS_issue_lane_3_rs2_data_or_ROB,     IS_issue_lane_2_rs2_data_or_ROB,     IS_issue_lane_1_rs2_data_or_ROB,     IS_issue_lane_0_rs2_data_or_ROB    }),
        .issue_RS_demux_rs2_is_renamed     ({IS_issue_lane_3_rs2_is_renamed,      IS_issue_lane_2_rs2_is_renamed,      IS_issue_lane_1_rs2_is_renamed,      IS_issue_lane_0_rs2_is_renamed     }),
        .issue_RS_demux_address            ({IS_issue_lane_3_address,             IS_issue_lane_2_address,             IS_issue_lane_1_address,             IS_issue_lane_0_address            }),
`ifdef TEST
        .issue_RS_demux_PC                 ({IS_issue_lane_3_PC,                  IS_issue_lane_2_PC,                  IS_issue_lane_1_PC,                  IS_issue_lane_0_PC                 }),
`endif
        .forward_request_ROB_index_1       (forward_request_ROB_index_1                                                                                                                         ),
        .forward_request_ROB_valid_1       (forward_request_ROB_valid_1                                                                                                                         ),
        .forward_request_ROB_index_2       (forward_request_ROB_index_2                                                                                                                         ),
        .forward_request_ROB_valid_2       (forward_request_ROB_valid_2                                                                                                                         ),
        .issue_ROB_ready                   (IS_issue_ROB_ready                                                                                                                                  ),
        .issue_ROB_valid                   (IS_issue_ROB_valid                                                                                                                                  ),
        .issue_ROB_dest_reg_index          (IS_issue_ROB_dest_reg_index                                                                                                                         ),
        .issue_ROB_op_type                 (IS_issue_ROB_op_type                                                                                                                                ),
        .issue_ROB_imm                     (IS_issue_ROB_imm                                                                                                                                    ),
        .issue_ROB_PC                      (IS_issue_ROB_PC                                                                                                                                     ),
        .issue_ROB_index                   (IS_issue_ROB_index                                                                                                                                  ),
        .issue_ROB_update_rs1_is_link      (IS_issue_ROB_update_rs1_is_link                                                                                                                     ),
        .issue_ROB_update_rd_is_link       (IS_issue_ROB_update_rd_is_link                                                                                                                      ),
        .issue_ROB_update_rs1_is_rd        (IS_issue_ROB_update_rs1_is_rd                                                                                                                       ),
        .issue_ROB_update_BTB_hit          (IS_issue_ROB_update_BTB_hit                                                                                                                         ),
        .issue_LB_ready                    (IS_issue_LB_ready                                                                                                                                   ),
        .issue_LB_valid                    (IS_issue_LB_valid                                                                                                                                   ),
        .issue_LB_PC                       (IS_issue_LB_PC                                                                                                                                      ),
        .issue_SB_ready                    (issue_SB_ready                                                                                                                                      ),
        .issue_SB_valid                    (issue_SB_valid                                                                                                                                      ),
        .issue_SB_PC                       (issue_SB_PC                                                                                                                                         ),
        .flush                             (flush                                                                                                                                               )
    );


    /*
     * (Multiple) Reservation stations:
     *
     * Issue_RS_demux ports should be split once per reservation station.
     * Since we have just one lane, we can just connect them.
     */

    // RS outputs to the execution lanes
    wire                           ALU_execute_ready,     STORE_AC_execute_ready,     LOAD_AC_execute_ready,     LB_load_execute_ready,     MLU_execute_ready;
    wire                           ALU_execute_valid,     STORE_AC_execute_valid,     LOAD_AC_execute_valid,     LB_load_execute_valid,     MLU_execute_valid;
    wire [ROB_INDEX_WIDTH    -1:0] ALU_execute_ROB_index, STORE_AC_execute_ROB_index, LOAD_AC_execute_ROB_index, LB_load_execute_ROB_index, MLU_execute_ROB_index;
    wire [XLEN               -1:0] ALU_execute_value,     STORE_AC_execute_value,                                LB_load_execute_value,     MLU_execute_value;
    wire [XLEN               -1:0]                        STORE_AC_execute_address,   LOAD_AC_execute_address,   LB_load_execute_address                     ;

    // Response from the ROB to the reservation stations
    wire [1:0]                     forward_response_valids;
    wire [2*ROB_INDEX_WIDTH  -1:0] forward_response_indexes;
    wire [2*XLEN             -1:0] forward_response_values;

    // RS dispatch to execute unit
    wire                           RS_INT_dispatch_ready,               RS_STORE_dispatch_ready,               RS_LOAD_dispatch_ready              , RS_M_EXT_dispatch_ready;
    wire                           RS_INT_dispatch_valid,               RS_STORE_dispatch_valid,               RS_LOAD_dispatch_valid              , RS_M_EXT_dispatch_valid;
    wire [XLEN               -1:0] RS_INT_dispatch_1st_reg,             RS_STORE_dispatch_1st_reg,             RS_LOAD_dispatch_1st_reg            , RS_M_EXT_dispatch_1st_reg;
    wire [XLEN               -1:0] RS_INT_dispatch_2nd_reg,             RS_STORE_dispatch_2nd_reg,             RS_LOAD_dispatch_2nd_reg            , RS_M_EXT_dispatch_2nd_reg;
    wire [DECODED_INSTR_WIDTH-1:0] RS_INT_dispatch_decoded_instruction, RS_STORE_dispatch_decoded_instruction, RS_LOAD_dispatch_decoded_instruction, RS_M_EXT_dispatch_decoded_instruction;
    wire [ROB_INDEX_WIDTH    -1:0] RS_INT_dispatch_ROB_destination,     RS_STORE_dispatch_ROB_destination,     RS_LOAD_dispatch_ROB_destination    , RS_M_EXT_dispatch_ROB_destination;
    wire [XLEN               -1:0]                                      RS_STORE_dispatch_address,             RS_LOAD_dispatch_address;
    wire [XLEN               -1:0] RS_INT_dispatch_PC,                  RS_STORE_dispatch_PC,                  RS_LOAD_dispatch_PC                 , RS_M_EXT_dispatch_PC;

    /*
     * Common data bus (CDB)
     */
    wire [FORWARD_BUSSES-1                :0] CDB_valids      = {MLU_execute_valid,     LB_load_execute_valid,      ALU_execute_valid,     forward_response_valids};
    wire [FORWARD_BUSSES*ROB_INDEX_WIDTH-1:0] CDB_ROB_indexes = {MLU_execute_ROB_index, LB_load_execute_ROB_index,  ALU_execute_ROB_index, forward_response_indexes};
    wire [FORWARD_BUSSES*XLEN           -1:0] CDB_values      = {MLU_execute_value,     LB_load_execute_value,      ALU_execute_value,     forward_response_values };

    reservation_station #(
        .XLEN                        (XLEN                               ),
        .RS_SLOTS_INDEX_WIDTH        (RS_SLOTS_INDEX_WIDTH               ),
        .FORWARD_BUSSES              (FORWARD_BUSSES                     ),
        .ROB_INDEX_WIDTH             (ROB_INDEX_WIDTH                    ),
        .DECODED_INSTR_WIDTH         (DECODED_INSTR_WIDTH                )
    ) RS_INT (
        .clock_i                       (clock                              ),
        .reset_i                       (reset                              ),
        .issue_ready_o                 (IS_issue_lane_0_ready              ),
        .issue_valid_i                 (IS_issue_lane_0_valid              ),
        .issue_decoded_instruction_i   (IS_issue_lane_0_decoded_instruction),
        .issue_rd_ROB_index_i          (IS_issue_ROB_index                 ), // The ROB index is coming from the ROB, not the IS
        .issue_rs1_data_or_ROB_i       (IS_issue_lane_0_rs1_data_or_ROB    ),
        .issue_rs1_is_renamed_i        (IS_issue_lane_0_rs1_is_renamed     ),
        .issue_rs2_data_or_ROB_i       (IS_issue_lane_0_rs2_data_or_ROB    ),
        .issue_rs2_is_renamed_i        (IS_issue_lane_0_rs2_is_renamed     ),
        .issue_address_i               ({XLEN{1'b0}}                       ),
`ifdef TEST
        .issue_PC_i                    (IS_issue_lane_0_PC                 ),
`endif
        .forward_valids_i              (CDB_valids                         ),
        .forward_indexes_i             (CDB_ROB_indexes                    ),
        .forward_values_i              (CDB_values                         ),
        .dispatch_ready_i              (RS_INT_dispatch_ready              ),
        .dispatch_valid_o              (RS_INT_dispatch_valid              ),
        .dispatch_1st_reg_o            (RS_INT_dispatch_1st_reg            ),
        .dispatch_2nd_reg_o            (RS_INT_dispatch_2nd_reg            ),
        .dispatch_address_o            (/* Int lane doesn't use addresses*/),
        .dispatch_decoded_instruction_o(RS_INT_dispatch_decoded_instruction),
        .dispatch_ROB_destination_o    (RS_INT_dispatch_ROB_destination    ),
`ifdef TEST
        .dispatch_PC_o                 (RS_INT_dispatch_PC                 ),
`endif
        .flush_i                       (flush                              )
    );


    reservation_station #(
        .XLEN                        (XLEN                                                     ),
        .RS_SLOTS_INDEX_WIDTH        (RS_SLOTS_INDEX_WIDTH                                     ),
        .FORWARD_BUSSES              (FORWARD_BUSSES                                           ),
        .ROB_INDEX_WIDTH             (ROB_INDEX_WIDTH                                          ),
        .DECODED_INSTR_WIDTH         (DECODED_INSTR_WIDTH                                      )
    ) RS_STORE (
        .clock_i                       (clock                                                    ),
        .reset_i                       (reset                                                    ),
        .issue_ready_o                 (IS_issue_lane_1_ready                                    ),
        .issue_valid_i                 (IS_issue_lane_1_valid                                    ),
        .issue_decoded_instruction_i   (IS_issue_lane_1_decoded_instruction                      ),
        .issue_rd_ROB_index_i          ({{(ROB_INDEX_WIDTH-SB_INDEX_WIDTH){1'b0}}, issue_SB_tail}), // TODO: find a cleaner way to feed SB indexes
        .issue_rs1_data_or_ROB_i       (IS_issue_lane_1_rs1_data_or_ROB                          ),
        .issue_rs1_is_renamed_i        (IS_issue_lane_1_rs1_is_renamed                           ),
        .issue_rs2_data_or_ROB_i       (IS_issue_lane_1_rs2_data_or_ROB                          ),
        .issue_rs2_is_renamed_i        (IS_issue_lane_1_rs2_is_renamed                           ),
        .issue_address_i               (IS_issue_lane_1_address                                  ),
`ifdef TEST
        .issue_PC_i                    (IS_issue_lane_1_PC                                       ),
`endif
        .forward_valids_i              (CDB_valids                                               ),
        .forward_indexes_i             (CDB_ROB_indexes                                          ),
        .forward_values_i              (CDB_values                                               ),
        .dispatch_ready_i              (RS_STORE_dispatch_ready                                  ),
        .dispatch_valid_o              (RS_STORE_dispatch_valid                                  ),
        .dispatch_1st_reg_o            (RS_STORE_dispatch_1st_reg                                ),
        .dispatch_2nd_reg_o            (RS_STORE_dispatch_2nd_reg                                ),
        .dispatch_address_o            (RS_STORE_dispatch_address                                ),
        .dispatch_decoded_instruction_o(RS_STORE_dispatch_decoded_instruction                    ),
        .dispatch_ROB_destination_o    (RS_STORE_dispatch_ROB_destination                        ),
`ifdef TEST
        .dispatch_PC_o                 (),
`endif
        .flush_i                       (flush                                                    )
    );


    reservation_station #(
        .XLEN                        (XLEN                                ),
        .RS_SLOTS_INDEX_WIDTH        (RS_SLOTS_INDEX_WIDTH                ),
        .FORWARD_BUSSES              (FORWARD_BUSSES                      ),
        .ROB_INDEX_WIDTH             (ROB_INDEX_WIDTH                     ),
        .DECODED_INSTR_WIDTH         (DECODED_INSTR_WIDTH                 )
    ) RS_LOAD (
        .clock_i                       (clock                               ),
        .reset_i                       (reset                               ),
        .issue_ready_o                 (IS_issue_lane_2_ready               ),
        .issue_valid_i                 (IS_issue_lane_2_valid               ),
        .issue_decoded_instruction_i   (IS_issue_lane_2_decoded_instruction ),
        .issue_rd_ROB_index_i          (IS_issue_ROB_index                  ),
        .issue_rs1_data_or_ROB_i       (IS_issue_lane_2_rs1_data_or_ROB     ),
        .issue_rs1_is_renamed_i        (IS_issue_lane_2_rs1_is_renamed      ),
        .issue_rs2_data_or_ROB_i       (IS_issue_lane_2_rs2_data_or_ROB     ),
        .issue_rs2_is_renamed_i        (IS_issue_lane_2_rs2_is_renamed      ),
        .issue_address_i               (IS_issue_lane_2_address             ),
`ifdef TEST
        .issue_PC_i                    (IS_issue_lane_2_PC                  ),
`endif
        .forward_valids_i              (CDB_valids                          ),
        .forward_indexes_i             (CDB_ROB_indexes                     ),
        .forward_values_i              (CDB_values                          ),
        .dispatch_ready_i              (RS_LOAD_dispatch_ready              ),
        .dispatch_valid_o              (RS_LOAD_dispatch_valid              ),
        .dispatch_1st_reg_o            (RS_LOAD_dispatch_1st_reg            ),
        .dispatch_2nd_reg_o            (RS_LOAD_dispatch_2nd_reg            ),
        .dispatch_address_o            (RS_LOAD_dispatch_address            ),
        .dispatch_decoded_instruction_o(RS_LOAD_dispatch_decoded_instruction),
        .dispatch_ROB_destination_o    (RS_LOAD_dispatch_ROB_destination    ),
`ifdef TEST
        .dispatch_PC_o                 (),
`endif
        .flush_i                       (flush                               )
    );


    reservation_station #(
        .XLEN                        (XLEN                                 ),
        .RS_SLOTS_INDEX_WIDTH        (RS_SLOTS_INDEX_WIDTH                 ),
        .FORWARD_BUSSES              (FORWARD_BUSSES                       ),
        .ROB_INDEX_WIDTH             (ROB_INDEX_WIDTH                      ),
        .DECODED_INSTR_WIDTH         (DECODED_INSTR_WIDTH                  )
    ) RS_M_EXTENSION (
        .clock_i                       (clock                                ),
        .reset_i                       (reset                                ),
        .issue_ready_o                 (IS_issue_lane_3_ready                ),
        .issue_valid_i                 (IS_issue_lane_3_valid                ),
        .issue_decoded_instruction_i   (IS_issue_lane_3_decoded_instruction  ),
        .issue_rd_ROB_index_i          (IS_issue_ROB_index                   ),
        .issue_rs1_data_or_ROB_i       (IS_issue_lane_3_rs1_data_or_ROB      ),
        .issue_rs1_is_renamed_i        (IS_issue_lane_3_rs1_is_renamed       ),
        .issue_rs2_data_or_ROB_i       (IS_issue_lane_3_rs2_data_or_ROB      ),
        .issue_rs2_is_renamed_i        (IS_issue_lane_3_rs2_is_renamed       ),
        .issue_address_i               (IS_issue_lane_3_address              ),
`ifdef TEST
        .issue_PC_i                    (IS_issue_lane_3_PC                   ),
`endif
        .forward_valids_i              (CDB_valids                           ),
        .forward_indexes_i             (CDB_ROB_indexes                      ),
        .forward_values_i              (CDB_values                           ),
        .dispatch_ready_i              (RS_M_EXT_dispatch_ready              ),
        .dispatch_valid_o              (RS_M_EXT_dispatch_valid              ),
        .dispatch_1st_reg_o            (RS_M_EXT_dispatch_1st_reg            ),
        .dispatch_2nd_reg_o            (RS_M_EXT_dispatch_2nd_reg            ),
        .dispatch_address_o            (/* M_Ext lane doesn't use addresses*/),
        .dispatch_decoded_instruction_o(RS_M_EXT_dispatch_decoded_instruction),
        .dispatch_ROB_destination_o    (RS_M_EXT_dispatch_ROB_destination    ),
`ifdef TEST
        .dispatch_PC_o                 (),
`endif
        .flush_i                       (flush                                )
    );


    /*
     * Execute lanes
     */
    integer_lane #(
        .XLEN                        (XLEN                               ),
        .ROB_INDEX_WIDTH             (ROB_INDEX_WIDTH                    ),
        .DECODED_INSTR_WIDTH         (DECODED_INSTR_WIDTH                )
    ) INT_LANE (
        .clock                       (clock                              ),
        .reset                       (reset                              ),
        .dispatch_ready              (RS_INT_dispatch_ready              ),
        .dispatch_valid              (RS_INT_dispatch_valid              ),
        .dispatch_1st_reg            (RS_INT_dispatch_1st_reg            ),
        .dispatch_2nd_reg            (RS_INT_dispatch_2nd_reg            ),
        .dispatch_decoded_instruction(RS_INT_dispatch_decoded_instruction),
        .dispatch_ROB_index          (RS_INT_dispatch_ROB_destination    ),
`ifdef TEST
        .dispatch_PC_i               (RS_INT_dispatch_PC                 ),
`endif
        .execute_ready               (ALU_execute_ready                  ),
        .execute_valid               (ALU_execute_valid                  ),
        .execute_ROB_index           (ALU_execute_ROB_index              ),
        .execute_value               (ALU_execute_value                  ),
        .flush                       (flush                              )
    );

    m_ext_lane #(
        .XLEN                        (XLEN                               ),
        .ROB_INDEX_WIDTH             (ROB_INDEX_WIDTH                    ),
        .DECODED_INSTR_WIDTH         (DECODED_INSTR_WIDTH                )
    ) M_LANE (
        .clock_i                       (clock                                ),
        .reset_i                       (reset                                ),
        .dispatch_ready_o              (RS_M_EXT_dispatch_ready              ),
        .dispatch_valid_i              (RS_M_EXT_dispatch_valid              ),
        .dispatch_1st_reg_i            (RS_M_EXT_dispatch_1st_reg            ),
        .dispatch_2nd_reg_i            (RS_M_EXT_dispatch_2nd_reg            ),
        .dispatch_decoded_instruction_i(RS_M_EXT_dispatch_decoded_instruction),
        .dispatch_ROB_index_i          (RS_M_EXT_dispatch_ROB_destination    ),
        .execute_ready_i               (MLU_execute_ready                    ),
        .execute_valid_o               (MLU_execute_valid                    ),
        .execute_ROB_index_o           (MLU_execute_ROB_index                ),
        .execute_value_o               (MLU_execute_value                    ),
        .flush_i                       (flush                                )
    );

    address_calculator #(
        .XLEN                        (XLEN                                 ),
        .ROB_INDEX_WIDTH             (ROB_INDEX_WIDTH                      )
    ) STORE_AC (
        .clock                       (clock                                ),
        .reset                       (reset                                ),
        .dispatch_ready              (RS_STORE_dispatch_ready              ),
        .dispatch_valid              (RS_STORE_dispatch_valid              ),
        .dispatch_1st_reg            (RS_STORE_dispatch_1st_reg            ),
        .dispatch_2nd_reg            (RS_STORE_dispatch_2nd_reg            ),
        .dispatch_address            (RS_STORE_dispatch_address            ),
        .dispatch_ROB_index          (RS_STORE_dispatch_ROB_destination    ),
        .execute_ready               (STORE_AC_execute_ready               ),
        .execute_valid               (STORE_AC_execute_valid               ),
        .execute_ROB_index           (STORE_AC_execute_ROB_index           ),
        .execute_value               (STORE_AC_execute_value               ),
        .execute_address             (STORE_AC_execute_address             ),
        .flush                       (flush                                )
    );


    address_calculator #(
        .XLEN                        (XLEN                                ),
        .ROB_INDEX_WIDTH             (ROB_INDEX_WIDTH                     )
    ) LOAD_AC (
        .clock                       (clock                               ),
        .reset                       (reset                               ),
        .dispatch_ready              (RS_LOAD_dispatch_ready              ),
        .dispatch_valid              (RS_LOAD_dispatch_valid              ),
        .dispatch_1st_reg            (RS_LOAD_dispatch_1st_reg            ),
        .dispatch_2nd_reg            (RS_LOAD_dispatch_2nd_reg            ),
        .dispatch_address            (RS_LOAD_dispatch_address            ),
        .dispatch_ROB_index          (RS_LOAD_dispatch_ROB_destination    ),
        .execute_ready               (LOAD_AC_execute_ready               ),
        .execute_valid               (LOAD_AC_execute_valid               ),
        .execute_ROB_index           (LOAD_AC_execute_ROB_index           ),
        .execute_value               (                                    ),
        .execute_address             (LOAD_AC_execute_address             ),
        .flush                       (flush                               )
    );


    // load request port
    wire              LB_load_request_ready;
    wire              LB_load_request_valid;
    wire [XLEN  -1:0] LB_load_request_address;
    // load response port
    wire              DMEM_load_response_ready;
    wire              DMEM_load_response_valid;
    wire [XLEN  -1:0] DMEM_load_response_address;
    wire [XLEN  -1:0] DMEM_load_response_value;
    // store request port
    wire              SB_store_request_ready;
    wire              SB_store_request_valid;
    wire [XLEN  -1:0] SB_store_request_address;
    wire [XLEN  -1:0] SB_store_request_value;
    wire [XLEN/8-1:0] SB_store_request_byte_en;

    wire              LB_store_commit_hazard;


    dmem_arbiter #(
        .XLEN                 (XLEN                      ),
        .LOADS_OVER_STORES    (1                         ) // 0=stores have priority, 1=loads
    ) DMEM_ARBITER (
        .load_request_ready   (LB_load_request_ready     ),
        .load_request_valid   (LB_load_request_valid     ),
        .load_request_address (LB_load_request_address   ),
        .load_response_ready  (DMEM_load_response_ready  ),
        .load_response_valid  (DMEM_load_response_valid  ),
        .load_response_address(DMEM_load_response_address),
        .load_response_value  (DMEM_load_response_value  ),
        .store_request_ready  (SB_store_request_ready    ),
        .store_request_valid  (SB_store_request_valid    ),
        .store_request_address(SB_store_request_address  ),
        .store_request_value  (SB_store_request_value    ),
        .store_request_byte_en(SB_store_request_byte_en  ),
        //memory stage interface
        .memory_read          (memory_read               ),
        .memory_write         (memory_write              ),
        .memory_byte_en       (memory_byte_en            ),
        .memory_address_out   (memory_address_out        ),
        .memory_data_out      (memory_data_out           ),
        .memory_data_in       (memory_data_in            ),
        .memory_address_in    (memory_address_in         ),
        .memory_valid         (memory_valid              ),
        .memory_ready         (memory_ready              )
    );


    store_buffer #(
        .XLEN                 (XLEN                                          ),
        .SB_INDEX_WIDTH       (SB_INDEX_WIDTH                                ),
        .ROB_INDEX_WIDTH      (ROB_INDEX_WIDTH                               )
    ) SB (
        .clock                    (clock                                         ),
        .reset                    (reset                                         ),
        .flush                    (flush                                         ),
        .ROB_head                 (ROB_commit_ROB_index                          ),
        .issue_SB_ready           (issue_SB_ready                                ), // TODO: rename issue_SB to store_issue
        .issue_SB_valid           (issue_SB_valid                                ),
        .issue_SB_tail            (issue_SB_tail                                 ), // TODO: feed this to stores instead of the ROB index
        .issue_SB_PC              (issue_SB_PC                                   ),
        .issue_decoded_instruction(IS_issue_lane_1_decoded_instruction           ),
        .execute_valid            (STORE_AC_execute_valid                        ),
        .execute_ready            (STORE_AC_execute_ready                        ),
        .execute_SB_tail          (STORE_AC_execute_ROB_index[SB_INDEX_WIDTH-1:0]), // TODO: replace this with the SB index
        .execute_value            (STORE_AC_execute_value                        ),
        .execute_address          (STORE_AC_execute_address                      ),
        .store_commit_ready       (ROB_store_commit_ready                        ),
        .store_commit_valid       (ROB_store_commit_valid                        ),
        .store_commit_address     (SB_store_commit_address                       ),
        .store_request_ready      (SB_store_request_ready                        ),
        .store_request_valid      (SB_store_request_valid                        ),
        .store_request_address    (SB_store_request_address                      ),
        .store_request_value      (SB_store_request_value                        ),
        .store_request_byte_en    (SB_store_request_byte_en                      )
    );


    load_buffer #(
        .XLEN                     (XLEN                      ),
        .ROB_INDEX_WIDTH          (ROB_INDEX_WIDTH           ),
        .LB_INDEX_WIDTH           (LB_INDEX_WIDTH            ),
        .DECODED_INSTR_WIDTH      (DECODED_INSTR_WIDTH       )
    ) LB (
        .clock                              (clock                                           ),
        .reset                              (reset                                           ),
        .flush                              (flush                                           ),
        .issue_ready                        (IS_issue_LB_ready                               ),
        .issue_valid                        (IS_issue_LB_valid                               ),
        .issue_ROB_index                    (IS_issue_ROB_index                              ),
        .issue_decoded_instruction          (IS_issue_lane_2_decoded_instruction             ),
        .address_receive_ready              (LOAD_AC_execute_ready                           ),
        .address_receive_valid              (LOAD_AC_execute_valid                           ),
        .address_receive_ROB_index          (LOAD_AC_execute_ROB_index                       ),
        .address_receive_address            (LOAD_AC_execute_address                         ),
        .load_request_ready                 (LB_load_request_ready                           ),
        .load_request_valid                 (LB_load_request_valid                           ),
        .load_request_address               (LB_load_request_address                         ),
        .load_response_ready                (DMEM_load_response_ready                        ),
        .load_response_valid                (DMEM_load_response_valid                        ),
        .load_response_address              (DMEM_load_response_address                      ),
        .load_response_value                (DMEM_load_response_value                        ),
        .ROB_accept_ready                   (LB_load_execute_ready                           ),
        .ROB_accept_valid                   (LB_load_execute_valid                           ),
        .ROB_accept_value                   (LB_load_execute_value                           ),
        .ROB_accept_ROB_index               (LB_load_execute_ROB_index                       ),
        .commit_ready                       (                                                ), // Later, we should have the ROB listen to this
        .commit_valid                       (ROB_commit_valid                                ),
        .commit_ROB_index                   (ROB_commit_ROB_index                            ),
        .store_commit_valid                 (ROB_store_commit_ready && ROB_store_commit_valid),
        .store_commit_address               (SB_store_commit_address                         ),
        .store_commit_hazard                (LB_store_commit_hazard                          )
    );


    /*
     * Re-order Buffer
     */
    reorder_buffer #(
        .XLEN                         (XLEN                                                                     ),
        .REG_INDEX_WIDTH              (REG_INDEX_WIDTH                                                          ),
        .ROB_INDEX_WIDTH              (ROB_INDEX_WIDTH                                                          ),
        .SB_INDEX_WIDTH               (SB_INDEX_WIDTH                                                           ),
        .EXECUTION_LANES              (ROB_INPUT_LANES                                                          ),
        .NLP_UPDATE                   (NLP_UPDATE                                                               )
    ) ROB (
        .clock                        (clock                                                                    ),
        .reset                        (reset                                                                    ),
        .flush                        (flush                                                                    ),
        // Issue port
        .issue_ROB_ready              (IS_issue_ROB_ready                                                       ),
        .issue_ROB_valid              (IS_issue_ROB_valid                                                       ),
        .issue_ROB_dest_reg_index     (IS_issue_ROB_dest_reg_index                                              ),
        .issue_ROB_op_type            (IS_issue_ROB_op_type                                                     ),
        .issue_ROB_imm                (IS_issue_ROB_imm                                                         ),
        .issue_ROB_PC                 (IS_issue_ROB_PC                                                          ),
        .issue_ROB_index              (IS_issue_ROB_index                                                       ),
        .issue_ROB_update_rs1_is_link (IS_issue_ROB_update_rs1_is_link                                          ),  // high if rs1 register is x1 or x5
        .issue_ROB_update_rd_is_link  (IS_issue_ROB_update_rd_is_link                                           ),  // high if rd register is x1 or x5
        .issue_ROB_update_rs1_is_rd   (IS_issue_ROB_update_rs1_is_rd                                            ),  // high if rd register is x1 or x5
        .issue_ROB_update_BTB_hit     (IS_issue_ROB_update_BTB_hit                                              ),
        // ROB forward request port
        .forward_request_ROB_index_1  (forward_request_ROB_index_1                                              ),
        .forward_request_ROB_index_2  (forward_request_ROB_index_2                                              ),
        .forward_request_ROB_valid_1  (forward_request_ROB_valid_1                                              ),
        .forward_request_ROB_valid_2  (forward_request_ROB_valid_2                                              ),
        // ROB forward response port
        .forward_response_valids      (forward_response_valids                                                  ),
        .forward_response_indexes     (forward_response_indexes                                                 ),
        .forward_response_values      (forward_response_values                                                  ),
        // Execute unit ports
        .execute_unit_readys          ({MLU_execute_ready,     LB_load_execute_ready,     ALU_execute_ready    }),
        .execute_unit_valids          ({MLU_execute_valid,     LB_load_execute_valid,     ALU_execute_valid    }),
        .execute_unit_indexes         ({MLU_execute_ROB_index, LB_load_execute_ROB_index, ALU_execute_ROB_index}),
        .execute_unit_values          ({MLU_execute_value,     LB_load_execute_value,     ALU_execute_value    }),
        // Commit port
        .commit_valid                 (ROB_commit_valid                                                         ),
        .commit_dest_reg              (ROB_commit_dest_reg_index                                                ),
        .commit_value                 (ROB_commit_data                                                          ),
        .commit_ROB_index             (ROB_commit_ROB_index                                                     ),
        // Store buffer commit port
        .store_commit_ready           (ROB_store_commit_ready                                                   ), // ROB tells the SB that a store committed,
        .store_commit_valid           (ROB_store_commit_valid                                                   ), // SB tells the LB which address got committed,
        .store_commit_hazard          (LB_store_commit_hazard                                                   ), // LB tells ROB if a hazard happened, ROB raises flush
        // PC update port
        .fetch_update_valid           (ROB_fetch_update_valid                                                   ),
        .fetch_update_ready           (ROB_fetch_update_ready                                                   ),
        .fetch_update_data            (ROB_fetch_update_data                                                    )
    );


    assign memory_atomic = 1'b0;


// ANSI colors:
// 0 - Black
// 1 - Red
// 2 - Green
// 3 - Brown/yellow
// 4 - Blue
// 5 - Purple
// 6 - Cyan
// 7 - Light grey/white
// 9 - Default


`ifdef TEST
`include "../rtl/cores/out_of_order/functions/decode_function.v"
    always @ (posedge clock) begin
`ifdef PRINTDECODE
        if (DS_decode_ready && DS_decode_valid) begin
            $write("[%t] ", $time);
            $write("\033[0;34m"); // Color the output
            $display("DS -> IS, PC %0h", DS_decode_instruction[77:14]);
            $write("\033[0m");
        end
`endif
`ifdef PRINTISSUE
        if (IS_issue_ROB_ready && IS_issue_ROB_valid) begin
            $write("[%t] ", $time);
            $write("\033[0;33m"); // Color the output
            $display("IS -> RS, PC %0h", IS_issue_ROB_PC);
            $write("\033[0m");
        end
`endif
`ifdef PRINTDISPATCH
        if (RS_INT_dispatch_ready && RS_INT_dispatch_valid) begin
            $write("[%t] ", $time);
            $write("\033[0;32m"); // Color the output
            $write("RS -> EX, PC %0h", RS_INT_dispatch_PC);
            $write("\033[0m");
            $display("   -     %0d, %0d", RS_INT_dispatch_1st_reg, RS_INT_dispatch_2nd_reg);
        end
`endif
`ifdef PRINTCOMMIT
        if (ROB_commit_valid) begin
            $write("[%t] ", $time);
            $write("\033[0;31m"); // Color the output
            $write("ROB-> RF, PC %0h", ROB.PCs[ROB.head]);
            $write("\033[0m");
            if (ROB_commit_dest_reg_index != 0)
                $display("   -    %s (x%01d) <= %0d", num2reg(ROB_commit_dest_reg_index), ROB_commit_dest_reg_index, ROB_commit_data);
            else
                $display("");
        end

        if (flush) begin
            $write("[%t] ", $time);
            $write("\033[0;41m"); // Color the output
            $write("FLUSH");
            $display("\033[0m");
        end
`endif
    end
`endif

endmodule
