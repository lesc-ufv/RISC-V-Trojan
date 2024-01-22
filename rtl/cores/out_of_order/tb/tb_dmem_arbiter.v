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

module tb_dmem_arbiter();
parameter XLEN              = 64;
parameter LOADS_OVER_STORES = 0;

// load request port
wire              load_request_ready;
reg               load_request_valid;
reg [XLEN   -1:0] load_request_address;
// load response port
reg               load_response_ready;
wire              load_response_valid;
wire [XLEN  -1:0] load_response_address;
wire [XLEN  -1:0] load_response_value;
// store request port
wire              store_request_ready;
reg               store_request_valid;
reg [XLEN   -1:0] store_request_address;
reg [XLEN   -1:0] store_request_value;
reg [XLEN/8 -1:0] store_request_byte_en;
//memory stage interface
wire              memory_read;        // high if CPU is sending out a load
wire              memory_write;       // high if CPU is sending out a store
wire [XLEN/8-1:0] memory_byte_en;     // specifies which bytes we are writting, one bit / byte
wire [XLEN  -1:0] memory_address_out; // load or store address
wire [XLEN  -1:0] memory_data_out;    // store data sent to memory
reg  [XLEN  -1:0] memory_data_in;     // data of the load request coming in from memory
reg  [XLEN  -1:0] memory_address_in;  // address of the load request coming in from memory
reg               memory_valid;       // validity of the load request - the CPU must be able to accept this!
reg               memory_ready;       // readyness of the memory to accept new stores or loads

dmem_arbiter #(
  .XLEN(XLEN),
  .LOADS_OVER_STORES(LOADS_OVER_STORES)
) DUT (
  // load request port
  .load_request_ready(load_request_ready),
  .load_request_valid(load_request_valid),
  .load_request_address(load_request_address),
  // load response port
  .load_response_ready(load_response_ready),
  .load_response_valid(load_response_valid),
  .load_response_address(load_response_address),
  .load_response_value(load_response_value),
  // store request port
  .store_request_ready(store_request_ready),
  .store_request_valid(store_request_valid),
  .store_request_address(store_request_address),
  .store_request_value(store_request_value),
  .store_request_byte_en(store_request_byte_en),
  //memory stage interface
  .memory_read(memory_read),        // high if CPU is sending out a load
  .memory_write(memory_write),       // high if CPU is sending out a store
  .memory_byte_en(memory_byte_en),     // specifies which bytes we are writting, one bit / byte
  .memory_address_out(memory_address_out), // load or store address
  .memory_data_out(memory_data_out),    // store data sent to memory
  .memory_data_in(memory_data_in),     // data of the load request coming in from memory
  .memory_address_in(memory_address_in),  // address of the load request coming in from memory
  .memory_valid(memory_valid),       // validity of the load request - the CPU must be able to accept this!
  .memory_ready(memory_ready)        // readyness of the memory to accept new stores or loads
);

initial begin
  // load request port
  load_request_valid   <= 1'b0;
  load_request_address <= 0;
  // load response port
  load_response_ready <= 1'b1;
  // store request port
  store_request_valid   <= 1'b0;
  store_request_address <= 0;
  store_request_value   <= 0;
  store_request_byte_en <= 0;
  //memory stage interface
  memory_data_in    <= 0;
  memory_address_in <= 0;
  memory_valid      <= 1'b0;
  memory_ready      <= 1'b1;

  #10

  if(load_request_ready  !== 1'b1 |
     load_response_valid !== 1'b0 |
     store_request_ready !== 1'b1 |
     memory_read         !== 1'b0 |
     memory_write        !== 1'b0 ) begin
    $display("\ntb_dmem_arbiter --> Test Failed!\n\n");
    $stop;
  end

  #10
  $display("\ntb_dmem_arbiter --> Test Passed!\n\n");
  $stop;
end

endmodule
