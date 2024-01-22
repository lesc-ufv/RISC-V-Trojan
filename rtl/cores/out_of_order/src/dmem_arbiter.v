/** @module : dmem_arbiter
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
 * Since the memory subsystem can only service one request per cycle (either load
 * or store), we need an arbiter to choose between sending out stores and loads
 * when both are available. Right now, this module always prefers loads over stores.
 * The logic here is that we are trying to minimize load latency, and we can forward
 * stores. The system would hovewer need to stall in the case the store buffer gets
 * full. This should work by first preventing the issue queue from issuing any more
 * stores, and since it is in-order, no other instructions will leave it either.
 */
module dmem_arbiter #(
    parameter XLEN              = 64,
    parameter LOADS_OVER_STORES = 0 // If 1, when both stores and loads can be sent
                                    // out, loads have precedence.
)(
    // load request port
    output              load_request_ready,
    input               load_request_valid,
    input [XLEN   -1:0] load_request_address,
    // load response port
    input               load_response_ready,
    output              load_response_valid,
    output [XLEN  -1:0] load_response_address,
    output [XLEN  -1:0] load_response_value,
    // store request port
    output              store_request_ready,
    input               store_request_valid,
    input [XLEN   -1:0] store_request_address,
    input [XLEN   -1:0] store_request_value,
    input [XLEN/8 -1:0] store_request_byte_en,
    //memory stage interface
    output              memory_read,        // high if CPU is sending out a load
    output              memory_write,       // high if CPU is sending out a store
    output [XLEN/8-1:0] memory_byte_en,     // specifies which bytes we are writting, one bit / byte
    output [XLEN  -1:0] memory_address_out, // load or store address
    output [XLEN  -1:0] memory_data_out,    // store data sent to memory
    input  [XLEN  -1:0] memory_data_in,     // data of the load request coming in from memory
    input  [XLEN  -1:0] memory_address_in,  // address of the load request coming in from memory
    input               memory_valid,       // validity of the load request - the CPU must be able to accept this!
    input               memory_ready        // readyness of the memory to accept new stores or loads
);

    /*
     * To the CPU
     */
    // Depending on LOADS_OVER_STORES parameter, will either prioritize loads or stores
    // when both can be sent out to memory. Prioritized loads help improve IPC, but make
    // precise interrupts more difficult because of a possible backlog of stores in SB.
    assign load_request_ready  = LOADS_OVER_STORES ? memory_ready
                                                   : memory_ready && ~store_request_valid;
    assign store_request_ready = LOADS_OVER_STORES ? memory_ready && ~load_request_valid
                                                   : memory_ready;
    // Note: the memory assumes that the CPU can ALWAYS accept load responses.
    // There is no clean way of handling it, so we just accept this requirement and
    // propagate it up the stack
    assign load_response_valid = memory_valid;
    // Load address and value
    assign load_response_address = memory_address_in;
    assign load_response_value = memory_data_in;

    /*
     * To the cache
     */
    assign memory_read        = memory_ready && LOADS_OVER_STORES ?  load_request_valid
                                                                  :  load_request_valid && ~store_request_valid;
    assign memory_write       = memory_ready && LOADS_OVER_STORES ? ~load_request_valid && store_request_valid
                                                                  :  store_request_valid;
    assign memory_byte_en     = store_request_byte_en;
    assign memory_address_out = memory_read ? load_request_address : store_request_address;
    assign memory_data_out    = store_request_value;

endmodule
