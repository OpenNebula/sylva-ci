#!/usr/bin/env bash

((!DETACHED)) && DETACHED=1 exec setsid --fork "$SHELL" "$0" "$@"

set -e -o pipefail

# Load context mounted as ISO9660 device
: "${CONTEXT_PATH:=/dev/sr0}"
source <(isoinfo -i "$CONTEXT_PATH" -R -x /context.sh)

: "${SYLVA_CI_GIT_URL:=$1}"
: "${SYLVA_CI_GIT_REV:=$2}"

set -u

# Clone Sylva CI repository
if [[ ! -e /opt/sylva-ci/ ]]; then
    git clone -b "$SYLVA_CI_GIT_REV" "$SYLVA_CI_GIT_URL" /opt/sylva-ci/
fi

# Hostname configuration
install -o 0 -g 0 -m u=rw,go=r /dev/fd/0 /etc/nixos/configuration.nix.d/01-hostname.nix <<NIX
{ ... }: { networking.hostName = "$SET_HOSTNAME"; }
NIX

# Nix package manager configuration
install -o 0 -g 0 -m u=rw,go=r /dev/fd/0 /etc/nixos/configuration.nix.d/02-flakes.nix <<NIX
{ pkgs, ... }: {
  nix = {
    settings = {
      experimental-features = "nix-command flakes";
      sandbox = false;
      trusted-users = ["root"];
    };
    buildMachines = [{
      hostName = "localhost";
      protocol = null;
      system = "x86_64-linux";
      supportedFeatures = ["kvm" "nixos-test" "big-parallel" "benchmark"];
      maxJobs = 1;
      speedFactor = 1;
    }];
    gc = {
      automatic = true;
      dates = "weekly";
    };
  };
}
NIX

# Apply NixOS configuration changes
nixos-rebuild switch

# Docker registry configuration
install -o 0 -g 0 -m u=rw,go=r /dev/fd/0 /etc/nixos/configuration.nix.d/03-docker.nix <<NIX
{ ... }: {
  services.dockerRegistry = {
    enable = true;
    enableDelete = true;
    enableGarbageCollect = true;
    garbageCollectDates = "weekly";
    listenAddress = "0.0.0.0";
    port = 5000;
    storagePath = "/var/lib/docker-registry/";
    extraConfig = {
      proxy.remoteurl = "https://registry-1.docker.io";
    };
  };
  systemd.services.docker-registry = {
    environment = { OTEL_TRACES_EXPORTER = "none"; };
    overrideStrategy = "asDropinIfExists";
  };
}
NIX

# Sylva CI service configuration from sylva-ci flake (includes Redis configuration)
install -o 0 -g 0 -m u=rw,go=r /dev/fd/0 /etc/nixos/configuration.nix.d/04-services.nix <<NIX
{ pkgs, ... }: {
  imports = [
    (builtins.getFlake "path:/opt/sylva-ci").nixosModules.x86_64-linux.default
  ];
  environment.systemPackages = with pkgs; [
    (builtins.getFlake "path:/opt/sylva-ci").packages.x86_64-linux.default
  ];
  services = {
    redis.servers."sylva-ci" = {
      enable = true;
      bind = "127.0.0.1";
      port = 6379;
      extraParams = ["--protected-mode no"];
    };
    sylva-ci = {
      enable = true;
    };
  };
}
NIX

# Sets a timer job to report Sylva CI results on upstream gitlab project
# each weekday at 5am CET, and deletes the local logs older than 10 days
# (logs are saved under /var/tmp/sylva-ci/logs/)
install -o 0 -g 0 -m u=rw,go=r /dev/fd/0 /etc/nixos/configuration.nix.d/05-timers.nix <<NIX
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    ruby
  ];
  systemd = {
    timers."report-sylva-ci" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Mon..Fri 05:00 CET";
        Unit = "report-sylva-ci.service";
      };
    };
    services."report-sylva-ci" = {
      serviceConfig = {
        Type = "oneshot";
      };
      path = with pkgs; [ cdrkit findutils ruby ];
      script = ''
        set -ea
        source <(isoinfo -i "$CONTEXT_PATH" -R -x /context.sh)
        ruby /opt/sylva-ci/report-sylva-ci.rb
        find /var/tmp/sylva-ci/logs/ -mindepth 1 -maxdepth 1 -type d -mtime +10 -exec rm --preserve-root -vrf {} +
      '';
    };
  };
}
NIX

nixos-rebuild switch

sync
