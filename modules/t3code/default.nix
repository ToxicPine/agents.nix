{ llm-agents, nixpkgs }:
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
  cfg = config.services.t3code;
in
{
  imports = [ ../resources ];
  options.services.t3code = {
    enable = lib.mkEnableOption "a supervised headless T3 Code server";

    user = lib.mkOption {
      type = lib.types.str;
      description = "Existing normal user account that runs T3 Code.";
      example = "alice";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = import ./package.nix {
        upstream = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code.unwrapped;
      };
      defaultText = lib.literalExpression "agents.nix's pinned T3 Code CLI with host-managed resource policy";
      description = ''
        T3 Code package providing the t3 executable. The default package uses
        agents from the inherited PATH instead of bundling provider CLIs, and
        leaves systemd resource policy alone unless explicitly configured through
        T3CODE_AGENT_SLICE_* environment variables. See modules/t3code/README.md.
      '';
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
      type = if pkgs.stdenv.hostPlatform.isDarwin then lib.types.enum [ false ] else lib.types.bool;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin then
          throw "Set services.t3code.openFirewall = false explicitly on macOS."
        else
          true;
      defaultText = lib.literalExpression "true on Linux; explicit false on macOS";
      description = "Allow the configured TCP port on all interfaces. For interface-specific access, configure networking.firewall.interfaces directly.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !pkgs.stdenv.hostPlatform.isDarwin || !cfg.openFirewall;
            message = "services.t3code.openFirewall is only supported on Linux; configure the macOS firewall separately.";
          }
          {
            assertion =
              cfg.user != ""
              && (
                if pkgs.stdenv.hostPlatform.isDarwin then
                  config.users.users.${cfg.user}.home != null
                else
                  config.users.users.${cfg.user}.isNormalUser
              );
            message = "services.t3code.user must name an existing normal user account.";
          }
        ];

      }
      (
        if !isDarwin then
          {
            services.codex-executor = {
              enable = lib.mkDefault true;
              package = lib.mkDefault nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.codex;
            };
            users.users.${cfg.user} = {
              linger = lib.mkDefault true;
              packages = [
                cfg.package
                config.services.codex-executor.package
              ];
            };
            networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

            # T3 places provider app servers below this slice. Tool executors
            # live alongside it in app-codexjobs.slice.
            systemd.user.slices.app-t3code.sliceConfig = {
              CPUWeight = lib.mkDefault 1000;
              IOWeight = lib.mkDefault 1000;
            };

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
                CPUWeight = lib.mkDefault 1000;
                IOWeight = lib.mkDefault 1000;
              };
            };
          }
        else
          {
            users.users.${cfg.user}.packages = [ cfg.package ];
            launchd.daemons.t3code = (import ../lib/darwin-service.nix { inherit config lib pkgs; }) {
              name = "t3code";
              inherit (cfg) user;
              command = [
                (lib.getExe cfg.package)
                "serve"
                "--host"
                cfg.host
                "--port"
                (toString cfg.port)
              ];
            };
          }
      )
    ]
  );
}
