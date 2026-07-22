# -------------------------------------------------
# Toolchain
# -------------------------------------------------

CC          := cc65
AS          := ca65
LD          := ld65
BIN2ROM     := bin2rom

GETADDRSYS  := ./build/getaddress_syscall
GETADDRKRN  := ./build/getaddress_kernel
GETADDRUSR  := ./build/getaddress_user

PYTHON      := python3
DISASM      := ./build/disasm6502.py

RM          := rm -f
RMDIR       := rm -rf
MKDIR       := mkdir -p
CP          := cp
CAT         := cat

# -------------------------------------------------
# Project configuration
# -------------------------------------------------

INCDIR      := include -I bios -I user
CINCDIR     := libneox/include -I user/include
CFLAGS      := -t none --cpu 65c02 -Oirs -I $(CINCDIR) -I libneox/cc65 \
               --code-name C_CODE --rodata-name C_RODATA \
               --data-name C_DATA --bss-name C_BSS
OUTDIR      := out

SYS_TARGET  := neox_syscall
KRN_TARGET  := neox_kernel
USR_TARGET  := neox_user

SYS_CFG     := ./build/neox_syscall.cfg
KRN_CFG     := ./build/neox_kernel.cfg
USR_CFG     := ./libneox/cc65/cfg/neox.cfg

# Standard cc65 target archive. This is passed only to ld65; it is not
# a local Make prerequisite. ld65 resolves it through the installed
# cc65 library search path and extracts only referenced members.
CC65_RUNTIME_LIB := none.lib


SYS_BIN     := $(OUTDIR)/$(SYS_TARGET).bin
SYS_ROM     := $(OUTDIR)/$(SYS_TARGET).rom
SYS_MAP     := $(OUTDIR)/$(SYS_TARGET).map
SYS_LBL     := $(OUTDIR)/$(SYS_TARGET).lbl
SYS_LST     := $(OUTDIR)/$(SYS_TARGET).lst
SYS_DIS     := $(OUTDIR)/$(SYS_TARGET).dis

KRN_BIN     := $(OUTDIR)/$(KRN_TARGET).bin
KRN_ROM     := $(OUTDIR)/$(KRN_TARGET).rom
KRN_MAP     := $(OUTDIR)/$(KRN_TARGET).map
KRN_LBL     := $(OUTDIR)/$(KRN_TARGET).lbl
KRN_LST     := $(OUTDIR)/$(KRN_TARGET).lst
KRN_DIS     := $(OUTDIR)/$(KRN_TARGET).dis

USR_BIN     := $(OUTDIR)/$(USR_TARGET).bin
USR_ROM     := $(OUTDIR)/$(USR_TARGET).rom
USR_MAP     := $(OUTDIR)/$(USR_TARGET).map
USR_LBL     := $(OUTDIR)/$(USR_TARGET).lbl
USR_LST     := $(OUTDIR)/$(USR_TARGET).lst
USR_DIS     := $(OUTDIR)/$(USR_TARGET).dis

# optional install path
BASE_DIR    := /cygdrive/c/Users/rien/OneDrive/source/repos
PROJECT_DIR := /NEO6502_MMU_V3/NEO6502_MMU_V3
INSTALL_DIR := $(BASE_DIR)$(PROJECT_DIR)/data/system

# -------------------------------------------------
# Sources
# -------------------------------------------------

NBOX_BASE := user/nbox
include user/nbox.mk

SYSCALL_SRCS := \
	kernel/zero_page.asm \
	kernel/shared_state.asm \
	kernel/syscall_table.asm

KERNEL_SRCS := \
	kernel/zero_page.asm \
	kernel/shared_state.asm \
	kernel/context.asm \
	kernel/gate.asm \
	kernel/entry_table.asm \
	kernel/main.asm \
	kernel/irq.asm \
	kernel/klog.asm \
	kernel/math8.asm \
	kernel/sched_lock.asm \
	kernel/scheduler.asm \
	kernel/supervisor.asm \
	kernel/idle_task.asm \
	kernel/process_control.asm \
	kernel/fd.asm \
	kernel/spawn.asm \
	kernel/pipe.asm \
	kernel/timer.asm \
	kernel/ksys_io.asm \
	kernel/ksys_fs.asm \
	kernel/ksys_proc.asm \
	kernel/ksys_time.asm \
	kernel/device.asm \
	kernel/console_device.asm \
	kernel/rp_console_io.asm \
	kernel/rp_fs_io.asm \
	kernel/mailbox.asm \
	kernel/init_tasks.asm

