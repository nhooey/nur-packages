# The `background-items-darwin-module` check in flake.nix:
# modules/background-items, evaluated with lib.evalModules against stubs of
# the nix-darwin options it reads and sets, rather than against nix-darwin
# itself, which would add an input (and lock nodes) for every consumer of
# this flake. The stubs copy what the module depends on: a launchd job's
# `command` becomes ProgramArguments `/bin/sh -c "/bin/wait4path /nix/store
# && exec <command>"`, its Label defaults to org.nixos.<name>, and
# environment.<files>."<Label>.plist".text is
# lib.generators.toPlist { escape = true; } of its serviceConfig.
# `alice` is a placeholder user.
{ pkgs, package }:
let
  inherit (pkgs) lib;
  inherit (lib) mkOption types;

  serviceConfig = types.submodule {
    freeformType = types.attrsOf types.anything;
    options = {
      Label = mkOption { type = types.str; };
      Program = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      ProgramArguments = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
      };
    };
  };
  job = types.submodule (
    { name, config, ... }:
    {
      options = {
        command = mkOption {
          type = types.str;
          default = "";
        };
        serviceConfig = mkOption {
          type = serviceConfig;
          default = { };
        };
      };
      config.serviceConfig = {
        Label = lib.mkDefault "org.nixos.${name}";
        ProgramArguments = lib.mkIf (config.command != "") [
          "/bin/sh"
          "-c"
          "/bin/wait4path /nix/store && exec ${config.command}"
        ];
      };
    }
  );
  textFile = types.submodule {
    options.text = mkOption {
      type = types.lines;
      default = "";
    };
  };
  jobsOption = mkOption {
    type = types.attrsOf job;
    default = { };
  };
  filesOption = mkOption {
    type = types.attrsOf textFile;
    default = { };
  };
  linesOption = mkOption {
    type = types.lines;
    default = "";
  };

  darwinStub =
    { config, ... }:
    let
      plists = lib.mapAttrs' (
        _: j:
        lib.nameValuePair "${j.serviceConfig.Label}.plist" {
          text = lib.generators.toPlist { escape = true; } j.serviceConfig;
        }
      );
    in
    {
      options = {
        assertions = mkOption {
          type = types.listOf types.attrs;
          default = [ ];
        };
        system.primaryUser = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        users.users = mkOption {
          type = types.attrsOf (
            types.submodule {
              options.home = mkOption {
                type = types.nullOr types.path;
                default = null;
              };
              # As in nix-darwin: no default, so reading it unset throws.
              options.uid = mkOption { type = types.int; };
            }
          );
          default = { };
        };
        launchd.daemons = jobsOption;
        launchd.agents = jobsOption;
        launchd.user.agents = jobsOption;
        environment.launchDaemons = filesOption;
        environment.launchAgents = filesOption;
        environment.userLaunchAgents = filesOption;
        environment.etc = mkOption {
          type = types.attrsOf (types.attrsOf types.anything);
          default = { };
        };
        environment.systemPackages = mkOption {
          type = types.listOf types.package;
          default = [ ];
        };
        system.activationScripts.extraActivation.text = linesOption;
        system.activationScripts.postActivation.text = linesOption;
      };
      config = {
        environment.launchDaemons = plists config.launchd.daemons;
        environment.launchAgents = plists config.launchd.agents;
        environment.userLaunchAgents = plists config.launchd.user.agents;
      };
    };

  # nix-darwin's jobs, as it defines them.
  nixDarwinJobs = {
    launchd.daemons.nix-daemon = {
      command = "/nix/store/nix/bin/nix-daemon";
      serviceConfig.KeepAlive = true;
    };
    launchd.daemons.nix-gc = {
      command = "/nix/store/nix/bin/nix-collect-garbage --delete-older-than 30d";
      serviceConfig.StartCalendarInterval = [ { Hour = 3; } ];
    };
    launchd.user.agents.demo-prune.serviceConfig.ProgramArguments = [
      "/bin/sh"
      "-c"
      "exec /nix/store/demo --prune"
    ];
  };

  # alice is declared, as in most nix-darwin configurations, but without a
  # uid, which nix-darwin only needs for its knownUsers.
  evalWith = evalWithUsers { alice.home = "/Users/alice"; };
  evalWithUsers =
    users: settings:
    (lib.evalModules {
      modules = [
        darwinStub
        nixDarwinJobs
        ../../modules/background-items
        {
          _module.args.pkgs = pkgs;
          system.primaryUser = "alice";
          users.users = users;
          services.background-items = {
            inherit package;
          }
          // settings;
        }
      ];
    }).config;

  failedAssertions = c: map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  toPlist = lib.generators.toPlist { escape = true; };

  disabled = evalWith { };
  off = evalWith {
    enable = false;
    items."com.example.x" = {
      domain = "gui";
      state = "absent";
    };
  };

  full = evalWith {
    enable = true;
    items = {
      "com.google.keystone.agent" = {
        domain = "gui";
        state = "absent";
        extraPaths = [ "~/Library/Application Support/Google/GoogleUpdater" ];
      };
      "com.google.keystone.daemon" = {
        domain = "system";
        state = "absent";
        extraPaths = [ "/Library/Google/GoogleSoftwareUpdate" ];
      };
      "com.example.helper" = {
        domain = "gui";
        state = "off";
      };
      "com.example.wanted" = {
        domain = "system";
        state = "on";
      };
    };
    openAtLogin = [ "/Applications/Rectangle.app" ];
    launcherNames = {
      "org.nixos.nix-gc" = "Nix GC";
      "org.nixos.demo-prune" = "Demo Prune";
    };
  };
  config = builtins.fromJSON (full.environment.etc."background-items/config.json".text);
  configWithUid = builtins.fromJSON (
    (evalWithUsers { alice.uid = 501; } { enable = true; })
    .environment.etc."background-items/config.json".text
  );
  itemOf = label: lib.findFirst (i: i.label == label) null config.items;

  onlyOnAndOff = evalWith {
    enable = true;
    items."com.example.helper" = {
      domain = "gui";
      state = "off";
    };
  };

  bad = evalWith {
    enable = true;
    items."com.example.x" = {
      domain = "gui";
      state = "absent";
      extraPaths = [
        "/"
        "/Library"
        "~/a/../b"
        "relative/path"
        "/Library/Foo*"
        "/Library/Google/GoogleSoftwareUpdate"
      ];
    };
    launcherNames = {
      "org.nixos.darwin-store" = "Nix Store Volume";
      "org.nixos.nix-gc" = "Nix/GC";
      "org.nixos.nix-daemon" = "Nix/GC";
    };
  };
  badMessages = failedAssertions bad;

  gcPlist = full.environment.launchDaemons."org.nixos.nix-gc.plist".text;
  prunePlist = full.environment.userLaunchAgents."org.nixos.demo-prune.plist".text;
  cleanup = full.launchd.daemons.background-items-cleanup;
  extra = full.system.activationScripts.extraActivation.text;
  post = full.system.activationScripts.postActivation.text;
  exe = builtins.unsafeDiscardStringContext (lib.getExe package);
