CROSS_COMPILE ?= arm-none-eabi-
CC = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
CFLAGS = -fpic -fvisibility=hidden -Os -Wall -Wextra -Werror -std=gnu99 -I. -DIS_VESC_LIB -fomit-frame-pointer -falign-functions=16 -mthumb -fsingle-precision-constant -mfloat-abi=hard -mfpu=fpv4-sp-d16 -mcpu=cortex-m4 -fdata-sections -ffunction-sections
LDFLAGS = -nostartfiles -static -mfloat-abi=hard -mfpu=fpv4-sp-d16 -mcpu=cortex-m4 -Wl,--gc-sections,--undefined=init -T link.ld
all: motor_wizard.bin
motor_wizard.bin: code.c schema.h transaction.h vesc_c_if.h link.ld Makefile
	"$(CC)" $(CFLAGS) -c code.c -o code.o
	"$(CC)" code.o $(LDFLAGS) -lm -o motor_wizard.elf
	"$(OBJCOPY)" -O binary motor_wizard.elf motor_wizard.bin --gap-fill 0x00

clean:
	rm -f motor_wizard.bin motor_wizard.elf *.o

.DELETE_ON_ERROR:
.PHONY: all clean
