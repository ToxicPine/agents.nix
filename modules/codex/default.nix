{ nixpkgs }:
{
  config,
  lib,
  pkgs,
  options,
  ...
}:

let
  isDarwin = options ? launchd;
  cfg = config.services.codex-remote-control;
in
{
  options.services.codex-remote-control = {
    enable = lib.mkEnableOption "a supervised Codex server for SSH and remote control";

    user = lib.mkOption {
      type = lib.types.str;
      description = "Existing normal user account that runs Codex.";
      example = "alice";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.codex;
      defaultText = lib.literalExpression "Codex from agents.nix's independently pinned nixpkgs-unstable";
      description = "Codex package to run. Defaults to this flake's locked nixpkgs-unstable package.";
    };

  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion =
              cfg.user != ""
              && (
                if pkgs.stdenv.hostPlatform.isDarwin then
                  config.users.users.${cfg.user}.home != null
                else
                  config.users.users.${cfg.user}.isNormalUser
              );
            message = "services.codex-remote-control.user must name an existing normal user account.";
          }
        ];

      }
      (
        if !isDarwin then
          {
            users.users.${cfg.user} = {
              linger = lib.mkDefault true;
              packages = [ cfg.package ];
            };

            systemd.user.services.codex-daemon = {
              description = lib.mkDefault "Codex app server with SSH and remote control";
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = cfg.user;
              enableDefaultPath = lib.mkDefault false;

              serviceConfig = {
                Type = lib.mkDefault "exec";
                WorkingDirectory = lib.mkDefault "%h";
                ExecStart = lib.mkDefault "${lib.getExe cfg.package} app-server --listen unix:// --remote-control";
                Restart = lib.mkDefault "on-failure";
                RestartSec = lib.mkDefault "5s";
              };
            };
          }
        else
          {
            users.users.${cfg.user}.packages = [ cfg.package ];
            launchd.daemons.codex-daemon = (import ../lib/darwin-service.nix { inherit config lib pkgs; }) {
              name = "codex-daemon";
              inherit (cfg) user;
              command = [
                (lib.getExe cfg.package)
                "app-server"
                "--listen"
                "unix://"
                "--remote-control"
              ];
            };
          }
      )
    ]
  );
}
