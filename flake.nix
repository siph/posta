{
  description = "Blogging backend as a service built with SurrealDB.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # TODO: Last version of `2.x.x`, remove when surrealist is updated to support `3.x.x`
    surrealdb-flake.url = "github:surrealdb/surrealdb/bdd9f2e334fcaa43e154ffe29f0006b5ab064235";
  };

  outputs = inputs @ {
    flake-parts,
    nixpkgs,
    surrealdb-flake,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem = {
        config,
        lib,
        pkgs,
        self',
        system,
        ...
      }:
        with pkgs; {
          formatter = pkgs.alejandra;

          _module.args.pkgs = import nixpkgs {
            inherit system;

            config = {
              allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ["surrealdb"];
            };

            overlays = [
              (final: prev: {
                surrealdb = surrealdb-flake.packages.${system}.default;
              })
            ];
          };

          checks = {
            posta-tests = with pkgs;
              stdenv.mkDerivation {
                inherit system;
                name = "posta tests";
                src = ./.;
                buildInputs = [
                  nushell
                  surrealdb
                ];
                buildPhase = ''
                  ${nushell}/bin/nu \
                    --no-config-file \
                    ./tests/mod.nu
                '';
                installPhase = ''
                  touch $out
                '';
              };
          };

          devShells = with pkgs; {
            default = mkShell {
              buildInputs = [
                nushell
                surrealdb
              ];
            };
          };
        };
    };
}
