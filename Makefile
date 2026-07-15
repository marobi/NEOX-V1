# -------------------------------------------------
# Toolchain
# -------------------------------------------------

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
OUTDIR      := out

SYS_TARGET  := neox_syscall
KRN_TARGET  := neox_kernel
USR_TARGET  := neox_user

SYS_CFG     := ./build/neox_syscall.cfg
KRN_CFG     := ./build/neox_kernel.cfg
USR_CFG     := ./build/neox_user.cfg

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

NBOX_BASE := user
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
	user/user_space.asm \
	user/neosh.asm \
	$(NBOX_SRCS)

# Optional user library objects
USERLIB_SRCS := 

# -------------------------------------------------
# Derived objects / listings
# -------------------------------------------------

SYS_OBJS      := $(SYSCALL_SRCS:%.asm=$(OUTDIR)/%.o)
KRN_OBJS      := $(KERNEL_SRCS:%.asm=$(OUTDIR)/%.o)
USR_OBJS      := $(USER_SRCS:%.asm=$(OUTDIR)/%.o)
USERLIB_OBJS  := $(USERLIB_SRCS:%.asm=$(OUTDIR)/%.o)

SYS_PART_LSTS := $(SYSCALL_SRCS:%.asm=$(OUTDIR)/%.lst)
KRN_PART_LSTS := $(KERNEL_SRCS:%.asm=$(OUTDIR)/%.lst)
USR_PART_LSTS := $(USER_SRCS:%.asm=$(OUTDIR)/%.lst)
USERLIB_LSTS  := $(USERLIB_SRCS:%.asm=$(OUTDIR)/%.lst)

# -------------------------------------------------
# Default target
# -------------------------------------------------

.PHONY: all clean distclean install print dirs listings disasm
all: $(SYS_ROM) $(KRN_ROM) $(USR_ROM) $(SYS_DIS) $(KRN_DIS) $(USR_DIS)

SYS_DEPS      := $(SYSCALL_SRCS:%.asm=$(OUTDIR)/%.d)
KRN_DEPS      := $(KERNEL_SRCS:%.asm=$(OUTDIR)/%.d)
USR_DEPS      := $(USER_SRCS:%.asm=$(OUTDIR)/%.d)
USERLIB_DEPS  := $(USERLIB_SRCS:%.asm=$(OUTDIR)/%.d)

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

$(USR_BIN): $(USR_OBJS) $(USR_CFG) | dirs
	$(LD) -C $(USR_CFG) -vm -m $(USR_MAP) -Ln $(USR_LBL) -o $@ $(USR_OBJS)

# -------------------------------------------------
# Python disassembly output
# -------------------------------------------------

$(SYS_DIS): $(SYS_BIN) $(SYS_MAP) $(SYS_LBL) $(DISASM) | dirs
	$(PYTHON) $(DISASM) $(SYS_BIN) C000 $(SYS_MAP) $(SYS_LBL) > $@

$(KRN_DIS): $(KRN_BIN) $(KRN_MAP) $(KRN_LBL) $(DISASM) | dirs
	$(PYTHON) $(DISASM) $(KRN_BIN) 6000 $(KRN_MAP) $(KRN_LBL) > $@

$(USR_DIS): $(USR_BIN) $(USR_MAP) $(USR_LBL) $(DISASM) | dirs
	$(PYTHON) $(DISASM) $(USR_BIN) 2000 $(USR_MAP) $(USR_LBL) > $@

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
# Aggregate assembler listings
# -------------------------------------------------

$(SYS_LST): $(SYS_PART_LSTS)
	$(CAT) $^ > $@

$(KRN_LST): $(KRN_PART_LSTS)
	$(CAT) $^ > $@

$(USR_LST): $(USR_PART_LSTS)
	$(CAT) $^ > $@

listings: $(SYS_LST) $(KRN_LST) $(USR_LIST)

# -------------------------------------------------
# Directories
# -------------------------------------------------

dirs:
	$(MKDIR) $(OUTDIR)
	$(MKDIR) $(OUTDIR)/kernel
	$(MKDIR) $(OUTDIR)/user
	$(MKDIR) $(OUTDIR)/user/applets
	$(MKDIR) $(OUTDIR)/user/lib

# -------------------------------------------------
# Install
# -------------------------------------------------

install: $(SYS_ROM) $(KRN_ROM)
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
	@echo "Syscall objects:"
	@printf "  %s\n" $(SYS_OBJS)
	@echo "Kernel objects:"
	@printf "  %s\n" $(KRN_OBJS)
	@echo "Userlib objects:"
	@printf "  %s\n" $(USERLIB_OBJS)
	@echo
	@echo "Syscall listings:"
	@printf "  %s\n" $(SYS_PART_LSTS)
	@echo "Kernel listings:"
	@printf "  %s\n" $(KRN_PART_LSTS)
	@echo "Userlib listings:"
	@printf "  %s\n" $(USERLIB_LSTS)
	@echo
	@echo "Disassembler:        $(DISASM)"
	@echo "Get address syscall: $(GETADDRSYS)"
	@echo "Get address kernel:  $(GETADDRKRN)"
	@echo "Get address user:    $(GETADDRUSR)"
	@echo "Dependency files:"
	@printf "  %s\n" $(SYS_DEPS) $(KRN_DEPS) $(USR_DEPS) $(USERLIB_DEPS)
	
clean:
	$(RMDIR) $(OUTDIR)

distclean: clean

-include $(SYS_DEPS)
-include $(KRN_DEPS)
-include $(USR_DEPS)
-include $(USERLIB_DEPS)
