SHELL := /bin/bash

BUILD_DIR ?= ../build/sw
CROSS_COMPILE ?= riscv64-unknown-elf-
PYTHON ?= python3

CC      := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
READELF := $(CROSS_COMPILE)readelf

ARCH      := rv32i
ABI       := ilp32
TCM_BYTES := 65536

include tests/programs.mk

PROGRAMS := $(sort $(BAREMETAL_PROGRAMS) $(BENCHMARK_PROGRAMS))

COREMARK_DIR := ../third_party/coremark
COREMARK_PORT_DIR := coremark
COREMARK_ITERATIONS ?= 1
COREMARK_PROGRAMS := coremark_performance coremark_validation
COREMARK_SOURCES := \
	$(COREMARK_DIR)/core_list_join.c \
	$(COREMARK_DIR)/core_main.c \
	$(COREMARK_DIR)/core_matrix.c \
	$(COREMARK_DIR)/core_state.c \
	$(COREMARK_DIR)/core_util.c \
	$(COREMARK_PORT_DIR)/core_portme.c
COREMARK_HEADERS := \
	$(COREMARK_DIR)/coremark.h \
	$(COREMARK_PORT_DIR)/core_portme.h \
	include/baremetal.h
COREMARK_CPPFLAGS := \
	-Iinclude \
	-I$(COREMARK_PORT_DIR) \
	-I$(COREMARK_DIR) \
	-DTOTAL_DATA_SIZE=2000 \
	-DITERATIONS=$(COREMARK_ITERATIONS)
COREMARK_MEM_IMAGES := \
	$(addprefix $(BUILD_DIR)/,$(addsuffix .mem,$(COREMARK_PROGRAMS)))
COREMARK_DISASSEMBLIES := \
	$(addprefix $(BUILD_DIR)/,$(addsuffix .dump,$(COREMARK_PROGRAMS)))

CPPFLAGS := -Iinclude
COMMON_FLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mcmodel=medlow \
	-mstrict-align \
	-mno-relax \
	-ffreestanding \
	-fno-common \
	-fno-pic \
	-ffunction-sections \
	-fdata-sections \
	-g3
CFLAGS := $(COMMON_FLAGS) -O2 -std=gnu11 -Wall -Wextra -Werror
ASFLAGS := $(COMMON_FLAGS)
LDFLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mno-relax \
	-nostdlib \
	-nostartfiles \
	-static \
	-T link.ld \
	-Wl,--build-id=none \
	-Wl,--gc-sections \
	-Wl,--fatal-warnings

COMMON_OBJECTS := \
	$(BUILD_DIR)/runtime/crt0.o \
	$(BUILD_DIR)/runtime/runtime.o
MEM_IMAGES := $(addprefix $(BUILD_DIR)/,$(addsuffix .mem,$(PROGRAMS)))
DISASSEMBLIES := $(addprefix $(BUILD_DIR)/,$(addsuffix .dump,$(PROGRAMS)))

.DEFAULT_GOAL := all
# A failed ISA scan must never leave an apparently successful dump target.
.DELETE_ON_ERROR:

.PHONY: all images baremetal-images coremark-check coremark-images coremark-force check-tools list clean
all: baremetal-images
baremetal-images: images $(DISASSEMBLIES)
images: $(MEM_IMAGES)

coremark-check:
	@echo "[CHECK] CoreMark upstream source hashes"
	@cd $(COREMARK_DIR) && sha256sum -c SOURCE.sha256

coremark-images: coremark-check $(COREMARK_MEM_IMAGES) $(COREMARK_DISASSEMBLIES)

coremark-force:

check-tools:
	@command -v $(CC) >/dev/null 2>&1 || { echo "error: $(CC) not found" >&2; exit 127; }
	@command -v $(OBJCOPY) >/dev/null 2>&1 || { echo "error: $(OBJCOPY) not found" >&2; exit 127; }
	@command -v $(OBJDUMP) >/dev/null 2>&1 || { echo "error: $(OBJDUMP) not found" >&2; exit 127; }
	@command -v $(READELF) >/dev/null 2>&1 || { echo "error: $(READELF) not found" >&2; exit 127; }
	@command -v $(PYTHON) >/dev/null 2>&1 || { echo "error: $(PYTHON) not found" >&2; exit 127; }

list:
	@printf '%s\n' $(PROGRAMS)

$(BUILD_DIR)/%.o: %.c | check-tools
	@mkdir -p $(@D)
	@echo "[CC]    $<"
	@$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/%.o: %.S | check-tools
	@mkdir -p $(@D)
	@echo "[AS]    $<"
	@$(CC) $(CPPFLAGS) $(ASFLAGS) -MMD -MP -c $< -o $@

