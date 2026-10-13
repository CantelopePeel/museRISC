#!/usr/bin/env python3
"""Generate bare-metal TestFloat checker ELFs for the CVA6 model.

Reads Berkeley TestFloat `testfloat_gen` output (hex operand/result/
flags lines) and emits one RISC-V assembly checker per operation:
for each vector, load operands, clear fflags, execute the FPU op,
compare the result bits (canonicalizing NaNs: any NaN matches any
NaN) and the accrued exception flags exactly, then halt via HTIF
tohost like riscv-tests (odd pass value 1; fail value encodes the
case index). Vectors are embedded as data; large functions are
stride-sampled to at most --max-cases while preserving order.

Operation classes:
  arith  float->float arithmetic (add/sub/mul/div/sqrt/mulAdd)
  f2i    float->int conversions (fcvt.w/l[.s/.d], unsigned too);
         32-bit results compare sign-extended, as RV64 fcvt.w*
  i2f    int->float conversions (fcvt.[s/d].w/l, unsigned too)
  cvtfd  f32->f64 (fcvt.d.s); cvtfs: f64->f32 (fcvt.s.d)
  cmp    comparisons (feq/fle/flt) returning 0/1 in an int register

Usage:
  testfloat_gen -level 1 -seed 1 f64_add | \\
    scripts/testfloat_cva6.py f64_add > f64_add.S
"""
import sys

# name: (kind, nops, asm, is_f32, sign_extend_result32)
OPS = {
    "f32_add":    ("arith", 2, "fadd.s f3, f0, f1", True, False),
    "f32_sub":    ("arith", 2, "fsub.s f3, f0, f1", True, False),
    "f32_mul":    ("arith", 2, "fmul.s f3, f0, f1", True, False),
    "f32_div":    ("arith", 2, "fdiv.s f3, f0, f1", True, False),
    "f32_sqrt":   ("arith", 1, "fsqrt.s f3, f0", True, False),
    "f32_mulAdd": ("arith", 3, "fmadd.s f3, f0, f1, f2", True, False),
    "f64_add":    ("arith", 2, "fadd.d f3, f0, f1", False, False),
    "f64_sub":    ("arith", 2, "fsub.d f3, f0, f1", False, False),
    "f64_mul":    ("arith", 2, "fmul.d f3, f0, f1", False, False),
    "f64_div":    ("arith", 2, "fdiv.d f3, f0, f1", False, False),
    "f64_sqrt":   ("arith", 1, "fsqrt.d f3, f0", False, False),
    "f64_mulAdd": ("arith", 3, "fmadd.d f3, f0, f1, f2", False, False),
    "f32_to_i32":  ("f2i", 1, "fcvt.w.s a0, f0", True, True),
    "f32_to_i64":  ("f2i", 1, "fcvt.l.s a0, f0", True, False),
    "f32_to_ui32": ("f2i", 1, "fcvt.wu.s a0, f0", True, True),
    "f32_to_ui64": ("f2i", 1, "fcvt.lu.s a0, f0", True, False),
    "f64_to_i32":  ("f2i", 1, "fcvt.w.d a0, f0", False, True),
    "f64_to_i64":  ("f2i", 1, "fcvt.l.d a0, f0", False, False),
    "f64_to_ui32": ("f2i", 1, "fcvt.wu.d a0, f0", False, True),
    "f64_to_ui64": ("f2i", 1, "fcvt.lu.d a0, f0", False, False),
    "i32_to_f32":  ("i2f", 1, "fcvt.s.w f3, a0", True, False),
    "i64_to_f32":  ("i2f", 1, "fcvt.s.l f3, a0", True, False),
    "ui32_to_f32": ("i2f", 1, "fcvt.s.wu f3, a0", True, False),
    "ui64_to_f32": ("i2f", 1, "fcvt.s.lu f3, a0", True, False),
    "i32_to_f64":  ("i2f", 1, "fcvt.d.w f3, a0", False, False),
    "i64_to_f64":  ("i2f", 1, "fcvt.d.l f3, a0", False, False),
    "ui32_to_f64": ("i2f", 1, "fcvt.d.wu f3, a0", False, False),
    "ui64_to_f64": ("i2f", 1, "fcvt.d.lu f3, a0", False, False),
    "f32_to_f64": ("cvtfd", 1, "fcvt.d.s f3, f0", False, False),
    "f64_to_f32": ("cvtfs", 1, "fcvt.s.d f3, f0", True, False),
    "f32_eq": ("cmp", 2, "feq.s a0, f0, f1", True, False),
    "f32_le": ("cmp", 2, "fle.s a0, f0, f1", True, False),
    "f32_lt": ("cmp", 2, "flt.s a0, f0, f1", True, False),
    "f64_eq": ("cmp", 2, "feq.d a0, f0, f1", False, False),
    "f64_le": ("cmp", 2, "fle.d a0, f0, f1", False, False),
    "f64_lt": ("cmp", 2, "flt.d a0, f0, f1", False, False),
}

def f32_compare(w, flagmask=0x1F):
    w("""
    fmv.x.w a0, f3
    frflags a1
    slli a0, a0, 32
    srli a0, a0, 32
    beq a0, a3, flags_ok
    li t0, 0x7F800000
    and t1, a0, t0
    and t2, a3, t0
    bne t1, t0, fail_result
    bne t2, t0, fail_result
    li t0, 0x007FFFFF
    and t1, a0, t0
    and t2, a3, t0
    beqz t1, fail_result
    beqz t2, fail_result
flags_ok:""")
    w(f"""
    andi a1, a1, 0x{flagmask:02X}
    bne a1, a4, fail_flags
""")

