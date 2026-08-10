.PHONY: check test install cluster-system cluster-user

check:
	./scripts/check.sh

test: check
	./scripts/test.sh

install:
	./install.sh

cluster-system:
	./install.sh --cluster --system-only

cluster-user:
	./install.sh --cluster --user-only
