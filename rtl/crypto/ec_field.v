// museRISC 256-bit prime-field unit: add / sub / mul modulo `mod`.
// Used with mod = secp256k1 p or Curve25519 p (or a custom modulus).
// Multiplication is binary double-and-add, always 256 iterations
// (fixed count; operands must be < mod). Phase-0 correctness-first
// design -- a wider radix datapath is a Phase-2 optimisation.
`default_nettype none
module ec_field (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [1:0]   op,        // 0=add, 1=sub, 2=mul
    input  wire [255:0] a,
    input  wire [255:0] b,
    input  wire [255:0] mod,
    output reg  [255:0] result,
    output reg          busy,
    output reg          done
);
    reg [255:0] res, aa, bb, mm;
    reg [8:0]   cnt;

    // Modular add of x+y (x,y < mm, so sum < 2*mm: one subtract suffices).
    function [255:0] modadd(input [255:0] x, input [255:0] y);
        reg [256:0] s;
        begin
            s = {1'b0, x} + {1'b0, y};
            if (s >= {1'b0, mm}) s = s - {1'b0, mm};
            modadd = s[255:0];
        end
    endfunction

    wire [255:0] doubled = modadd(res, res);
    wire [255:0] added   = modadd(doubled, aa);
    wire         cur_bit = bb[255 - cnt[7:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy<=0; done<=0; result<=0; res<=0; cnt<=0;
        end else if (start && !busy) begin
            aa<=a; bb<=b; mm<=mod; done<=0;
            if (op == 2'd2) begin
                busy<=1; res<=0; cnt<=0;
            end else if (op == 2'd0) begin
                // add: compute directly against the input modulus
                result <= (({1'b0,a}+{1'b0,b}) >= {1'b0,mod}) ?
                          (a + b - mod) : (a + b);
                done <= 1;
            end else begin
                result <= (a >= b) ? (a - b) : (a + mod - b);
                done <= 1;
            end
        end else if (busy) begin
            res <= cur_bit ? added : doubled;
            if (cnt == 9'd255) begin
                result <= cur_bit ? added : doubled;
                busy <= 0; done <= 1;
            end
            cnt <= cnt + 1;
        end else done <= 0;
    end
endmodule
`default_nettype wire
