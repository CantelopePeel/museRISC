// Integration KAT for muse_crypto_top: drives the AXI4-Lite
// register interface (docs/SPEC.md) end to end -- DIN/DOUT word
// ordering, CTRL engine/op select, STATUS busy/done, MODSEL and
// the custom-modulus regs. Leaf engines have their own KATs
// (tb_sha256, tb_ec_field); vectors here are reused from them so
// a failure localises to the register/AXI layer.
`timescale 1ns/1ps
`default_nettype none
module tb_muse_crypto_top;
    reg clk = 0, rst_n = 0;
    reg  [7:0]  awaddr = 0; reg awvalid = 0; wire awready;
    reg  [31:0] wdata = 0;  reg wvalid = 0;  wire wready;
    wire [1:0]  bresp; wire bvalid; reg bready = 0;
    reg  [7:0]  araddr = 0; reg arvalid = 0; wire arready;
    wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready = 0;
    integer errors = 0, i;
    reg [31:0] v;
    reg [255:0] got;

    muse_crypto_top dut (.clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
        .s_axi_rready(rready));
    always #5 clk = ~clk;

    task wr(input [7:0] a, input [31:0] d);
        begin
            @(negedge clk); awaddr = a; wdata = d; awvalid = 1; wvalid = 1;
            @(negedge clk); awvalid = 0; wvalid = 0;
            wait (bvalid); @(negedge clk); bready = 1;
            @(negedge clk); bready = 0;
            if (bresp !== 2'b00) begin
                errors = errors + 1;
                $display("FAIL wr %h bresp=%b", a, bresp);
            end
        end
    endtask

    task rd(input [7:0] a, output [31:0] d);
        begin
            @(negedge clk); araddr = a; arvalid = 1;
            @(negedge clk); arvalid = 0;
            wait (rvalid); d = rdata;
            if (rresp !== 2'b00) begin
                errors = errors + 1;
                $display("FAIL rd %h rresp=%b", a, rresp);
            end
            @(negedge clk); rready = 1;
            @(negedge clk); rready = 0;
        end
    endtask

    // Poll STATUS.done (bit1) with a cycle budget.
    task wait_done(input [255:0] nm);
        integer t;
        begin
            v = 0; t = 0;
            while (v[1] !== 1'b1 && t < 20000) begin
                rd(8'h04, v); t = t + 1;
            end
            if (v[1] !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL %0s: done never set (STATUS=%h)", nm, v);
            end
        end
    endtask

    task read_dout;
        integer k; reg [31:0] w;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                rd(8'h48 + 4*k[7:0], w);
                got[32*k +: 32] = w;
            end
        end
    endtask

    task check(input [255:0] exp, input [255:0] nm);
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL %0s got=%h exp=%h", nm, got, exp);
            end else $display("PASS %0s", nm);
        end
    endtask

    localparam [255:0] SECP = 256'hfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;
    localparam [255:0] C255 = 256'h7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed;

    initial begin
        repeat (2) @(negedge clk); rst_n = 1;

        // --- SHA-256("abc"): DIN0 is the first message word
        // (top word-reverses DIN into the block), DOUT0 is the
        // least-significant digest word.
        wr(8'h08, 32'h61626380);
        for (i = 1; i < 15; i = i + 1) wr(8'h08 + 4*i[7:0], 32'd0);
        wr(8'h08 + 8'd60, 32'd24);            // bit length, last word
        wr(8'h00, 32'h1);                     // CTRL: start, engine 0
        rd(8'h04, v);
        if (v[1] !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL sha256(abc): done not cleared by CTRL write");
        end
        wait_done("sha256(abc)");
        read_dout;
        // read_dout reassembles DOUT0..7 low word first, so
        // "got" is the digest as one 256-bit number.
        check(256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad,
              "sha256(abc) via AXI");

        // --- SHA-256(""): reuse DIN regs, rewrite DIN0/last word.
        wr(8'h08, 32'h80000000);
        wr(8'h08 + 8'd60, 32'd0);
        wr(8'h00, 32'h1);
        wait_done("sha256(empty)");
        read_dout;
        check(256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855,
              "sha256(empty) via AXI");

        // --- Field mul, mixed vector, secp256k1 (MODSEL=0).
        // a = DIN0..7 (low word first), b = DIN8..15.
        for (i = 0; i < 8; i = i + 1) begin
            wr(8'h08 + 4*i[7:0],
               (256'h1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef >> (32*i)) & 256'hffffffff);
            wr(8'h28 + 4*i[7:0],
               (256'hfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321 >> (32*i)) & 256'hffffffff);
        end
        wr(8'h68, 32'd0);                     // MODSEL = secp256k1
        wr(8'h00, 32'hA1);                    // start, engine 2, op 2 (mul)
        wait_done("field mul mixed secp");
        read_dout;
        check(256'h0dabcd892d293feb6a2a19b97d502825c6a865e9cd771060354652a4e4897181,
              "field mul mixed secp via AXI");

        // --- Field sub 2-3 mod secp = p-1.
        for (i = 0; i < 16; i = i + 1) wr(8'h08 + 4*i[7:0], 32'd0);
        wr(8'h08, 32'd2); wr(8'h28, 32'd3);
        wr(8'h00, 32'h61);                    // start, engine 2, op 1 (sub)
        wait_done("field sub 2-3 secp");
        read_dout;
        check(SECP - 256'd1, "field sub 2-3 secp via AXI");

        // --- Field mul (p-2)^2 with MODSEL=1 (Curve25519) = 4.
        for (i = 0; i < 8; i = i + 1) begin
            wr(8'h08 + 4*i[7:0], ((C255 - 256'd2) >> (32*i)) & 256'hffffffff);
            wr(8'h28 + 4*i[7:0], ((C255 - 256'd2) >> (32*i)) & 256'hffffffff);
        end
        wr(8'h68, 32'd1);
        wr(8'h00, 32'hA1);
        wait_done("field mul (p-2)^2 c25519");
        read_dout;
        check(256'd4, "field mul (p-2)^2 c25519 via AXI");

        // --- Custom modulus via MOD regs (MODSEL=2), mul 2*3.
        for (i = 0; i < 8; i = i + 1)
            wr(8'h6c + 4*i[7:0], (SECP >> (32*i)) & 256'hffffffff);
        for (i = 0; i < 16; i = i + 1) wr(8'h08 + 4*i[7:0], 32'd0);
        wr(8'h08, 32'd2); wr(8'h28, 32'd3);
        wr(8'h68, 32'd2);
        rd(8'h68, v);
        if (v[1:0] !== 2'd2) begin
            errors = errors + 1;
            $display("FAIL MODSEL readback got=%h", v);
        end
        wr(8'h00, 32'hA1);
        wait_done("field mul 2*3 custom mod");
        read_dout;
        check(256'd6, "field mul 2*3 custom mod via AXI");

        // --- Engine 1 (Keccak) is reserved: a start must leave
        // STATUS idle (no busy, no done), not hang the slave.
        wr(8'h00, 32'h11);                    // start, engine 1
        repeat (20) @(negedge clk);
        rd(8'h04, v);
        if (v[1:0] !== 2'b00) begin
            errors = errors + 1;
            $display("FAIL reserved engine 1: STATUS=%h (want idle)", v);
        end else $display("PASS reserved engine 1 stays idle");

        if (errors == 0) $display("TB_MUSE_CRYPTO_TOP PASS");
        else $display("TB_MUSE_CRYPTO_TOP FAIL %0d", errors);
        $finish;
    end
endmodule
`default_nettype wire
