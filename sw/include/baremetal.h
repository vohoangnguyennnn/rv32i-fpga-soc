#ifndef RV32I_BAREMETAL_H
#define RV32I_BAREMETAL_H

#include <stddef.h>
#include <stdint.h>

#define BM_TOHOST_ADDR UINT32_C(0x0000fffc)
#define BM_PASS_STATUS UINT32_C(1)

extern volatile uint32_t tohost;

void bm_exit(int status) __attribute__((noreturn));
void bm_pass(void) __attribute__((noreturn));
void bm_fail(uint32_t code) __attribute__((noreturn));

#define BM_CHECK(condition, code) \
  do {                            \
    if (!(condition)) {           \
      bm_fail((code));            \
    }                             \
  } while (0)

#endif
