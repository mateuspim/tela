# Muscle-memory aliases over ./tool/tela, the Docker toolchain wrapper that is
# the real entrypoint (host flutter/mise is too old for this project). Every
# target just forwards — no build logic lives here, so the rules stay in one
# place and there is nothing to keep in sync.
#
#   make deploy                      # build release + install, safely
#   make deploy DEVICE=1.2.3.4:5555  # ...connecting to a networked device first
#   make test / analyze / format / apk / shell

TELA := ./tool/tela

.DEFAULT_GOAL := help
.PHONY: help deploy test analyze format apk shell

help:
	@printf 'targets:\n'
	@printf '  deploy [DEVICE=host:port]  build release APK + adb install -r (safe)\n'
	@printf '  test                       run the full suite\n'
	@printf '  analyze                    static analysis (must be clean)\n'
	@printf '  format                     dart format .\n'
	@printf '  apk                        build the universal release APK\n'
	@printf '  shell                      drop into the toolchain container\n'

# The one blessed path onto a device: never `flutter install`/`run`, which wipe.
deploy:
	$(TELA) deploy $(DEVICE)

test:
	$(TELA) test

analyze:
	$(TELA) analyze

format:
	$(TELA) dart format .

apk:
	$(TELA) build apk --release

shell:
	$(TELA) --shell

# Catch-all: any other single word forwards as-is — `make devices`, `make
# doctor`, `make clean`. Flagged or multi-word commands (`build apk --release`)
# still want `./tool/tela` directly: make reads extra words as targets and
# --flags as its own options, so it cannot pass them through.
%:
	@$(TELA) $@
