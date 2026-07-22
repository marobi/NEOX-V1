# -------------------------------------------------
# nbox component
# -------------------------------------------------

NBOX_BASE ?= user/nbox

NBOX_SRCS := \
	$(NBOX_BASE)/nbox_child.asm

NBOX_C_SRCS := \
	$(NBOX_BASE)/nbox.c

NBOX_OBJS := $(NBOX_SRCS:%.asm=$(OUTDIR)/%.o)
NBOX_C_OBJS := $(NBOX_C_SRCS:%.c=$(OUTDIR)/%.o)
NBOX_LSTS := $(NBOX_SRCS:%.asm=$(OUTDIR)/%.lst)
NBOX_C_LSTS := $(NBOX_C_SRCS:%.c=$(OUTDIR)/%.lst)
NBOX_DEPS := $(NBOX_SRCS:%.asm=$(OUTDIR)/%.d)
