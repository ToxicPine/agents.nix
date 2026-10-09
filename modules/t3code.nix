{ llm-agents }:
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.services.t3code;
in
{
  options.services.t3code = {
    enable = lib.mkEnableOption "a systemd-supervised headless T3 Code server";

    user = lib.mkOption {
      type = lib.types.str;
      description = "Existing normal user account that runs T3 Code.";
      example = "alice";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
      defaultText = lib.literalExpression "agents.nix's pinned llm-agents T3 Code package";
      description = "T3 Code package providing the t3 executable.";
    };

    host = lib.mkOption {
      type = lib.types.strMatching "[^[:space:]/]+";
      default = "127.0.0.1";
      example = "0.0.0.0";
      description = ''
        Bind address passed directly to --host. Loopback restricts access to this
        machine; 0.0.0.0 binds all IPv4 interfaces, including LAN and Tailscale;
        :: binds IPv6 and may also accept IPv4 depending on the system. A LAN or
        Tailscale IP binds that address only. A hostname, including MagicDNS,
        resolves at runtime and must resolve to an address on this machine.
        Hostnames do not enable Tailscale Serve or change authentication.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
      description = "HTTP and WebSocket port passed to --port.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow the configured TCP port on all interfaces. For interface-specific access, configure networking.firewall.interfaces directly.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != "" && config.users.users.${cfg.user}.isNormalUser;
        message = "services.t3code.user must name an existing normal user account.";
      }
    ];

    users.users.${cfg.user}.linger = lib.mkDefault true;
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.user.services.t3code = {
      description = lib.mkDefault "T3 Code headless server";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = cfg.user;
      enableDefaultPath = lib.mkDefault false;

      serviceConfig = {
        Type = lib.mkDefault "exec";
        WorkingDirectory = lib.mkDefault "%h";
        ExecStart = lib.mkDefault (
          utils.escapeSystemdExecArgs [
            (lib.getExe cfg.package)
            "serve"
            "--host"
            cfg.host
            "--port"
            cfg.port
          ]
        );
        Restart = lib.mkDefault "on-failure";
        RestartSec = lib.mkDefault "5s";
      };
    };
  };
}
