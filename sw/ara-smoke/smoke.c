// Ara RVV smoke kernel for the CVA6+Ara verilated model (issue #9).
// Integer vadd and FP vfadd over strip-mined arrays, scalar-checked.
// Returns 0 on success, 2/4 on the first failing stage (ara_tb maps
// the EOC register value >> 1 to the simulator exit code).
#include <stdint.h>

#define N 64
static int32_t a[N], b[N], c[N];
static float fa[N], fb[N], fc[N];

static int check_int(void) {
  for (int i = 0; i < N; i++) { a[i] = i * 3 - 50; b[i] = 100 - i; }
  int n = N;
  int32_t *pa = a, *pb = b, *pc = c;
  while (n > 0) {
    long vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(n));
    asm volatile("vle32.v v0, (%0)" ::"r"(pa));
    asm volatile("vle32.v v1, (%0)" ::"r"(pb));
    asm volatile("vadd.vv v2, v0, v1");
    asm volatile("vse32.v v2, (%0)" ::"r"(pc));
    pa += vl; pb += vl; pc += vl; n -= (int)vl;
  }
  for (int i = 0; i < N; i++)
    if (c[i] != a[i] + b[i]) return 2;
  return 0;
}

static int check_fp(void) {
  for (int i = 0; i < N; i++) { fa[i] = (float)i * 0.5f; fb[i] = 1.25f; }
  int n = N;
  float *pa = fa, *pb = fb, *pc = fc;
  while (n > 0) {
    long vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(n));
    asm volatile("vle32.v v0, (%0)" ::"r"(pa));
    asm volatile("vle32.v v1, (%0)" ::"r"(pb));
    asm volatile("vfadd.vv v2, v0, v1");
    asm volatile("vse32.v v2, (%0)" ::"r"(pc));
    pa += vl; pb += vl; pc += vl; n -= (int)vl;
  }
  for (int i = 0; i < N; i++) {
    float want = fa[i] + fb[i];
    if (fc[i] != want) return 4;
  }
  return 0;
}

int main(void) {
  int r = check_int();
  if (r) return r;
  return check_fp();
}
