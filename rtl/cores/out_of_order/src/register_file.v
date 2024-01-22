/** @module : register_file
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

// Parameterized register file with re-order buffer (ROB) support.
// Aside from the 31 32-bit register that the register file holds, for each register
// it also stores:
//    1. the position in the ROB buffer of the most recent instruction writing to
//       this register. Any instruction that uses this register should instead use
//       the soon-to-be-calculated value at the specified position in the ROB.
//    2. ROB valid flag, specifying if the value stored in the ROB field is valid
//       or not.

module register_file #(
    parameter XLEN            = 32,
    parameter REG_INDEX_WIDTH = 5,
    parameter ROB_INDEX_WIDTH = 8
) (
    input clock,
    input reset,
    input flush,

    // ROB commit port
    input                        commit_enable,
    input  [REG_INDEX_WIDTH-1:0] commit_sel,
    input  [XLEN           -1:0] commit_data,
    input  [ROB_INDEX_WIDTH-1:0] commit_ROB_index,

    // ROB update port (used when a new instruction is issued and only a register's ROB id needs to be updated)
    input                        update_enable,
    input  [REG_INDEX_WIDTH-1:0] update_dest_reg,
    input  [ROB_INDEX_WIDTH-1:0] update_ROB_index,

    // First read port: value + ROB id + ROB valid
    input  [REG_INDEX_WIDTH-1:0] read_sel1,
    output [XLEN           -1:0] read_data1,
    output [ROB_INDEX_WIDTH-1:0] read_ROB1,
    output                       read_ROB1_is_renamed,

    // Second read port: value + ROB id + ROB valid
    input  [REG_INDEX_WIDTH-1:0] read_sel2,
    output [XLEN           -1:0] read_data2,
    output [ROB_INDEX_WIDTH-1:0] read_ROB2,
    output                       read_ROB2_is_renamed
);
    localparam SLOTS = 1<<REG_INDEX_WIDTH;

    // We store the register values along with the ROB ID and the valid flag
    (* ram_style = "distributed" *)
    reg [XLEN           -1:0] register_file [0:SLOTS-1];

    (* ram_style = "distributed" *)
    reg [ROB_INDEX_WIDTH-1:0] ROB           [0:SLOTS-1];

    (* ram_style = "distributed" *)
    reg                       ROB_valid     [0:SLOTS-1];


    integer i;

    always @(posedge clock) begin
        if (reset==1) begin
            register_file[0] <= 0;

            for (i=0; i<(1<<REG_INDEX_WIDTH); i=i+1) begin
                ROB_valid[i] <= 0;
                register_file[i] <= 0;
                ROB[i] <= 0;
            end
        end

        else if (flush)
            for (i=0; i<(1<<REG_INDEX_WIDTH); i=i+1)
                ROB_valid[i] <= 0;

        else begin
            // This is a special case where the commit updates the value, but the new ROB index and valid flag
            // are set by the update logic
            if (commit_enable && update_enable && commit_sel != 0 && commit_sel == update_dest_reg) begin
                //register_file[commit_sel] <= {1'b1, update_ROB_index, commit_data};
                register_file[commit_sel] <= commit_data;
                ROB[commit_sel]           <= update_ROB_index;
                ROB_valid[commit_sel]     <= 1'b1;
            end

            else begin
                // In case of a commit, we should update the value in the register specified by commit_sel,
                // and if the register's ROB index is the same as the commit ROB index, we should set the ROB_valid flag to 0.
                // Otherwise, there is a later instruction also writing to this register, so we should keep the valid high.
                if (commit_enable && commit_sel != 0) begin
                    register_file[commit_sel] <= commit_data;

                    if (ROB[commit_sel] == commit_ROB_index)
                        ROB_valid[commit_sel] <= 0;
                end

                // In case of an update, an instruction is currently being sent to a reservation station and it's
                // destination register is getting replaced by a ROB index. That destination register needs to remember
                // the ROB index so that future instructions can use the ROB index.
                if (update_enable && update_dest_reg != 0) begin
                    //register_file[update_dest_reg][XLEN+ROB_INDEX_WIDTH:XLEN] <= {1'b1, update_ROB_index};
                    ROB[update_dest_reg] <= update_ROB_index;
                    ROB_valid[update_dest_reg] <= 1'b1;
                end
            end
        end
    end


    /*
     * Output wires
     */
    assign read_data1           = read_sel1 == 0 ? 0 : register_file[read_sel1];
    assign read_ROB1            = read_sel1 == 0 ? 0 : ROB          [read_sel1];
    assign read_ROB1_is_renamed = read_sel1 == 0 ? 0 : ROB_valid    [read_sel1];

    assign read_data2           = read_sel2 == 0 ? 0 : register_file[read_sel2];
    assign read_ROB2            = read_sel2 == 0 ? 0 : ROB          [read_sel2];
    assign read_ROB2_is_renamed = read_sel2 == 0 ? 0 : ROB_valid    [read_sel2];

    /**
     * FORMAL:
     * TODO: prove that we will never commit to an register whose valid flag is 0
     *
     */

endmodule