define PROGRAM_template
$(BUILD_DIR)/$(1).elf: $(COMMON_OBJECTS) $(BUILD_DIR)/tests/$(1).o link.ld | check-tools
	@mkdir -p $$(@D)
	@echo "[LINK]  $(1)"
	@$$(CC) $$(LDFLAGS) -Wl,-Map,$$(BUILD_DIR)/$(1).map -o $$@ \
		$$(COMMON_OBJECTS) $$(BUILD_DIR)/tests/$(1).o -lgcc
	@$$(READELF) -h $$@ | grep -q 'Class:[[:space:]]*ELF32' || { \
		echo "error: $(1) is not ELF32" >&2; exit 1; \
	}

$(BUILD_DIR)/$(1).bin: $(BUILD_DIR)/$(1).elf $(BUILD_DIR)/$(1).dump
	@echo "[BIN]   $(1)"
	@$$(OBJCOPY) -O binary $$< $$@

$(BUILD_DIR)/$(1).mem: $(BUILD_DIR)/$(1).bin ../tools/bin_to_memh.py
	@echo "[MEMH]  $(1)"
	@$$(PYTHON) ../tools/bin_to_memh.py \
		--input $$< --output $$@ --size $$(TCM_BYTES)

$(BUILD_DIR)/$(1).dump: $(BUILD_DIR)/$(1).elf ../tools/check_isa.py Makefile
	@echo "[DUMP]  $(1)"
	@$$(OBJDUMP) -d -M no-aliases $$< > $$@
	@$$(PYTHON) ../tools/check_isa.py $$@
endef

$(foreach program,$(PROGRAMS),$(eval $(call PROGRAM_template,$(program))))

# Compile the five upstream sources and the platform port with one identical
# flag set, as required by the CoreMark run and reporting rules. Runtime/startup
# objects use the same COMMON_FLAGS/CFLAGS and are linked without libc.
$(BUILD_DIR)/coremark_performance.elf: coremark-force $(COMMON_OBJECTS) $(COREMARK_SOURCES) $(COREMARK_HEADERS) link.ld | check-tools
	@mkdir -p $(@D)
	@echo "[LINK]  coremark_performance"
	@$(CC) $(COREMARK_CPPFLAGS) $(CFLAGS) -DPERFORMANCE_RUN=1 \
		$(LDFLAGS) -Wl,-Map,$(BUILD_DIR)/coremark_performance.map -o $@ \
		$(COMMON_OBJECTS) $(COREMARK_SOURCES) -lgcc
	@$(READELF) -h $@ | grep -q 'Class:[[:space:]]*ELF32' || { \
		echo "error: coremark_performance is not ELF32" >&2; exit 1; \
	}

$(BUILD_DIR)/coremark_validation.elf: coremark-force $(COMMON_OBJECTS) $(COREMARK_SOURCES) $(COREMARK_HEADERS) link.ld | check-tools
	@mkdir -p $(@D)
	@echo "[LINK]  coremark_validation"
	@$(CC) $(COREMARK_CPPFLAGS) $(CFLAGS) -DVALIDATION_RUN=1 \
		$(LDFLAGS) -Wl,-Map,$(BUILD_DIR)/coremark_validation.map -o $@ \
		$(COMMON_OBJECTS) $(COREMARK_SOURCES) -lgcc
	@$(READELF) -h $@ | grep -q 'Class:[[:space:]]*ELF32' || { \
		echo "error: coremark_validation is not ELF32" >&2; exit 1; \
	}

define COREMARK_IMAGE_template
$(BUILD_DIR)/$(1).bin: $(BUILD_DIR)/$(1).elf $(BUILD_DIR)/$(1).dump
	@echo "[BIN]   $(1)"
	@$$(OBJCOPY) -O binary $$< $$@

$(BUILD_DIR)/$(1).mem: $(BUILD_DIR)/$(1).bin ../tools/bin_to_memh.py
	@echo "[MEMH]  $(1)"
	@$$(PYTHON) ../tools/bin_to_memh.py \
		--input $$< --output $$@ --size $$(TCM_BYTES)

$(BUILD_DIR)/$(1).dump: $(BUILD_DIR)/$(1).elf ../tools/check_isa.py Makefile
	@echo "[DUMP]  $(1)"
	@$$(OBJDUMP) -d -M no-aliases $$< > $$@
	@$$(PYTHON) ../tools/check_isa.py $$@
endef

$(foreach program,$(COREMARK_PROGRAMS),$(eval $(call COREMARK_IMAGE_template,$(program))))

clean:
	@$(RM) -r $(BUILD_DIR)

-include $(COMMON_OBJECTS:.o=.d)
-include $(addprefix $(BUILD_DIR)/tests/,$(addsuffix .d,$(PROGRAMS)))

