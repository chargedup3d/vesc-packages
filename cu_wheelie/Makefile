VESC_TOOL ?= vesc_tool
PYTHON ?= python3

all: cu_wheelie.vescpkg

# ui.qml, version.lisp and README-gen.md are generated from these sources.
SOURCES = version ui.qml.in version.lisp.in README.md pkgdesc.qml

# Always rebuild so changes in imported sources and assets cannot be missed.
cu_wheelie.vescpkg: $(SOURCES) ../tools/build_package.py FORCE
	"$(PYTHON)" ../tools/build_package.py . --vesc-tool "$(VESC_TOOL)"

clean:
	"$(PYTHON)" ../tools/build_package.py . --clean

FORCE:
.PHONY: all clean FORCE
