{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.skills;
  relative = lib.types.strMatching "[^/].*";
  safePath =
    path:
    lib.all (
      part:
      !(builtins.elem part [
        ""
        "."
        ".."
      ])
    ) (lib.splitString "/" path);
  roots = [
    "."
    "skills"
    "skills/.curated"
    "skills/.experimental"
    "skills/.system"
  ]
  ++ map (agent: ".${agent}/skills") (
    lib.splitString " " "agents claude cline codebuddy codex commandcode continue factory github goose grok iflow junie kilo kilocode kimchi kiro minimax mux neovate opencode openhands pi qoder roo trae windsurf zcode zencoder"
  )
  ++ [ ".posit/assistant/skills" ];
  defaults = inherited: {
    targets = lib.mkOption {
      type = lib.types.listOf relative;
      default = inherited.targets;
      description = "Home-relative directories in which the module manages individual skill links. Unrelated skills are preserved.";
    };
    discovery = lib.mkOption {
      default = { };
      type = lib.types.submodule {
        options = {
          paths = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf relative);
            default = inherited.discovery.paths;
            description = "Source-relative roots; null searches recognised skill locations.";
          };
          maxDepth = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = inherited.discovery.maxDepth;
            description = "Maximum recursion depth below each discovery root.";
          };
        };
      };
    };
  };
  discover =
    entry:
    let
      source = toString entry.source;
      walk =
        path: depth:
        let
          contents = builtins.readDir path;
        in
        if contents."SKILL.md" or null == "regular" then
          [
            {
              name = builtins.unsafeDiscardStringContext (builtins.baseNameOf path);
              path = builtins.path { inherit path; };
            }
          ]
        else
          lib.concatMap (name: walk (path + "/${name}") (depth - 1)) (
            lib.filter (
              name:
              depth > 0
              && contents.${name} == "directory"
              && !(builtins.elem name [
                ".git"
                "node_modules"
                "dist"
                "build"
                "__pycache__"
              ])
            ) (builtins.attrNames contents)
          );
      paths = if entry.discovery.paths == null then roots else entry.discovery.paths;
    in
    lib.unique (
      lib.concatMap (
        root:
        let
          path = if root == "." then source else source + "/${root}";
        in
        if root != "." && !safePath root then
          throw "Invalid skill discovery path: ${root}"
        else if builtins.pathExists path then
          walk path entry.discovery.maxDepth
        else if entry.discovery.paths == null then
          [ ]
        else
          throw "Missing skill discovery path: ${root}"
      ) paths
    );
  matches =
    pattern: name:
    builtins.match (lib.replaceStrings [ "\\*" "\\?" ] [ ".*" "." ] (lib.escapeRegex pattern)) name
    != null;
  entries = settings: builtins.attrValues (lib.filterAttrs (_: entry: entry.enable) settings.skills);
  targets = settings: lib.unique (lib.concatMap (entry: entry.targets) (entries settings));
  selections =
    settings:
    lib.concatMap (
      entry:
      let
        found = discover entry;
        selected = lib.filter (
          skill:
          lib.any (pattern: matches pattern skill.name) entry.select
          && !lib.any (pattern: matches pattern skill.name) entry.exclude
        ) found;
      in
      assert lib.assertMsg (lib.all (
        pattern: lib.any (skill: matches pattern skill.name) found
      ) entry.select) "A programs.skills selector matched no skill directories.";
      lib.concatMap (
        target:
        assert lib.assertMsg (safePath target) "Invalid programs.skills target: ${target}";
        map (skill: {
          name = "${target}/${skill.name}";
          path = skill.path;
        }) selected
      ) entry.targets
    ) (entries settings);
