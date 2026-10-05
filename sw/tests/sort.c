#include "baremetal.h"
static volatile int32_t input[32] = {9,-3,14,0,7,7,-8,21,4,2,19,-1,6,13,5,8,
  32,-17,3,11,1,25,10,-5,18,16,12,15,20,-2,22,4};
static int32_t original[32], sorted[32];
int main(void) {
  for (unsigned i=0;i<32;i++) original[i] = sorted[i] = input[i];
  for (unsigned i=1;i<32;i++) {
    int32_t key=sorted[i]; unsigned j=i;
    while (j && sorted[j-1]>key) { sorted[j]=sorted[j-1]; j--; }
    sorted[j]=key;
  }
  for (unsigned i=1;i<32;i++) BM_CHECK(sorted[i-1]<=sorted[i],1u);
  // Exact multiplicity check includes negatives and duplicate values.
  for (unsigned i=0;i<32;i++) {
    unsigned before=0,after=0;
    for (unsigned j=0;j<32;j++) {
      before += original[j]==original[i]; after += sorted[j]==original[i];
    }
    BM_CHECK(before==after,2u);
  }
  return 0;
}
