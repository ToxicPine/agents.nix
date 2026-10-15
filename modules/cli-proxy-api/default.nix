{ llm-agents }:
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
  cfg = config.services.cli-proxy-api;
  format = pkgs.formats.yaml { };
  stateDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.users.users.${cfg.user}.home}/Library/Application Support/cli-proxy-api"
    else
      "/var/lib/cli-proxy-api";
  configPath = "${stateDir}/config.yaml";
  secretUtils =
    if isDarwin then
      import "${pkgs.path}/nixos/lib/utils.nix" {
        inherit config lib pkgs;
      }
    else
      utils;
  secretsReplacement = secretUtils.genJqSecretsReplacement {
    loadCredential = !pkgs.stdenv.hostPlatform.isDarwin;
  } cfg.settings configPath;
in
{
  options.services.cli-proxy-api = {
    enable = lib.mkEnableOption "CLIProxyAPI";

    sandbox = lib.mkOption {
      type = if pkgs.stdenv.hostPlatform.isDarwin then lib.types.enum [ false ] else lib.types.bool;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin then
          throw "Set services.cli-proxy-api.sandbox = false explicitly on macOS."
        else
          true;
      defaultText = lib.literalExpression "true on Linux; explicit false on macOS";
      description = "Apply systemd sandboxing restrictions to CLIProxyAPI.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.cli-proxy-api;
      defaultText = lib.literalExpression "agents.nix's pinned llm-agents CLIProxyAPI package";
      description = "CLIProxyAPI package to run.";
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = format.type;
        options = {
          server.port = lib.mkOption {
            type = lib.types.port;
            default = 8317;
            description = "Port on which CLIProxyAPI listens.";
          };
          oauth.auth-dir = lib.mkOption {
            type = lib.types.str;
            default = stateDir;
            description = "Directory where OAuth tokens are stored.";
          };
        };
      };
      default = { };
      example = lib.literalExpression ''
        {
          server = {
            host = "127.0.0.1";
            port = 8317;
          };
          access.api-keys = [ { _secret = "/run/secrets/cli-proxy-api-api-key"; } ];
          management.secret-key._secret = "/run/secrets/cli-proxy-api-management-key";
        }
      '';
      description = ''
        Configuration for CLIProxyAPI. See the
        [example configuration](https://github.com/router-for-me/CLIProxyAPI/blob/main/config.example.yaml)
        for available options. Secret values can be loaded from files using
        `._secret = "/path/to/secret";`.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/cli-proxy-api.env";
      description = "Environment file as defined in {manpage}`systemd.exec(5)` on Linux, or sourced as shell code on macOS.";
    };

    openFirewall = lib.mkOption {
      type = if pkgs.stdenv.hostPlatform.isDarwin then lib.types.enum [ false ] else lib.types.bool;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin then
          throw "Set services.cli-proxy-api.openFirewall = false explicitly on macOS."
        else
          false;
      defaultText = lib.literalExpression "false on Linux; explicit false on macOS";
      description = "Whether to open the firewall for {option}`services.cli-proxy-api.settings.server.port`.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin then
          (if config.system.primaryUser == null then "cli-proxy-api" else config.system.primaryUser)
        else
          "cli-proxy-api";
      description = "User account under which CLIProxyAPI runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = if pkgs.stdenv.hostPlatform.isDarwin then "staff" else "cli-proxy-api";
      description = "Group under which CLIProxyAPI runs.";
    };
  };

  config = lib.mkIf cfg.enable (
    if isDarwin then
      {
        assertions = [
          {
            assertion = (config.users.users.${cfg.user}.home or null) != null;
            message = "services.cli-proxy-api.user must name an existing user with a configured home.";
          }
          {
            assertion = !cfg.sandbox && !cfg.openFirewall;
            message = "services.cli-proxy-api.sandbox and openFirewall must be false on macOS.";
          }
        ];
        users.users.${cfg.user}.packages = [ cfg.package ];
        launchd.daemons.cli-proxy-api = lib.recursiveUpdate (
          (import ../lib/darwin-service.nix { inherit config lib pkgs; })
            {
              name = "cli-proxy-api";
              inherit (cfg) user;
              directory = stateDir;
              command = [
                (lib.getExe cfg.package)
                "-config"
                configPath
              ];
              prepare =
                lib.optionalString (cfg.environmentFile != null) ''
                  set -a
                  . ${lib.escapeShellArg cfg.environmentFile}
                  set +a
                ''
                + secretsReplacement.script;
            }
        ) { serviceConfig.GroupName = cfg.group; };
      }
    else
      {
        users.users = lib.mkIf (cfg.user == "cli-proxy-api") {
          cli-proxy-api = {
            isSystemUser = true;
            inherit (cfg) group;
            home = stateDir;
            description = "CLIProxyAPI service user";
          };
        };

        users.groups = lib.mkIf (cfg.group == "cli-proxy-api") {
          cli-proxy-api = { };
        };

        systemd.services.cli-proxy-api = {
          description = "Proxy that provides OpenAI/Gemini/Claude/Codex/Grok compatible API interfaces";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          preStart = secretsReplacement.script;

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            StateDirectory = "cli-proxy-api";
            StateDirectoryMode = "0700";
            WorkingDirectory = stateDir;
            ExecStart = utils.escapeSystemdExecArgs [
              (lib.getExe cfg.package)
              "-config"
              configPath
            ];
            Restart = "on-failure";
            RestartSec = 5;
            LoadCredential = secretsReplacement.credentials;
            EnvironmentFile = lib.mkIf (cfg.environmentFile != null) [ cfg.environmentFile ];

            UMask = "0077";
          }
          // lib.optionalAttrs cfg.sandbox {
            CapabilityBoundingSet = "";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            PrivateUsers = true;
            ProtectHostname = true;
            ProtectClock = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
            RestrictNamespaces = true;
            RestrictSUIDSGID = true;
            RestrictRealtime = true;
            RemoveIPC = true;
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
              "~@resources"
            ];
          };
        };

        networking.firewall = lib.mkIf cfg.openFirewall {
          allowedTCPPorts = [ cfg.settings.server.port ];
        };
      }
  );
}