USER_SRCS := \
	user/task/user_image.asm \
	user/shell/neosh_entry.asm \
	$(NBOX_SRCS)

USER_C_SRCS := \
	$(NBOX_C_SRCS) \
	user/shell/neosh.c \
	user/applets/echo.c \
	user/applets/cat.c \
	user/applets/path_command.c \
	user/applets/two_path_command.c \
	user/applets/rm.c \
	user/applets/mkdir.c \
	user/applets/rmdir.c \
	user/applets/mv.c \
	user/applets/cp.c \
	user/applets/cd.c \
	user/applets/pwd.c \
	user/applets/ls.c \
	user/applets/ps.c \
	user/applets/kill.c \

# NEOX-specific cc65 runtime integration and public libneox API.
LIBNEOX_ASM_SRCS := \
	libneox/cc65/zeropage.asm \
	libneox/cc65/runtime.asm \
	libneox/cc65/neox_open.asm \
	libneox/cc65/neox_read.asm \
	libneox/cc65/neox_write.asm \
	libneox/cc65/neox_close.asm \
	libneox/cc65/neox_delete.asm \
	libneox/cc65/neox_mkdir.asm \
	libneox/cc65/neox_rmdir.asm \
	libneox/cc65/neox_rename.asm \
	libneox/cc65/neox_chdir.asm \
	libneox/cc65/neox_getcwd.asm \
	libneox/cc65/neox_opendir.asm \
	libneox/cc65/neox_readdir.asm \
	libneox/cc65/neox_closedir.asm \
	libneox/cc65/neox_get_process_info.asm \
	libneox/cc65/neox_seek.asm \
	libneox/cc65/neox_spawn_resident.asm \
	libneox/cc65/neox_waitpid.asm \
	libneox/cc65/neox_signal.asm \
	libneox/cc65/neox_get_launch_id.asm \
	libneox/cc65/neox_get_launch_line.asm

# No diagnostic C translation units are part of the production image.
# Future common C implementation modules are added here.
LIBNEOX_C_SRCS := \
	libneox/common/applet_args.c \
	libneox/common/applet_support.c

# Compiler-generated helper routines are resolved from the installed
# standard cc65 none.lib archive. The final image is still linked directly
# with ld65 so NEOX keeps complete control of startup, configuration, entry
# ordering, and cartridge layout.


# -------------------------------------------------
# Derived objects / listings
# -------------------------------------------------

SYS_OBJS      := $(SYSCALL_SRCS:%.asm=$(OUTDIR)/%.o)
KRN_OBJS      := $(KERNEL_SRCS:%.asm=$(OUTDIR)/%.o)
USR_OBJS      := $(USER_SRCS:%.asm=$(OUTDIR)/%.o)
USER_C_ASMS   := $(USER_C_SRCS:%.c=$(OUTDIR)/%.s)
USER_C_OBJS   := $(USER_C_SRCS:%.c=$(OUTDIR)/%.o)
LIBNEOX_ASM_OBJS := $(LIBNEOX_ASM_SRCS:%.asm=$(OUTDIR)/%.o)
LIBNEOX_C_ASMS := $(LIBNEOX_C_SRCS:%.c=$(OUTDIR)/%.s)
LIBNEOX_C_OBJS := $(LIBNEOX_C_SRCS:%.c=$(OUTDIR)/%.o)

SYS_PART_LSTS := $(SYSCALL_SRCS:%.asm=$(OUTDIR)/%.lst)
KRN_PART_LSTS := $(KERNEL_SRCS:%.asm=$(OUTDIR)/%.lst)
USR_PART_LSTS := $(USER_SRCS:%.asm=$(OUTDIR)/%.lst)
USER_C_LSTS   := $(USER_C_SRCS:%.c=$(OUTDIR)/%.lst)
LIBNEOX_C_LSTS := $(LIBNEOX_C_SRCS:%.c=$(OUTDIR)/%.lst)

# -------------------------------------------------
# Default target
# -------------------------------------------------

