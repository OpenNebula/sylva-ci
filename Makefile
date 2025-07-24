SHELL := $(shell which bash)
SELF  := $(patsubst %/,%,$(dir $(abspath $(firstword $(MAKEFILE_LIST)))))

export

.PHONY: all

all:

.PHONY: init plan apply destroy

init plan:
	terraform $@

apply destroy: TF_LOG ?= INFO
apply destroy: init
	terraform $@ --auto-approve

.PHONY: run

run:
	nix run

.PHONY: touch check

touch:
	cd $(SELF)/scenario/ && \
	nix flake update --override-input entropy file+file://<(TZ=CET date)

check:
	cd $(SELF)/scenario/ && \
	nix flake check --option sandbox false --print-build-logs

define ADD_TEST =
.PHONY: test-$(1)

test-$(1):
	cd $(SELF)/scenario/ && \
	nix build --option sandbox false --print-build-logs '.#checks.x86_64-linux.sylva-ci-$(1)' --rebuild || \
	nix build --option sandbox false --print-build-logs '.#checks.x86_64-linux.sylva-ci-$(1)'
endef

$(eval $(call ADD_TEST,deploy-rke2))
$(eval $(call ADD_TEST,deploy-kubeadm))
