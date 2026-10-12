// Keccak-f1600 KAT: permutation of the all-zero state. Expected value
// from sw/golden.py, itself cross-checked against hashlib SHA3-256.
`timescale 1ns/1ps
module tb_keccak;
    reg clk=0, rst_n=0, start=0;
    reg [1599:0] state_in;
    wire [1599:0] state_out;
    wire busy, done;
    keccak_f1600 dut(.clk(clk),.rst_n(rst_n),.start(start),
        .state_in(state_in),.state_out(state_out),.busy(busy),.done(done));
    always #5 clk = ~clk;
    localparam [1599:0] EXP_ZERO = 1600'heaf1ff7b5ceca24975f644e97f30a13b16f53526e70465c21841f924a2c509e4940c7922ae3a26148c3ee88a1ccf32c8b87c5a554fd00ecb613670957bc4661164befef28cc970f205e5635a21d9ae6101f22f1a11a5569f43b831cd0347c82681a57c16dbcf555fa9a6e6260d712103eb5aa93f2317d63530935ab7d08ffc64ad30a6f71b19059c8c5bda0cd6192e7690fee5a0a44647c4ff97a42d7f8e6fd48b284e056253d057bd1547306f80494dd598261ea65aa9ee84d5ccf933c0478af1258f7940e1dde7;
    initial begin
        repeat(2) @(negedge clk); rst_n=1;
        @(negedge clk); state_in=1600'b0; start=1;
        @(negedge clk); start=0;
        wait(done); @(negedge clk);
        if (state_out !== EXP_ZERO) begin
            $display("FAIL keccak(0)\n got=%h\n exp=%h", state_out, EXP_ZERO);
            $display("TB_KECCAK FAIL");
        end else $display("PASS keccak-f1600(0)\nTB_KECCAK PASS");
        $finish;
    end
endmodule
