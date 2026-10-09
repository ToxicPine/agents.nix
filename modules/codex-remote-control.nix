{ nixpkgs }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.codex-remote-control;
in
{
  options.services.codex-remote-control = {
    enable = lib.mkEnableOption "a systemd-supervised Codex server for SSH and remote control";

    user = lib.mkOption {
      type = lib.types.str;
      description = "Existing normal user account that runs Codex.";
      example = "alice";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.codex;
      defaultText = lib.literalExpression "agents.nix's pinned unstable Codex package";
      description = "Codex package to run. Defaults to this flake's locked nixos-unstable package.";
    };

  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != "" && config.users.users.${cfg.user}.isNormalUser;
        message = "services.codex-remote-control.user must name an existing normal user account.";
      }
    ];

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
  };
}