in
{
  options.programs.skills = {
    defaults = lib.mkOption {
      default = { };
      type = lib.types.submodule {
        options = defaults {
          targets = [ ".agents/skills" ];
          discovery = {
            paths = null;
            maxDepth = 5;
          };
        };
      };
    };
    users = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }: {
            options = {
              defaults = lib.mkOption {
                default = { };
                type = lib.types.submodule { options = defaults cfg.defaults; };
              };
              skills = lib.mkOption {
                default = { };
                type = lib.types.attrsOf (
                  lib.types.coercedTo lib.types.path (source: { inherit source; }) (
                    lib.types.submodule (
                      { name, ... }: {
                        options = defaults config.defaults // {
                          enable = lib.mkOption {
                            type = lib.types.bool;
                            default = true;
                          };
                          source = lib.mkOption { type = lib.types.path; };
                          select = lib.mkOption {
                            type = lib.types.listOf lib.types.str;
                            default = [ name ];
                            description = "Skill directory names or globs using * and ?.";
                          };
                          exclude = lib.mkOption {
                            type = lib.types.listOf lib.types.str;
                            default = [ ];
                          };
                        };
                      }
                    )
                  )
                );
              };
              package = lib.mkOption {
                type = lib.types.package;
                readOnly = true;
                default =
                  let
                    links = lib.unique (selections config);
                    names = map (link: link.name) links;
                    destinations = targets config;
                  in
                  assert lib.assertMsg (
                    lib.length names == lib.length (lib.unique names)
                  ) "Conflicting skill directories for user ${name}.";
                  assert lib.assertMsg (lib.all (
                    a: lib.all (b: a == b || !lib.hasPrefix "${a}/" b) destinations
                  ) destinations) "Overlapping skill targets for user ${name}.";
                  pkgs.linkFarm "${name}-skills" (
                    links
                    ++ map (target: {
                      name = target;
                      path = pkgs.emptyDirectory;
                    }) (lib.filter (target: !lib.any (link: lib.hasPrefix "${target}/" link.name) links) destinations)
                  );
                description = "Store tree containing this user's skill directories.";
              };
            };
          }
        )
      );
    };
  };
  config = {
    assertions = lib.mapAttrsToList (name: settings: {
      assertion = config.users.users.${name}.isNormalUser or false;
      message = "programs.skills.users.${name} must name an existing normal user.";
    }) cfg.users;
    system.activationScripts.agent-skills = {
      deps = [ "users" ];
      text = lib.optionalString (cfg.users != { }) ''
        agent_skills_status=0
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: settings:
            let
              user = config.users.users.${name};
              links = lib.unique (selections settings);
              script = ''
                ${lib.concatMapStringsSep "\n" (link: ''
                  target=${lib.escapeShellArg "${user.home}/${link.name}"}
                  if [ -e "$target" ] || [ -L "$target" ]; then
                    if [ -L "$target" ]; then
                      previous=$(${pkgs.coreutils}/bin/readlink -- "$target")
                      case "$previous" in
                        ${lib.escapeShellArg builtins.storeDir}/*${lib.escapeShellArg "-${name}-skills/${link.name}"}) ;;
                        *) printf 'Refusing to replace unmanaged skill: %s\n' "$target" >&2; exit 1 ;;
                      esac
                    else
                      printf 'Refusing to replace unmanaged skill: %s\n' "$target" >&2
                      exit 1
                    fi
                  fi
                '') links}
                ${lib.concatMapStringsSep "\n" (link: ''
                  ${pkgs.coreutils}/bin/mkdir -p -- ${lib.escapeShellArg "${user.home}/${builtins.dirOf link.name}"}
                  ${pkgs.coreutils}/bin/ln -sfnT -- ${lib.escapeShellArg "${settings.package}/${link.name}"} ${lib.escapeShellArg "${user.home}/${link.name}"}
                '') links}
              '';
            in
            lib.optionalString (targets settings != [ ]) ''
              ${pkgs.util-linux}/bin/runuser -u ${lib.escapeShellArg user.name} -- ${pkgs.runtimeShell} -euc ${lib.escapeShellArg script} || agent_skills_status=1
            ''
          ) cfg.users
        )}
        test "$agent_skills_status" -eq 0
      '';
    };
  };
}