in
# Off (the default), the module changes nothing.
assert disabled.environment.etc == { };
assert disabled.launchd.daemons ? background-items-cleanup == false;
assert off.system.activationScripts.postActivation.text == "";
assert failedAssertions full == [ ];

# The config file the scripts read.
assert config.user == "alice";
assert config.home == "/Users/alice";
# With no uid set, the scripts look it up with `id -u`.
assert config.uid == null;
assert configWithUid.uid == 501;
assert
  (itemOf "com.google.keystone.agent").plists == [
    "/Users/alice/Library/LaunchAgents/com.google.keystone.agent.plist"
    "/Library/LaunchAgents/com.google.keystone.agent.plist"
  ];
assert
  (itemOf "com.google.keystone.agent").extraPaths == [
    "/Users/alice/Library/Application Support/Google/GoogleUpdater"
  ];
assert
  (itemOf "com.google.keystone.daemon").plists == [
    "/Library/LaunchDaemons/com.google.keystone.daemon.plist"
  ];
assert (itemOf "com.example.wanted").state == "on";
assert config.openAtLogin == [ "/Applications/Rectangle.app" ];

# Activation: launchers before nix-darwin loads the plists, apply after.
assert lib.hasInfix "install-launchers --dir /usr/local/libexec/nix-launchd" extra;
assert lib.hasInfix "-- 'Demo Prune' 'Nix GC'" extra;
assert lib.hasInfix "${exe} --config " (builtins.unsafeDiscardStringContext post);
assert lib.hasSuffix " apply || echo \"background-items: apply failed\" >&2\n" post;

# The WatchPaths job re-runs the absent cleanup when those folders change.
assert
  cleanup.serviceConfig.WatchPaths == [
    "/Users/alice/Library/LaunchAgents"
    "/Library/LaunchAgents"
    "/Library/LaunchDaemons"
  ];
assert lib.hasSuffix " cleanup" cleanup.command;
assert onlyOnAndOff.launchd.daemons ? background-items-cleanup == false;

# Launchers: the listed jobs run through them, with their own arguments after.
assert
  gcPlist == toPlist {
    Label = "org.nixos.nix-gc";
    ProgramArguments = [
      "/usr/local/libexec/nix-launchd/Nix GC"
      "/bin/sh"
      "-c"
      "/bin/wait4path /nix/store && exec /nix/store/nix/bin/nix-collect-garbage --delete-older-than 30d"
    ];
    StartCalendarInterval = [ { Hour = 3; } ];
  };
assert
  prunePlist == toPlist {
    Label = "org.nixos.demo-prune";
    ProgramArguments = [
      "/usr/local/libexec/nix-launchd/Demo Prune"
      "/bin/sh"
      "-c"
      "exec /nix/store/demo --prune"
    ];
  };
# A job that is not listed keeps its plist.
assert
  full.environment.launchDaemons."org.nixos.nix-daemon.plist".text
  == disabled.environment.launchDaemons."org.nixos.nix-daemon.plist".text;

# Unsafe extra paths, darwin-store, invalid and duplicate names are refused;
# the one safe extra path is not.
assert builtins.length (builtins.filter (lib.hasInfix "extraPaths") badMessages) == 5;
assert !(builtins.any (lib.hasInfix "GoogleSoftwareUpdate") badMessages);
assert builtins.any (lib.hasInfix "org.nixos.darwin-store is written by the Nix installer")
  badMessages;
assert builtins.any (lib.hasInfix "\"Nix/GC\" is not a valid file name") badMessages;
assert builtins.any (lib.hasInfix "two jobs have the same name") badMessages;
pkgs.writeText "background-items-darwin-module" (
  builtins.toJSON {
    inherit gcPlist prunePlist;
    watch = cleanup.serviceConfig.WatchPaths;
  }
)
