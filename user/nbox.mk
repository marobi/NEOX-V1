# -------------------------------------------------
# nbox module sources
#
# NBOX_BASE defaults to user for root builds.
# A later standalone user/Makefile can set NBOX_BASE := .
# before including this file.
# -------------------------------------------------

NBOX_BASE ?= user
NBOX_APPLET_BASE := $(NBOX_BASE)/applets

NBOX_SRCS := \
	$(NBOX_BASE)/nbox.asm \
	$(NBOX_APPLET_BASE)/applet_scratch.asm \
	$(NBOX_APPLET_BASE)/help.asm \
	$(NBOX_APPLET_BASE)/pwd.asm \
	$(NBOX_APPLET_BASE)/cd.asm \
	$(NBOX_APPLET_BASE)/ls.asm \
	$(NBOX_APPLET_BASE)/cat.asm \
	$(NBOX_APPLET_BASE)/echo.asm \
	$(NBOX_APPLET_BASE)/rm.asm \
	$(NBOX_APPLET_BASE)/mv.asm \
	$(NBOX_APPLET_BASE)/mkdir.asm \
	$(NBOX_APPLET_BASE)/rmdir.asm \
	$(NBOX_APPLET_BASE)/cp.asm \
	$(NBOX_APPLET_BASE)/ps.asm

NBOX_OBJS := $(NBOX_SRCS:%.asm=$(OUTDIR)/%.o)
NBOX_LSTS := $(NBOX_SRCS:%.asm=$(OUTDIR)/%.lst)
NBOX_DEPS := $(NBOX_SRCS:%.asm=$(OUTDIR)/%.d)