.PHONY: all clean distclean install print dirs listings disasm
all: $(SYS_ROM) $(KRN_ROM) $(USR_ROM) $(SYS_DIS) $(KRN_DIS) $(USR_DIS)

SYS_DEPS      := $(SYSCALL_SRCS:%.asm=$(OUTDIR)/%.d)
KRN_DEPS      := $(KERNEL_SRCS:%.asm=$(OUTDIR)/%.d)
USR_DEPS      := $(USER_SRCS:%.asm=$(OUTDIR)/%.d)

# -------------------------------------------------
# Cartridge generation
# -------------------------------------------------

$(SYS_ROM): $(SYS_BIN)
	$(BIN2ROM) -B $(shell $(GETADDRSYS)) -o $@ $<

$(KRN_ROM): $(KRN_BIN)
	$(BIN2ROM) -B $(shell $(GETADDRKRN)) -o $@ $<

$(USR_ROM): $(USR_BIN)
	$(BIN2ROM) -B $(shell $(GETADDRUSR)) -o $@ $<

# -------------------------------------------------
# Link rules
# -------------------------------------------------

$(SYS_BIN): $(SYS_OBJS) $(SYS_CFG) | dirs
	$(LD) -C $(SYS_CFG) -vm -m $(SYS_MAP) -Ln $(SYS_LBL) -o $@ $(SYS_OBJS)

$(KRN_BIN): $(KRN_OBJS) $(KRN_CFG) | dirs
	$(LD) -C $(KRN_CFG) -vm -m $(KRN_MAP) -Ln $(KRN_LBL) -o $@ $(KRN_OBJS)

$(USR_BIN): $(USR_OBJS) $(USER_C_OBJS) $(LIBNEOX_ASM_OBJS) $(LIBNEOX_C_OBJS) $(USR_CFG) | dirs
	$(LD) -C $(USR_CFG) -vm -m $(USR_MAP) -Ln $(USR_LBL) \
		-o $@ $(USR_OBJS) $(USER_C_OBJS) $(LIBNEOX_ASM_OBJS) $(LIBNEOX_C_OBJS) \
		$(CC65_RUNTIME_LIB)

# -------------------------------------------------
# Python disassembly output
# -------------------------------------------------

$(SYS_DIS): $(SYS_BIN) $(SYS_MAP) $(SYS_LBL) $(DISASM) | dirs
	$(PYTHON) $(DISASM) $(SYS_BIN) F100 $(SYS_MAP) $(SYS_LBL) > $@

$(KRN_DIS): $(KRN_BIN) $(KRN_MAP) $(KRN_LBL) $(DISASM) | dirs
	$(PYTHON) $(DISASM) $(KRN_BIN) 8000 $(KRN_MAP) $(KRN_LBL) > $@

$(USR_DIS): $(USR_BIN) $(USR_MAP) $(USR_LBL) $(DISASM) | dirs
	$(PYTHON) $(DISASM) $(USR_BIN) 1000 $(USR_MAP) $(USR_LBL) > $@

disasm: $(SYS_DIS) $(KRN_DIS)

# -------------------------------------------------
# Assemble rules with listing output
# -------------------------------------------------

$(OUTDIR)/kernel/%.o: kernel/%.asm | dirs
	$(AS) --cpu W65C02 -g -I $(INCDIR) \
		--create-dep $(OUTDIR)/kernel/$*.d \
		-l $(OUTDIR)/kernel/$*.lst \
		-o $@ $<

$(OUTDIR)/user/%.o: user/%.asm | dirs
	$(AS) --cpu W65C02 -g -I $(INCDIR) \
		--create-dep $(OUTDIR)/user/$*.d \
		-l $(OUTDIR)/user/$*.lst \
		-o $@ $<

$(OUTDIR)/user/lib/%.o: user/lib/%.asm | dirs
	$(AS) --cpu W65C02 -g -I $(INCDIR) \
		--create-dep $(OUTDIR)/user/lib/$*.d \
		-l $(OUTDIR)/user/lib/$*.lst \
		-o $@ $<

# -------------------------------------------------
# cc65 user applet compile and assemble rules
# -------------------------------------------------

$(OUTDIR)/user/%.s: user/%.c | dirs
	$(CC) $(CFLAGS) -o $@ $<

