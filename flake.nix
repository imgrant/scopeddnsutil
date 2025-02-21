{
  description = "A tool to configure scoped DNS resolvers on macOS";

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2411.*";

  outputs = { nixpkgs, ... }:
    let
      forAllSystems = gen:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed
        (system: gen nixpkgs.legacyPackages.${system});
    in {
      packages = forAllSystems (pkgs: { default = pkgs.callPackage ./. { }; });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell.override { inherit (pkgs.swiftPackages) stdenv; } {
          buildInputs = [ pkgs.swift pkgs.swiftpm pkgs.swiftpm2nix pkgs.swiftPackages.Foundation ];
          LD_LIBRARY_PATH = "${pkgs.swiftPackages.Dispatch}/lib";
        };
      });
    };
}