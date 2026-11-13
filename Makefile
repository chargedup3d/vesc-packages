# Same package-folder/resource-archive layout as vedderb/vesc_pkg.
VESC_TOOL ?= vesc_tool
PYTHON ?= python3
RCC ?= rcc
CROSS_COMPILE ?= arm-none-eabi-
export VESC_TOOL PYTHON CROSS_COMPILE

PKGS = cu_express_link cu_esc_base cu_dash cu_wheelie cu_imu cu_io cu_link

all: vesc_pkg_all.rcc

packages: $(PKGS)

vesc_pkg_all.rcc: packages res_all.qrc
	@set -eu; tmp=$$(mktemp "$@.XXXXXX"); \
	trap 'rm -f "$$tmp"' EXIT; trap 'exit 1' HUP INT TERM; \
	"$(RCC)" --format-version 1 -no-compress -binary res_all.qrc -o "$$tmp"; \
	test -s "$$tmp"; mv -f "$$tmp" "$@"

$(PKGS):
	$(MAKE) -C $@

clean:
	@for pkg in $(PKGS); do $(MAKE) -C "$$pkg" clean || exit $$?; done
	rm -f vesc_pkg_all.rcc vesc_pkg_all.rcc.*

.PHONY: all packages clean $(PKGS)
