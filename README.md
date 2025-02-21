# scopeddnsutil — a scoped DNS helper tool for macOS

This tool is a command-line helper for managing scoped DNS configurations on macOS. It adds or removes DNS resolvers to use for specific domains and IP ranges, so-called *split-horizon* or scoped DNS.

The use-case could be, for example, to add a private, scoped DNS resolver for use with a VPN connection, sending only specific DNS queries to a resolver reachable via the VPN tunnel. The scoped DNS configuration could then be removed when the VPN connection is turned off.

## Features

- Configure domain-specific DNS resolvers
- Support for multiple domains and DNS servers
- Support for reverse DNS zones using CIDR notation
- Automatic conversion between CIDR and `in-addr.arpa` formats
- Easy addition and removal of configurations

## Installation

### Use in a Nix (flakes) configuration with [nix-darwin](https://daiderd.com/nix-darwin/)

Add the repository as an input in your flake:

```nix
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2411.*";
    
    scopeddnsutil = {
      url = "github:imgrant/scopeddnsutil";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
```

Include it in your outputs section, and pass it to, eg `environment.systemPackages` in a `darwinConfiguration`:

```nix
  outputs = { self, nixpkgs, scopeddnsutil, ... }: {
    darwinConfigurations.your-machine = darwin.lib.darwinSystem {
      system = "aarch64-darwin";  # or "x86_64-darwin" for Intel Macs
      modules = [
        {
          environment.systemPackages = [
            scopeddnsutil.packages.${pkgs.system}.default
          ];
        }
      ];
    };
  };
```

You could specify the package in `home.packages` to install it as a user-specific package via [Home Manager](https://nix-community.github.io/home-manager/) instead.

### Ad hoc usage from the command line with Nix

#### Run the program directly

```bash
nix run github:imgrant/scopeddnsutil
```

#### Start a shell with the program available

```bash
nix shell github:imgrant/scopeddnsutil
```

#### Build it as a standalone binary

```bash
nix build github:imgrant/scopeddnsutil
```

### Build using the Swift package manager

```bash
swift build -c release
```

The binary will be available at `.build/release/scopeddnsutil`.

## Usage

```bash
scopeddnsutil [add|remove] [options]

Required Options:
  -r, --resolvers <ip>[,<ip>...]   IP address(es) of DNS resolvers
  -d, --domains <domain>[,...]     Domain(s) to scope these resolvers for

Optional:
  -i, --cidrs <cidr>[,...]         IP address ranges in CIDR notation
  -v, --verbose                    Show detailed output
  -q, --quiet                      Suppress all output
  -h, --help                       Show this help message
```

### Examples

#### Add a scoped DNS configuration

```bash
$ sudo scopeddnsutil add \
  --domains "example.com" \
  --resolvers "203.0.113.1"
Added scoped DNS entry
```

Afterwards, you can use `scutil` to confirm that the configuration is working:

```bash
$ scutil --dns
DNS configuration

resolver #1
  search domain[0] : example.com
  search domain[1] : lan
  nameserver[0] : 198.51.100.1
  if_index : 14 (en0)
  flags    : Request A records
  reach    : 0x00020002 (Reachable,Directly Reachable Address)

resolver #2
  domain   : example.com
  nameserver[0] : 203.0.113.1
  flags    : Supplemental, Request A records
  reach    : 0x00000002 (Reachable)
  order    : 103000

...
```

#### Remove a scoped DNS configuration

```bash
$ sudo scopeddnsutil remove \
  --domains "example.com" \
  --resolvers "203.0.113.1"
Removed scoped DNS entry
```

Confirm that the scoped configuration has been removed:

```bash
$ scutil --dns
DNS configuration

resolver #1
  search domain[0] : lan
  nameserver[0] : 198.51.100.1
  if_index : 14 (en0)
  flags    : Request A records
  reach    : 0x00020002 (Reachable,Directly Reachable Address)

resolver #2
  domain   : local
  options  : mdns
  timeout  : 5
  flags    : Request A records
  reach    : 0x00000000 (Not Reachable)
  order    : 300000

...
```

## Requirements

- macOS 13 or later
- Administrator privileges (`sudo`) for modifying DNS configuration

## Disclaimer

> [!WARNING]
> An AI code assistant was used to write this program. I'm not a macOS developer, nor have used
> Swift before—there ~~may~~ ***will*** be bugs.

The reverse lookup zones and CIDR processing is particularly suspect; it handles the common cases like `/8`, `/24` or `172.16.0.0/12` fine, but could make mistakes with more complex values. *Caveat emptor*.

## Acknowledgements

The Nix derivation and flake were copied from [Samasaur1/nix-swift-hello](https://github.com/Samasaur1/nix-swift-hello/).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
