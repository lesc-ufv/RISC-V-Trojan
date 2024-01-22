// A function converting 5-bit numbers smaller than 10 to characters 

function [23:0] num2reg;

    input [4:0] value;

    begin
        case(value)
            5'b00000: num2reg = " zr"; //"00"; 
            5'b00001: num2reg = " ra"; //"01"; 
            5'b00010: num2reg = " sp"; //"02"; 
            5'b00011: num2reg = " gp"; //"03"; 
            5'b00100: num2reg = " tp"; //"04"; 
            5'b00101: num2reg = " t0"; //"05"; 
            5'b00110: num2reg = " t1"; //"06"; 
            5'b00111: num2reg = " t2"; //"07"; 
            5'b01000: num2reg = " s0"; //"08"; 
            5'b01001: num2reg = " s1"; //"09"; 
            5'b01010: num2reg = " a0"; //"10"; 
            5'b01011: num2reg = " a1"; //"11"; 
            5'b01100: num2reg = " a2"; //"12"; 
            5'b01101: num2reg = " a3"; //"13"; 
            5'b01110: num2reg = " a4"; //"14"; 
            5'b01111: num2reg = " a5"; //"15"; 
            5'b10000: num2reg = " a6"; //"16"; 
            5'b10001: num2reg = " a7"; //"17"; 
            5'b10010: num2reg = " s2"; //"18"; 
            5'b10011: num2reg = " s3"; //"19"; 
            5'b10100: num2reg = " s4"; //"20"; 
            5'b10101: num2reg = " s5"; //"21"; 
            5'b10110: num2reg = " s6"; //"22"; 
            5'b10111: num2reg = " s7"; //"23"; 
            5'b11000: num2reg = " s8"; //"24"; 
            5'b11001: num2reg = " s9"; //"25"; 
            5'b11010: num2reg = "s10"; //"26"; 
            5'b11011: num2reg = "s11"; //"27"; 
            5'b11100: num2reg = " t3"; //"28"; 
            5'b11101: num2reg = " t4"; //"29"; 
            5'b11110: num2reg = " t5"; //"30"; 
            5'b11111: num2reg = " t6"; //"31"; 
            default: num2reg  = "XXX"; //"XX";
        endcase
    end
endfunction


function [7:0] num2hex;
    input [3:0] num;

    begin
        case(num[3:0])
            4'b0000: num2hex = "0"; 
            4'b0001: num2hex = "1"; 
            4'b0010: num2hex = "2"; 
            4'b0011: num2hex = "3"; 
            4'b0100: num2hex = "4"; 
            4'b0101: num2hex = "5"; 
            4'b0110: num2hex = "6"; 
            4'b0111: num2hex = "7"; 
            4'b1000: num2hex = "8"; 
            4'b1001: num2hex = "9"; 
            4'b1010: num2hex = "a"; 
            4'b1011: num2hex = "b"; 
            4'b1100: num2hex = "c"; 
            4'b1101: num2hex = "d"; 
            4'b1110: num2hex = "e"; 
            4'b1111: num2hex = "f"; 
            default: num2hex = "X";
        endcase
    end
endfunction

// A function for converting values to ascii hex
function [5*8-1:0] imm2ascii;
    input [19:0] value;
    
    begin
        imm2ascii = {num2hex(value[19:16]), num2hex(value[15:12]), num2hex(value[11:8]), num2hex(value[7:4]), num2hex(value[3:0])};
    end
endfunction


// A function for decoding RISC-V instruction as strings
function [20*8-1:0] decode;
    input [31:0] instruction;

    reg [6:0] opcode;
    reg [6:0] funct7;
    reg [2:0] funct3;
    reg [4:0] rd, rs1, rs2;
    reg [11:0] imm;
    reg [19:0] lui_imm;

    begin 
        opcode  = instruction[ 6: 0];
        funct7  = instruction[31:25];
        funct3  = instruction[14:12];
        rd      = instruction[11: 7];
        rs1     = instruction[19:15];
        rs2     = instruction[24:20];
        imm     = instruction[31:20];
        lui_imm = instruction[31:12];

        decode  = {20{" "}};
        // NOP
        if (instruction == 32'h00000013) 
            decode = "NOP";
        // R-type
        else if (opcode == 7'b0110011) begin
            casex({funct7, funct3})
                10'b0000000_000: decode = "ADD";
                10'b0100000_000: decode = "SUB";
                10'b0000000_111: decode = "AND";
                10'b0000000_110: decode = "OR";
                10'b0000000_100: decode = "XOR";
                10'b0000000_010: decode = "SLT";
                10'b0000000_011: decode = "SLTU";
                10'b0100000_101: decode = "SRA";
                10'b0000000_001: decode = "SLL";
                10'b0110011_000: decode = "MUL";
                default: decode = "I DON'T KNOW";
            endcase
                
            decode = {decode, " ", num2reg(rd), ", ", num2reg(rs1), ", ", num2reg(rs2)};

        end else if (opcode == 7'b0010011) begin
            casex({funct7, funct3})
                10'bxxxxxxx_000: decode = "ADDI";
                10'bxxxxxxx_111: decode = "ANDI";
                10'bxxxxxxx_110: decode = "ORI";
                10'bxxxxxxx_100: decode = "XORI";
                10'bxxxxxxx_010: decode = "SLTI";
                10'bxxxxxxx_011: decode = "SLTIU";
                10'b0100000_101: decode = "SRAI";
                10'b0000000_101: decode = "SRLI";
                10'b0000000_001: decode = "SLLI";
                default: decode = "I DON'T KNOW";
            endcase

            decode = {decode, " ", num2reg(rd), ", ", num2reg(rs1), ", ", imm2ascii(imm)};

        end else if (opcode == 7'b0110111) begin
            decode = {"LUI ", num2reg(rd), ", ", imm2ascii(lui_imm)};
        end else if (opcode == 7'b0010111)
            decode = "AUIPC";
        else if (opcode == 7'b0000011)
            decode = "LW";
        else if (opcode == 7'b0100011)
            decode = "SW";
        else if (opcode == 7'b1101111)
            decode = "JAL";
        else if (opcode == 7'b1100111)
            decode = "JALR";
        else if (opcode == 7'b1100011) begin
            casex(funct3)
                3'b000: decode = "BEQ";
                3'b001: decode = "BNE";
                3'b100: decode = "BLT";
                3'b101: decode = "BGE";
                3'b110: decode = "BLTU";
                3'b111: decode = "BGEU";
                default: decode = "I DON'T KNOW";
            endcase
            decode = {decode, " ", num2reg(instruction[19:15]), ", ", num2reg(instruction[24:20])};
        end else 
            decode = "I DON'T KNOW";

    end 
endfunction

