// SHA-256 block KATs: "abc" and "" (FIPS 180-4 examples, padded blocks).
`timescale 1ns/1ps
module tb_sha256;
    reg clk=0, rst_n=0, start=0;
    reg [511:0] block_in;
    wire [255:0] digest;
    wire busy, done;
    integer errors=0;
    sha256_block dut(.clk(clk),.rst_n(rst_n),.start(start),
        .block_in(block_in),.digest_out(digest),.busy(busy),.done(done));
    always #5 clk = ~clk;

    task run_block(input [511:0] blk, input [255:0] exp,
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
        // "abc": 61626380 || 00..00 || bitlen 24
        run_block({32'h61626380, 448'b0, 32'd24},
            256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, "sha256(abc)");
        // "": 80000000 || 00..00 || bitlen 0
        run_block({32'h80000000, 480'b0},
            256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855, "sha256(empty)");
        if (errors==0) $display("TB_SHA256 PASS"); else $display("TB_SHA256 FAIL %0d", errors);
        $finish;
    end
endmodule
