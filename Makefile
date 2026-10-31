# Generic make scripts to build a program from the repo root:
#
#     make example
#
# compiles example.d into example (example.exe on Windows), first
# generating example.d from example.fl with `fluid -c` when there is an
# example.fl newer than it. The library is built with `dub build` if it
# isn't there yet; Fluid itself is built with `rdmd buildfluid.d`.
#
# Needs GNU make (on Windows, e.g. from a Cygwin shell) and dmd.

ifeq ($(OS),Windows_NT)
FLDTK_LIB = fldtk.lib
LINK = $(FLDTK_LIB) gdi32.lib user32.lib kernel32.lib msvcrt120.lib \
       oldnames.lib ole32.lib gdiplus.lib opengl32.lib glu32.lib \
       msimg32.lib shell32.lib comdlg32.lib imm32.lib
else
FLDTK_LIB = libfldtk.so
LINK = -L-L. -L-lfldtk -L-rpath=$(CURDIR)
endif

FLUID ?= ./fluid

# example: example.d -> example(.exe). dmd names the program after its
# first source file.
%: %.d $(FLDTK_LIB)
	dmd $< -Isource $(LINK)

%.exe: %.d $(FLDTK_LIB)
	dmd $< -Isource $(LINK)

# example.d from example.fl.
%.d: %.fl
	$(FLUID) -c $<

# A generated .d is kept, like a hand-written one.
.PRECIOUS: %.d

$(FLDTK_LIB):
	dub build

# Keep the match-anything rule above from trying to rebuild this file.
Makefile: ;
