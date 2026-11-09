{
  description = "NixOS and nix-darwin modules for locally hosted coding agents";

  inputs = {
    llm-agents.url = "github:numtide/llm-agents.nix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    xs.url = "github:cablehead/xs";
  };

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
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      codexModule = import ./modules/codex { inherit nixpkgs; };
      t3codeModule = import ./modules/t3code { inherit llm-agents nixpkgs; };
      xsModule = import ./modules/xs { inherit xs; };
      cliProxyApiModule = import ./modules/cli-proxy-api { inherit llm-agents; };
      t3codePackages = forAllSystems (
        system:
        import ./modules/t3code/package.nix {
          upstream = llm-agents.packages.${system}.t3code.unwrapped;
        }
      );
    in
    {
      packages = forAllSystems (system: {
        t3code = t3codePackages.${system};
      });

      checks = forAllSystems (system: {
        t3code = t3codePackages.${system};
      });

      nixosModules = {
        default = {
          imports = [
            ./modules/cache.nix
            ./modules/skills.nix
            codexModule
            xsModule
            cliProxyApiModule
          ];
        };
        codex-remote-control = codexModule;
        t3code = t3codeModule;
        skills = ./modules/skills.nix;
        xs = xsModule;
        cli-proxy-api = cliProxyApiModule;
      };

      darwinModules = {
        default = {
          imports = [
            ./modules/cache.nix
            ./modules/skills.nix
            codexModule
            xsModule
            cliProxyApiModule
          ];
        };
        codex-remote-control = codexModule;
        t3code = t3codeModule;
        skills = ./modules/skills.nix;
        xs = xsModule;
        cli-proxy-api = cliProxyApiModule;
      };

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
              exec nixfmt flake.nix modules/*.nix modules/*/*.nix
            fi
            exec nixfmt "$@"
          '';
        }
      );

    };
}
