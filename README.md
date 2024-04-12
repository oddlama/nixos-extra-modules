[Installation](#installation)

# 🍵 nixos-extra-modules

This repository contains extra modules for nixos that are very opinionated and mainly
useful to me and my colleagues. All modules in here are opt-in, so nothing will
be changed unless you decide you want to use that specific module.

## Overview

#### NixOS Modules

| Name | Type | Source | Requires | Optional deps | Description |
|---|---|---|---|---|---|
Networking library and extensions | Lib | [Link](./lib/net.nix) | - | - | Integrates [this libary](https://gist.github.com/duairc/5c9bb3c922e5d501a1edb9e7b3b845ba) which adds option types for IPs, CIDRs, MACs, and more. Also adds some extensions for missing functions and cross-node hashtable-based lazy IP/MAC assignment.
Interface naming by MAC | Module | [Link](./modules/interface-naming.nix) | - | - | Allows you to define pairs of MAC address and interface name which will be enforced via udev as early as possible.
EFI/BIOS boot config | Module | [Link](./modules/boot.nix) | - | - | Allows you to specify a boot type (bios/efi) and the correct loader will automatically be configured
Nginx recommended options | Module | [Link](./modules/nginx.nix) | - | agenix | Sets many recommended settings for nginx with a single switch plus some opinionated defaults. Also adds a switch for setting recommended security headers on each location.
Node options | Module | [Link](./modules/node.nix) | - | - | A module that stores meta information about your nodes (hosts). Required for some other modules that operate across nodes.
Guests (MicroVMs & Containers) | Module | [Link](./modules/guests) | zfs, disko, node options | - | This module implements a common interface to use guest systems with microvms or nixos-containers.
Restic hetzner storage box setup | Module | [Link](./modules/restic.nix) | agenix, agenix-rekey | - | This module exposes new options for restic backups that allow a simple setup of hetzner storage boxes. There's [an app](./apps/setup-hetzner-storage-boxes.nix) that you should expose on your flake to automate remote setup.
Wireguard overlay networks | Module | [Link](./modules/wireguard.nix) | agenix, agenix-rekey, nftables-firewall, inputs.self.nodes | - | This module automatically creates cross-node wireguard networks including automatic semi-stable ip address assignments
nix-topology for wireguard | Module | [Link](./modules/topology-wireguard.nix) | nix-topology | - | This module automatically adds wireguard networks and interfaces based on the wireguard configuration from our wireguard module

#### Home Manager Modules

| Name | Type | Source | Requires | Optional deps | Description |
|---|---|---|---|---|---|
i3 systemd targets | Module | [Link](./hm-modules/i3.nix) | - | - | Makes i3 setup and reach graphical-session.target so that other services are properly executed.
Wallpapers | Module | [Link](./hm-modules/wallpapers.nix) | - | - | A simple wallpaper service that changes the wallpaper of each monitor to a random image after a specified interval.

## Installation

To use the extra modules, you will have to add this project to your `flake.nix`,
and import the provided main NixOS module in your hosts. Afterwards the new options
will be available.

Certain modules may require the use of additional flakes. In particular
depending on the modules you want to use, you might need:

- [agenix](https://github.com/ryantm/agenix)
- [agenix-rekey](https://github.com/oddlama/agenix-rekey)
- [disko](https://github.com/nix-community/disko)
- [home-manager](https://github.com/nix-community/home-manager)
- [impermanence](https://github.com/nix-community/impermanence)
- [microvm.nix](https://github.com/astro/microvm.nix)

You also must have a `specialArgs.inputs` that refers to all of your flake's inputs,
and `inputs.self.pkgs.${system}` must refer to an initialized package set for that
specific system that includes extra-modules as an overlay.

All cross-node configuration modules (like wireguard) require you to expose
all relevant nodes in your flake as `inputs.self.nodes`, so their configuration
can be accessed by other nodes.

Here's an example configuration:

```nix
{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    nixos-extra-modules = {
      url = "github:oddlama/nixos-extra-modules";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Additional inputs, may or may not be needed for a particular module or extension.
    # Enable what you use.

    # agenix = {
    #   url = "github:ryantm/agenix";
    #   inputs.home-manager.follows = "home-manager";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    #
    # agenix-rekey = {
    #   url = "github:oddlama/agenix-rekey";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.flake-utils.follows = "flake-utils";
    # };
    #
    # disko = {
    #   url = "github:nix-community/disko";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    #
    # home-manager = {
    #   url = "github:nix-community/home-manager";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    #
    # impermanence.url = "github:nix-community/impermanence";
    #
    # microvm = {
    #   url = "github:astro/microvm.nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.flake-utils.follows = "flake-utils";
    # };
  };

  outputs = {
    self,
    nixos-extra-modules,
    flake-utils,
    nixpkgs,
    ...
  } @ inputs: {
    # Example system configuration
    nixosConfigurations.yourhostname = let
      system = "x86_64-linux";
      pkgs = self.pkgs.${system};
    in nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./configuration.nix
        nixos-extra-modules.nixosModules.default
        {
          # We cannot force the package set via nixpkgs.pkgs and
          # inputs.nixpkgs.nixosModules.readOnlyPkgs, since nixosModules
          # should be able to dynamicall add overlays via nixpkgs.overlays.
          # So we just mimic the options and overlays defined by the passed pkgs set
          # to not lose what we already have defined below.
          nixpkgs.hostPlatform = system;
          nixpkgs.overlays = pkgs.overlays;
          nixpkgs.config = pkgs.config;
        }
      ];
      specialArgs = {
        inherit inputs;
        # Very important to inherit lib here, so that the additional
        # lib overlays are available early.
        inherit (pkgs) lib;
      };
    };

    # Required for cross-node configuration like in the wireguard module
    nodes = self.nixosConfigurations;
  }
  // flake-utils.lib.eachDefaultSystem (system: rec {
    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        nixos-extra-modules.overlays.default
        # (enable hird-party modules if needed)
        # agenix-rekey.overlays.default
        # ...
      ];
    };
  }
}
```
