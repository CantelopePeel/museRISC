// museRISC Keccak-f1600 permutation (FIPS 202). 24 rounds, 1 round/cycle.
// State lane (x,y) is state[64*(5*y+x) +: 64], little-endian lanes as in
// the Keccak reference. Sponge (rate/padding) is handled by the driver.
`default_nettype none
module keccak_f1600 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [1599:0] state_in,
    output reg  [1599:0] state_out,
    output reg           busy,
    output reg           done
);
    reg [1599:0] st;
    reg [4:0]    round;

    function [63:0] rotl(input [63:0] x, input [5:0] n);
        rotl = (n == 0) ? x : ((x << n) | (x >> (64 - n)));
    endfunction

    function [5:0] rho(input [2:0] x, input [2:0] y);
        case ({y, x})
            6'b000_000: rho=0;  6'b000_001: rho=1;  6'b000_010: rho=62;
            6'b000_011: rho=28; 6'b000_100: rho=27;
            6'b001_000: rho=36; 6'b001_001: rho=44; 6'b001_010: rho=6;
            6'b001_011: rho=55; 6'b001_100: rho=20;
            6'b010_000: rho=3;  6'b010_001: rho=10; 6'b010_010: rho=43;
            6'b010_011: rho=25; 6'b010_100: rho=39;
            6'b011_000: rho=41; 6'b011_001: rho=45; 6'b011_010: rho=15;
            6'b011_011: rho=21; 6'b011_100: rho=8;
            6'b100_000: rho=18; 6'b100_001: rho=2;  6'b100_010: rho=61;
            6'b100_011: rho=56; default:    rho=14;
        endcase
    endfunction

    function [63:0] rc(input [4:0] i);
        case (i)
            5'd0: rc=64'h0000000000000001; 5'd1: rc=64'h0000000000008082;
            5'd2: rc=64'h800000000000808a; 5'd3: rc=64'h8000000080008000;
            5'd4: rc=64'h000000000000808b; 5'd5: rc=64'h0000000080000001;
            5'd6: rc=64'h8000000080008081; 5'd7: rc=64'h8000000000008009;
            5'd8: rc=64'h000000000000008a; 5'd9: rc=64'h0000000000000088;
            5'd10: rc=64'h0000000080008009; 5'd11: rc=64'h000000008000000a;
            5'd12: rc=64'h000000008000808b; 5'd13: rc=64'h800000000000008b;
            5'd14: rc=64'h8000000000008089; 5'd15: rc=64'h8000000000008003;
            5'd16: rc=64'h8000000000008002; 5'd17: rc=64'h8000000000000080;
            5'd18: rc=64'h000000000000800a; 5'd19: rc=64'h800000008000000a;
            5'd20: rc=64'h8000000080008081; 5'd21: rc=64'h8000000000008080;
            5'd22: rc=64'h0000000080000001; default: rc=64'h8000000080008008;
        endcase
    endfunction

    // One Keccak round, combinational over `st` and `round`.
    reg [63:0] A [0:24], B [0:24], Cc [0:4], Dd [0:4];
    reg [1599:0] nxt;
    integer x, y;
    always @* begin
        for (y=0;y<5;y=y+1) for (x=0;x<5;x=x+1)
            A[5*y+x] = st[64*(5*y+x) +: 64];
        for (x=0;x<5;x=x+1)
            Cc[x] = A[x]^A[5+x]^A[10+x]^A[15+x]^A[20+x];
        for (x=0;x<5;x=x+1)
            Dd[x] = Cc[(x+4)%5] ^ rotl(Cc[(x+1)%5], 6'd1);
        for (y=0;y<5;y=y+1) for (x=0;x<5;x=x+1) begin
            A[5*y+x] = A[5*y+x] ^ Dd[x];
            B[5*((2*x+3*y)%5)+y] = rotl(A[5*y+x], rho(x[2:0], y[2:0]));
        end
        for (y=0;y<5;y=y+1) for (x=0;x<5;x=x+1)
            A[5*y+x] = B[5*y+x] ^ ((~B[5*y+((x+1)%5)]) & B[5*y+((x+2)%5)]);
        A[0] = A[0] ^ rc(round);
        for (y=0;y<5;y=y+1) for (x=0;x<5;x=x+1)
            nxt[64*(5*y+x) +: 64] = A[5*y+x];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy<=0; done<=0; state_out<=0; st<=0; round<=0;
        end else if (start && !busy) begin
            busy<=1; done<=0; st<=state_in; round<=0;
        end else if (busy) begin
            st <= nxt;
            if (round == 23) begin
                busy<=0; done<=1; state_out<=nxt;
            end
            round <= round + 1;
        end else done <= 0;
    end
endmodule
`default_nettype wire