def f64_compare(w, flagmask=0x1F):
    w("""
    fmv.x.d a0, f3
    frflags a1
    beq a0, a3, flags_ok
    li t0, 0x7FF0000000000000
    and t1, a0, t0
    and t2, a3, t0
    bne t1, t0, fail_result
    bne t2, t0, fail_result
    li t0, 0x000FFFFFFFFFFFFF
    and t1, a0, t0
    and t2, a3, t0
    beqz t1, fail_result
    beqz t2, fail_result
flags_ok:""")
    w(f"""
    andi a1, a1, 0x{flagmask:02X}
    bne a1, a4, fail_flags
""")

def main():
    if len(sys.argv) < 2 or sys.argv[1] not in OPS:
        print(f"usage: {sys.argv[0]} <op> [--max-cases N] < vectors.txt > out.S", file=sys.stderr)
        print("ops:", ", ".join(sorted(OPS)), file=sys.stderr)
        return 2
    op = sys.argv[1]
    max_cases = 0
    if "--max-cases" in sys.argv:
        max_cases = int(sys.argv[sys.argv.index("--max-cases") + 1])
    RMODES = {"rne": 0, "rtz": 1, "rdn": 2, "rup": 3, "rmm": 4}
    rmode = "rne"
    if "--rm" in sys.argv:
        rmode = sys.argv[sys.argv.index("--rm") + 1]
        assert rmode in RMODES, rmode
    kind, nops, inst, is32, se32 = OPS[op]
    lines = [ln.split() for ln in sys.stdin if ln.strip() and not ln.startswith("+")]
    cases = []
    for parts in lines:
        assert len(parts) == nops + 2, (op, parts)
        cases.append(parts)
    total = len(cases)
    if max_cases and total > max_cases:
        stride = total / max_cases
        cases = [cases[int(i * stride)] for i in range(max_cases)]
    n = len(cases)
    w = sys.stdout.write
    w(f"# TestFloat checker: {op}, {n} of {total} level-1 cases ({rmode.upper()}, tininess-after)\n")
    w("# Generated by scripts/testfloat_cva6.py from Berkeley TestFloat vectors.\n")
    w("# Fail tohost code: result mismatch = case+2, flags mismatch = case+1000002.\n")
    w("""
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x2000
    csrs mstatus, t0""")
    w(f"\n    csrwi frm, {RMODES[rmode]}")
    w("""
    la s0, cases
    li s1, 0
    li s2, CASE_COUNT
loop:""")
    off_exp = 8 * nops
    if kind in ("arith", "cmp", "f2i"):
        if is32:
            w("\n    flw f0, 0(s0)")
            if nops >= 2:
                w("\n    flw f1, 8(s0)")
            if nops >= 3:
                w("\n    flw f2, 16(s0)")
        else:
            w("\n    fld f0, 0(s0)")
            if nops >= 2:
                w("\n    fld f1, 8(s0)")
            if nops >= 3:
                w("\n    fld f2, 16(s0)")
    elif kind == "i2f":
        w("\n    ld a0, 0(s0)")
    elif kind == "cvtfd":
        w("\n    flw f0, 0(s0)")
    elif kind == "cvtfs":
        w("\n    fld f0, 0(s0)")
    w(f"""
    ld a3, {off_exp}(s0)
    ld a4, {off_exp + 8}(s0)
    csrwi fflags, 0
    {inst}""")
    # TestFloat generates float->int vectors with SoftFloat exact=false,
    # so expected flags never carry NX; RISC-V fcvt sets NX on inexact
    # conversions. Mask NX for f2i only (NV etc. still exact); fcvt NX
    # behavior is covered by ACT F/D against Sail.
    flagmask = 0x1E if kind == "f2i" else 0x1F
    if kind in ("arith", "i2f", "cvtfd", "cvtfs"):
        (f32_compare if is32 else f64_compare)(w, flagmask)
    else:  # f2i, cmp: integer result already in a0, exact compare
        w(f"""
    frflags a1
    bne a0, a3, fail_result
    andi a1, a1, 0x{flagmask:02X}
    bne a1, a4, fail_flags
""")
    stride = 8 * (nops + 2)
    w(f"""    addi s0, s0, {stride}
    addi s1, s1, 1
    blt s1, s2, loop
    li a0, 1
    la t0, tohost
    sw a0, 0(t0)
1:  j 1b
fail_result:
    addi a0, s1, 2
    j fail_write
fail_flags:
    li a0, 1000002
    add a0, a0, s1
fail_write:
    slli a0, a0, 1
    ori a0, a0, 1
    la t0, tohost
    sw a0, 0(t0)
1:  j 1b
    .align 2
trap_handler:
    li a0, 3
    la t0, tohost
    sw a0, 0(t0)
1:  j 1b
    .data
    .globl tohost
    .align 6
tohost: .dword 0
    .globl fromhost
    .align 6
fromhost: .dword 0
    .align 3
cases:
""")
    for parts in cases:
        for j, p in enumerate(parts[:-1]):
            v = int(p, 16)
            if se32 and j == nops:  # expected 32-bit int: sign-extend like RV64 fcvt.w*
                if v & 0x80000000:
                    v |= 0xFFFFFFFF00000000
            w(f"    .dword 0x{v:016X}\n")
        w(f"    .dword 0x{int(parts[-1], 16):X}\n")
    return 0

if __name__ == "__main__":
    import io
    buf = io.StringIO()
    real = sys.stdout
    sys.stdout = buf
    rc = main()
    sys.stdout = real
    if rc == 0:
        text = buf.getvalue()
        import re
        m = re.search(r": (\w+), (\d+) of (\d+)", text)
        cnt = m.group(2) if m else "0"
        real.write(f"    .equ CASE_COUNT, {cnt}\n")
        real.write(text)
    sys.exit(rc)
