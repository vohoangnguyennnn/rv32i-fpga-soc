#include "baremetal.h"
static volatile uint32_t input[2] = {37u, 12u};
int main(void) {
  uint32_t a = input[0], b = input[1];
  BM_CHECK(a+b == 49u, 1u);
  BM_CHECK(a-b == 25u, 2u);
  BM_CHECK((a^b) == 41u, 3u);
  BM_CHECK((a&b) == 4u, 4u);
  return 0;
}
