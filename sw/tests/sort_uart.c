#include "baremetal.h"
#include "uart.h"

#define MAX_VALUES 32u
#define LINE_BYTES 512u

static char line[LINE_BYTES];
static int32_t original[MAX_VALUES], sorted[MAX_VALUES];
static int skip_lf;

// Receive first, parse only after Enter. This keeps RX polling fast enough for
// continuous 115200-baud input with the peripheral's one-byte holding register.
static const char *read_line(void)
{
  unsigned length = 0;
  int too_long = 0;
  int receive_error = 0;
  for (;;) {
    char ch = uart_getc(&receive_error);
    if (skip_lf) {
      skip_lf = 0;
      if (ch == '\n') continue; // Treat CRLF as one Enter.
    }
    if (ch == '\r' || ch == '\n') {
      skip_lf = ch == '\r';
      // Include errors that appeared between the status and RXDATA reads.
      uint32_t errors = UART_STATUS & UINT32_C(0x18);
      if (errors != 0u) {
        receive_error = 1;
        UART_STATUS = errors;
      }
      line[length] = '\0';
      if (receive_error) return "ERROR: UART receive";
      if (too_long) return "ERROR: line too long";
      return 0;
    }
    if (ch == '\b' || ch == 127) {
      if (length != 0u) --length;
    } else if (ch == '\0') {
      receive_error = 1;
    } else if (length + 1u < LINE_BYTES) {
      line[length++] = ch;
    } else {
      too_long = 1; // Drain the rest of this line rather than sort a prefix.
    }
  }
}

static int separator(char ch)
{
  return ch == ' ' || ch == '\t' || ch == ',';
}

static const char *parse_line(unsigned *count)
{
  const char *p = line;
  *count = 0;
  while (*p != '\0') {
    while (separator(*p)) ++p;
    if (*p == '\0') break;
    if (*count == MAX_VALUES) return "ERROR: max 32 numbers";
    int negative = *p == '-';
    if (*p == '-' || *p == '+') ++p;
    if (*p < '0' || *p > '9') return "ERROR: invalid number";
    uint32_t magnitude = 0;
    uint32_t limit = negative ? UINT32_C(2147483648) : UINT32_C(2147483647);
    while (*p >= '0' && *p <= '9') {
      uint32_t digit = (uint32_t)(*p++ - '0');
      if (magnitude > (limit - digit) / 10u) return "ERROR: int32 range";
      magnitude = magnitude * 10u + digit;
    }
    if (*p != '\0' && !separator(*p)) return "ERROR: invalid number";
    int32_t value = negative
        ? (magnitude == UINT32_C(2147483648) ? INT32_MIN : -(int32_t)magnitude)
        : (int32_t)magnitude;
    original[*count] = sorted[*count] = value;
    ++*count;
  }
  return *count == 0u ? "ERROR: empty input" : 0;
}

static void sort_and_check(unsigned count)
{
  for (unsigned i = 1; i < count; ++i) {
    int32_t key = sorted[i];
    unsigned j = i;
    while (j != 0u && sorted[j - 1u] > key) {
      sorted[j] = sorted[j - 1u];
      --j;
    }
    sorted[j] = key;
  }
  int correct = 1;
  for (unsigned i = 1; i < count; ++i) correct &= sorted[i - 1u] <= sorted[i];
  // Exact multiplicities catch corrupted/lost values, including duplicates.
  for (unsigned i = 0; i < count; ++i) {
    unsigned before = 0, after = 0;
    for (unsigned j = 0; j < count; ++j) {
      before += original[j] == original[i];
      after += sorted[j] == original[i];
    }
    correct &= before == after;
  }
  if (!correct) {
    uart_puts("SORT FAIL\r\n");
    uart_flush();
    bm_fail(1u); // An internal correctness failure stops the CPU.
  }
}

int main(void)
{
  uart_puts("RV32I SORT\r\nEnter 1..32 int32 values separated by spaces; press Enter.\r\n");
  for (;;) {
    uart_puts("READY\r\n");
    uart_flush();
    const char *error = read_line();
    unsigned count = 0;
    if (error == 0) error = parse_line(&count);
    if (error != 0) {
      uart_puts(error);
      uart_puts("\r\n");
      uart_flush();
      continue; // Bad input can be corrected without resetting the FPGA.
    }
    sort_and_check(count);
    uart_puts("Sorted: ");
    for (unsigned i = 0; i < count; ++i) {
      if (i != 0u) uart_putc(' ');
      uart_put_i32(sorted[i]);
    }
    uart_puts("\r\n");
    uart_flush();
    // Preserve the existing latched first-success LED indication; keep serving
    // subsequent lines rather than calling the nonreturning bm_pass().
    tohost = BM_PASS_STATUS;
    __asm__ volatile ("fence rw, rw" : : : "memory");
  }
}
