{
  config,
  lib,
  pkgs,
}:
{
  name,
  user,
  command,
  directory ? null,
  prepare ? "",
}:
let
  userHome = config.users.users.${user}.home;
  workDir = if directory == null then userHome else directory;
in
{
  environment = {
    HOME = userHome;
    PATH = "/etc/profiles/per-user/${user}/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  };
  script = ''
    set -eu
    umask 077
    ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg workDir}
    ${lib.optionalString (
      directory != null
    ) "${pkgs.coreutils}/bin/chmod 700 ${lib.escapeShellArg workDir}"}
    cd ${lib.escapeShellArg workDir}
    ${prepare}
    exec ${lib.escapeShellArgs command}
  '';
  serviceConfig = {
    UserName = user;
    RunAtLoad = true;
    KeepAlive.SuccessfulExit = false;
    ThrottleInterval = 5;
    StandardOutPath = "/var/log/${name}.log";
    StandardErrorPath = "/var/log/${name}.log";
    Umask = 63;
  };
}