$(OUTDIR)/user/%.o: $(OUTDIR)/user/%.s | dirs
	$(AS) --cpu W65C02 -g -I $(INCDIR) \
		-l $(OUTDIR)/user/$*.lst \
		-o $@ $<

# -------------------------------------------------
# cc65/libneox compile and assemble rules
# -------------------------------------------------

$(OUTDIR)/libneox/cc65/%.o: libneox/cc65/%.asm | dirs
	$(AS) --cpu W65C02 -g -I $(INCDIR) \
		--create-dep $(OUTDIR)/libneox/cc65/$*.d \
		-l $(OUTDIR)/libneox/cc65/$*.lst \
		-o $@ $<

$(OUTDIR)/libneox/%.s: libneox/%.c | dirs
	$(CC) $(CFLAGS) -o $@ $<

$(OUTDIR)/libneox/%.o: $(OUTDIR)/libneox/%.s | dirs
	$(AS) --cpu W65C02 -g -I $(INCDIR) \
		-l $(OUTDIR)/libneox/$*.lst \
		-o $@ $<




# -------------------------------------------------
# Aggregate assembler listings
# -------------------------------------------------

$(SYS_LST): $(SYS_PART_LSTS)
	$(CAT) $^ > $@

$(KRN_LST): $(KRN_PART_LSTS)
	$(CAT) $^ > $@

$(USR_LST): $(USR_PART_LSTS) $(USER_C_LSTS) $(LIBNEOX_C_LSTS)
	$(CAT) $^ > $@

listings: $(SYS_LST) $(KRN_LST) $(USR_LST)

# -------------------------------------------------
# Directories
# -------------------------------------------------

dirs:
	$(MKDIR) $(OUTDIR)
	$(MKDIR) $(OUTDIR)/kernel
	$(MKDIR) $(OUTDIR)/user
	$(MKDIR) $(OUTDIR)/user/task
	$(MKDIR) $(OUTDIR)/user/shell
	$(MKDIR) $(OUTDIR)/user/nbox
	$(MKDIR) $(OUTDIR)/user/applets
	$(MKDIR) $(OUTDIR)/user/lib
	$(MKDIR) $(OUTDIR)/libneox/common
	$(MKDIR) $(OUTDIR)/libneox/cc65

# -------------------------------------------------
# Install
# -------------------------------------------------

install: $(SYS_ROM) $(KRN_ROM) $(USR_ROM)
	$(CP) $(SYS_ROM) $(INSTALL_DIR)
	$(CP) $(KRN_ROM) $(INSTALL_DIR)
	$(CP) $(USR_ROM) $(INSTALL_DIR)

# -------------------------------------------------
# Utilities
# -------------------------------------------------

print:
	@echo "Syscall BIN:  $(SYS_BIN)"
	@echo "Syscall ROM:  $(SYS_ROM)"
	@echo "Syscall MAP:  $(SYS_MAP)"
	@echo "Syscall LBL:  $(SYS_LBL)"
	@echo "Syscall LST:  $(SYS_LST)"
	@echo "Syscall DIS:  $(SYS_DIS)"
	@echo
	@echo "Kernel  BIN:  $(KRN_BIN)"
	@echo "Kernel  ROM:  $(KRN_ROM)"
	@echo "Kernel  MAP:  $(KRN_MAP)"
	@echo "Kernel  LBL:  $(KRN_LBL)"
	@echo "Kernel  LST:  $(KRN_LST)"
	@echo "Kernel  DIS:  $(KRN_DIS)"
	@echo
	@echo "User    BIN:  $(USR_BIN)"
	@echo "User    ROM:  $(USR_ROM)"
	@echo "User    MAP:  $(USR_MAP)"
	@echo "User    LBL:  $(USR_LBL)"
	@echo "User    LST:  $(USR_LST)"
	@echo "User    DIS:  $(USR_DIS)"
	@echo
	@echo "Kernel objects:"
	@printf "  %s\n" $(KRN_OBJS)
	@echo "User objects:"
	@printf "  %s\n" $(USR_OBJS)
	@echo "Get address kernel: $(GETADDRKRN)"
	@echo "Get address user:   $(GETADDRUSR)"

clean:
	$(RMDIR) $(OUTDIR)

distclean: clean

-include $(KRN_DEPS)
-include $(USR_DEPS)
-include $(USERLIB_DEPS)
