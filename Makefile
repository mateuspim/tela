# Muscle-memory aliases over ./tool/tela, the Docker toolchain wrapper that is
# the real entrypoint (host flutter/mise is too old for this project). Every
# target just forwards — no build logic lives here, so the rules stay in one
# place and there is nothing to keep in sync.
#
#   make deploy                      # build release + install, safely
#   make deploy DEVICE=1.2.3.4:5555  # ...connecting to a networked device first
#   make deploy EDITION=safe         # ...a different edition (default: full)
#   make signing-setup               # fetch the release key from Vaultwarden
#   make test / analyze / format / apk / shell

TELA := ./tool/tela

.DEFAULT_GOAL := help
.PHONY: help deploy signing-setup test kotlin-test ci hooks analyze format apk shell install run

help:
	@printf 'targets:\n'
	@printf '  deploy [DEVICE=host:port] [EDITION=full]  build release + adb install -r (safe)\n'
	@printf '  signing-setup              fetch the release key from Vaultwarden\n'
	@printf '  test                       run the full Dart suite\n'
	@printf '  kotlin-test                run the native (Kotlin) suite\n'
	@printf '  ci                         analyze + both suites, as the merge gate runs them\n'
	@printf '  hooks                      install the pre-merge-commit gate (once per clone)\n'
	@printf '  analyze                    static analysis (must be clean)\n'
	@printf '  format                     dart format .\n'
	@printf '  apk                        build the universal release APK\n'
	@printf '  shell                      drop into the toolchain container\n'

# The one blessed path onto a device: never `flutter install`/`run`, which wipe.
EDITION ?= full

deploy:
	$(TELA) deploy --edition $(EDITION) $(DEVICE)

signing-setup:
	$(TELA) signing-setup

test:
	$(TELA) test

# The native half. `make test` does not cover it — Dart and Kotlin are two
# suites, and both are owed before a commit that touches android/.
kotlin-test:
	$(TELA) kotlin-test

# Everything the merge gate checks, in one command, so you can find out before
# git does. Same three steps as .github/workflows/ci.yml.
ci: analyze test kotlin-test

# `core.hooksPath` is per-clone local config — it cannot be committed, so a
# fresh clone is unguarded until this runs. Also turns off fast-forward merges:
# git creates no merge commit for a fast-forward, so there is nothing for
# pre-merge-commit to hook onto and the suites would be silently skipped.
hooks:
	@git config core.hooksPath .githooks
	@git config merge.ff false
	@printf 'installed: .githooks (pre-merge-commit), merge.ff=false\n'

analyze:
	$(TELA) analyze

format:
	$(TELA) dart format .

apk:
	$(TELA) build apk --release --flavor full --dart-define=TELA_EDITION=full

shell:
	$(TELA) --shell

# Guardrail: `flutter install` and `flutter run` uninstall the app before
# reinstalling, which takes the Drift database and the Keystore-backed API key
# with it (2026-07-22: `make install` wiped a device this way). The catch-all
# below would forward `make install`/`make run` straight to them, so name them
# explicitly and fail loudly instead. `make deploy` is the safe path — it builds
# the universal APK using pubspec.yaml’s versionCode and `adb install -r`s it, never uninstalling.
install run:
	@printf 'make %s runs `flutter %s`, which UNINSTALLS first and wipes the\n' '$@' '$@' >&2
	@printf 'database and the stored API key. Use `make deploy` instead.\n' >&2
	@exit 2

# Catch-all: any other single word forwards as-is — `make devices`, `make
# doctor`, `make clean`. Flagged or multi-word commands (`build apk --release`)
# still want `./tool/tela` directly: make reads extra words as targets and
# --flags as its own options, so it cannot pass them through.
%:
	@$(TELA) $@
