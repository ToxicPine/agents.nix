{
  description = "NixOS modules for locally hosted coding agents";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      codexModule = import ./modules/codex-remote-control.nix { inherit nixpkgs; };
    in
    {
      nixosModules.default = codexModule;
      nixosModules.codex-remote-control = codexModule;

      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "agents-nix-fmt";
          runtimeInputs = [ pkgs.nixfmt ];
          text = ''
            if [ "$#" -eq 0 ]; then
              exec nixfmt flake.nix modules/*.nix
            fi
            exec nixfmt "$@"
          '';
        }
      );

    };
}
