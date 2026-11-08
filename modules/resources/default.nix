{
  config,
  lib,
  pkgs,
  options,
  ...
}:
let
  cfg = config.services.codex-executor;
  isDarwin = options ? launchd;
  launcher = pkgs.writeShellScript "codex-executor" ''
    exec ${pkgs.systemd}/bin/systemd-run --user --scope --quiet --collect \
      --slice=app-codexjobs.slice --property=OOMPolicy=stop \
      --property=TimeoutStopSec=10s -- \
      ${lib.getExe cfg.package} exec-server --listen stdio
  '';
  environments = pkgs.writeText "codex-environments.toml" ''
    # Managed by agents.nix services.codex-executor.
    default = "executor"
    include_local = true

    [[environments]]
    id = "executor"
    program = "${launcher}"
  '';
in
{
  options.services.codex-executor = {
    enable = lib.mkEnableOption "systemd containment for Codex's stdio executors";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.codex;
      description = "Codex package shared with its app servers.";
    };
  };
  config = lib.mkIf (cfg.enable && !isDarwin) {
    environment.etc."codex/environments.toml".source = environments;
    systemd.user.slices.app-codexjobs = {
      description = "Aggregate budget for Codex executors and tool processes";
      sliceConfig = {
        MemoryMax = lib.mkDefault "95%";
        TasksMax = lib.mkDefault 4096;
      };
    };
  };
}
