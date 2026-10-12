// SHA-512 block KATs: "abc" and "" (FIPS 180-4; digests = hashlib).
// Padding: 0x80, zeros, 128-bit bit-length at end of 1024-bit block.
`timescale 1ns/1ps
module tb_sha512;
    reg clk=0, rst_n=0, start=0;
    reg [1023:0] block_in;
    wire [511:0] digest;
    wire busy, done;
    integer errors=0;
    sha512_block dut(.clk(clk),.rst_n(rst_n),.start(start),
        .block_in(block_in),.digest_out(digest),.busy(busy),.done(done));
    always #5 clk = ~clk;
    task run_block(input [1023:0] blk, input [511:0] exp,
                   input [127:0] name);
        begin
            @(negedge clk); block_in=blk; start=1;
            @(negedge clk); start=0;
            wait(done); @(negedge clk);
            if (digest !== exp) begin
                errors=errors+1;
                $display("FAIL %0s got=%h exp=%h", name, digest, exp);
            end else $display("PASS %0s", name);
        end
    endtask
    initial begin
        repeat(2) @(negedge clk); rst_n=1;
        run_block({32'h61626380, 864'b0, 128'd24},
            512'hddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f,
            "sha512(abc)");
        run_block({32'h80000000, 992'b0},
            512'hcf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e,
            "sha512(empty)");
        if (errors==0) $display("TB_SHA512 PASS"); else $display("TB_SHA512 FAIL %0d", errors);
        $finish;
    end
endmodule
