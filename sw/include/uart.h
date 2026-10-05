#ifndef RV32I_UART_H
#define RV32I_UART_H

#include <stdint.h>

#define UART_TXDATA (*(volatile uint32_t *)UINT32_C(0x10000100))
#define UART_RXDATA (*(volatile uint32_t *)UINT32_C(0x10000104))
#define UART_STATUS (*(volatile uint32_t *)UINT32_C(0x10000108))

static inline void uart_putc(char ch)
{
  // The blocking LSU waits on the UART's req_ready while TX is busy.
  UART_TXDATA = (uint32_t)(unsigned char)ch;
}

static inline char uart_getc(int *receive_error)
{
  for (;;) {
    uint32_t errors = UART_STATUS & UINT32_C(0x18);
    if (errors != 0u) {
      *receive_error = 1;
      UART_STATUS = errors; // W1C overrun/framing flags; preserve TX/RX data.
    }
    uint32_t data = UART_RXDATA; // Read pops only when the holding byte is valid.
    if ((data & UINT32_C(0x80000000)) == 0u) return (char)(data & UINT32_C(0xff));
  }
}

static inline void uart_flush(void)
{
  // A TX write acknowledges the start of a frame, not its completion.
  // Wait for the last stop bit before reporting DONE or entering the halt loop.
  while ((UART_STATUS & UINT32_C(1)) == 0u) { }
}

static inline void uart_puts(const char *text)
{
  while (*text != '\0') uart_putc(*text++);
}

static inline void uart_put_i32(int32_t value)
{
  char digits[10];
  unsigned count = 0;
  uint32_t magnitude = (uint32_t)value;
  if (value < 0) {
    uart_putc('-');
    magnitude = 0u - magnitude; // Also defined for INT32_MIN.
  }
  do {
    digits[count++] = (char)('0' + magnitude % 10u);
    magnitude /= 10u; // RV32I compiler uses software arithmetic as needed.
  } while (magnitude != 0u);
  while (count != 0u) uart_putc(digits[--count]);
}

#endif
