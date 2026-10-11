{ llm-agents }:
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.services.cli-proxy-api;
  format = pkgs.formats.yaml { };
  stateDir = "/var/lib/cli-proxy-api";
  configPath = "${stateDir}/config.yaml";
  secretsReplacement = utils.genJqSecretsReplacement {
    loadCredential = true;
  } cfg.settings configPath;
in
{
  options.services.cli-proxy-api = {
    enable = lib.mkEnableOption "CLIProxyAPI";

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
      description = "Environment file as defined in {manpage}`systemd.exec(5)`.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for {option}`services.cli-proxy-api.settings.server.port`.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "cli-proxy-api";
      description = "User account under which CLIProxyAPI runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "cli-proxy-api";
      description = "Group under which CLIProxyAPI runs.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users = lib.mkIf (cfg.user == "cli-proxy-api") {
      cli-proxy-api = {
        isSystemUser = true;
        group = cfg.group;
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
        UMask = "0077";
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.settings.server.port ];
    };
  };
}
