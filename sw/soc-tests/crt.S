// Minimal CRT for SoC baremetal tests at 0x8000_0000:
// stack at 0x8010_0000 (unused by the test image), zero
// .bss, call main, park on return.
	.section .text
	.globl _start
_start:
	li	sp, 0x80100000
	la	t0, _bss_start
	la	t1, _bss_end
1:	bgeu	t0, t1, 2f
	sd	zero, 0(t0)
	addi	t0, t0, 8
	j	1b
2:	call	main
3:	wfi
	j	3b
