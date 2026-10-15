{ xs }:
{
  config,
  lib,
  pkgs,
  options,
  utils,
  ...
}:
let
  isDarwin = options ? launchd;
  cfg = config.services.xs;
  host = if lib.hasInfix ":" cfg.host then "[${cfg.host}]" else cfg.host;
in
{
  options.services.xs = {
    enable = lib.mkEnableOption "a cross.stream user service";
    sandbox = lib.mkOption {
      type = if pkgs.stdenv.hostPlatform.isDarwin then lib.types.enum [ false ] else lib.types.bool;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin then
          throw "Set services.xs.sandbox = false explicitly on macOS."
        else
          true;
      defaultText = lib.literalExpression "true on Linux; explicit false on macOS";
      description = "Apply systemd sandboxing restrictions to xs.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      description = "Existing normal user account that runs xs.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = xs.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "agents.nix's pinned xs package";
    };
    host = lib.mkOption {
      type = lib.types.strMatching "[0-9a-fA-F:.]+";
      default = "127.0.0.1";
      example = "::1";
      description = "IPv4 or unbracketed IPv6 listen address. Firewall rules are configured separately.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 3021;
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !pkgs.stdenv.hostPlatform.isDarwin || !cfg.sandbox;
            message = "services.xs.sandbox requires Linux systemd sandboxing.";
          }
          {
            assertion =
              cfg.user != ""
              && (
                if pkgs.stdenv.hostPlatform.isDarwin then
                  config.users.users.${cfg.user}.home != null
                else
                  config.users.users.${cfg.user}.isNormalUser or false
              );
            message = "services.xs.user must name an existing normal user account.";
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
            systemd.user.services.xs = {
              description = "Cross.stream store";
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = cfg.user;
              enableDefaultPath = lib.mkDefault false;
              serviceConfig = lib.mapAttrs (_: lib.mkDefault) (
                {
                  Type = "exec";
                  ExecStart = utils.escapeSystemdExecArgs [
                    (lib.getExe' cfg.package "xs")
                    "serve"
                    "./store"
                    "--expose"
                    "${host}:${toString cfg.port}"
                  ];
                  WorkingDirectory = "%S/xs";
                  StateDirectory = "xs";
                  Restart = "on-failure";
                  RestartSec = "5s";
                }
                // lib.optionalAttrs cfg.sandbox {
                  StateDirectoryMode = "0700";
                  UMask = "0077";
                  PrivateUsers = true;
                  PrivateDevices = true;
                  PrivateIPC = true;
                  PrivateTmp = "disconnected";
                  TemporaryFileSystem = "/:ro";
                  BindReadOnlyPaths = [ "/nix/store" ];
                  NoNewPrivileges = true;
                  CapabilityBoundingSet = "";
                  RestrictNamespaces = true;
                  RestrictSUIDSGID = true;
                  RestrictRealtime = true;
                  LockPersonality = true;
                  MemoryDenyWriteExecute = true;
                  SystemCallArchitectures = "native";
                  SystemCallFilter = [
                    "@system-service"
                    "~@privileged @resources @debug kill tkill tgkill rt_sigqueueinfo rt_tgsigqueueinfo pidfd_send_signal"
                  ];
                  SystemCallErrorNumber = "EPERM";
                  RestrictAddressFamilies = [
                    "AF_UNIX"
                    "AF_INET"
                    "AF_INET6"
                  ];
                }
              );
            };
          }
        else
          {
            users.users.${cfg.user}.packages = [ cfg.package ];
            launchd.daemons.xs = (import ../lib/darwin-service.nix { inherit config lib pkgs; }) {
              name = "xs";
              inherit (cfg) user;
              command = [
                (lib.getExe' cfg.package "xs")
                "serve"
                "./store"
                "--expose"
                "${host}:${toString cfg.port}"
              ];
              directory = "${config.users.users.${cfg.user}.home}/Library/Application Support/xs";
            };
          }
      )
    ]
  );
}
