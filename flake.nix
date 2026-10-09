{
  description = "NixOS modules for locally hosted coding agents";

  inputs.llm-agents.url = "github:numtide/llm-agents.nix";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.xs.url = "github:cablehead/xs";

  outputs =
    {
      nixpkgs,
      llm-agents,
      xs,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      codexModule = import ./modules/codex-remote-control.nix { inherit nixpkgs; };
      t3codeModule = import ./modules/t3code.nix { inherit llm-agents; };
      xsModule = import ./modules/xs.nix { inherit xs; };
    in
    {
      nixosModules.default = {
        imports = [
          ./modules/cache.nix
          ./modules/skills.nix
          codexModule
          t3codeModule
          xsModule
        ];
      };
      nixosModules.codex-remote-control = codexModule;
      nixosModules.t3code = t3codeModule;
      nixosModules.skills = ./modules/skills.nix;
      nixosModules.xs = xsModule;

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
