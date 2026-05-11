{
  description = "Git Remote Integrity Guard (GRIG)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Native dependencies required by the libgit2 and libssh2 C-bindings
        nativeBuildInputs = with pkgs; [
          pkg-config
          cmake
          makeWrapper
        ];

        # Library dependencies linked during compilation
        buildInputs = with pkgs; [
          openssl
          libssh2
          zlib
        ] ++ lib.optionals stdenv.isDarwin [
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.SystemConfiguration
        ];

      in
      {
        # Native Nix package build
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "grig";
          version = "0.1.0";
          
          src = ./.;

          # Points to the lockfile to ensure reproducible builds
          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          inherit nativeBuildInputs buildInputs;

          # Setting this to false is common for git tools in Nix, 
          # as libgit2 tests often try to reach the network or read global ~/.gitconfig
          doCheck = false; 
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          inherit nativeBuildInputs buildInputs;

          # Tools available in the 'nix develop' environment
          packages = with pkgs; [
            cargo
            rustc
            rust-analyzer
            rustfmt
            clippy
            jq
          ];

          shellHook = ''
            echo "🦀 GRIG Rust Development Environment Loaded"
            export RUST_BACKTRACE=1
          '';
        };
      }
    );
}
