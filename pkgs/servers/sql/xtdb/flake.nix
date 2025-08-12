{
  description = "XTDB - the temporal database";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gradle2nix = {
      url = "github:nhooey/gradle2nix/v2_bugfix-remove-param-console-plain";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , flake-parts
    , devshell
    , gradle2nix
    , ...
    }@inputs:

    inputs.flake-parts.lib.mkFlake { inherit inputs; } rec {

      systems = inputs.flake-utils.lib.defaultSystems;

      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
        inputs.devshell.flakeModule
      ];

      perSystem =
        { pkgs
        , system
        , config
        , ...
        }:
        let
          gradlePhaseFlags = {
            build = [ "docker:standalone:shadowJar" ];
          };
        in
        {
          _module.args.pkgs = import self.inputs.nixpkgs {
            inherit system;
          };

          packages = {
            default =
              let
                pkgs = nixpkgs.legacyPackages.${system};
                buildGradlePackage = self.inputs.gradle2nix.builders.${system}.buildGradlePackage;
              in
              pkgs.callPackage ./default.nix {
                inherit pkgs buildGradlePackage;
              };
          };

          devshells =
            let
              debugMode = builtins.pathExists ./flake.debug;
              wrapCommand = cmd: if debugMode then "sh -x -c '${cmd}'" else cmd;
            in
            {
              default = {
                motd =
                  "{202}🔨 Welcome to devshell{reset}"
                  + (if !debugMode then "" else "\n{34}🐞 Debug Mode is enabled{reset}\n") +
                  "$(type -p menu &>/dev/null && menu)";

                packages = [
                  pkgs.jdk21
                  pkgs.gradle
                ];

                env = [
                  {
                    name = "PATH";
                    prefix = "../../../../bin";
                  }
                ];

                commands =
                  let
                    gradle2nixUrl = "github:nhooey/gradle2nix/v2_bugfix-remove-param-console-plain";
                    xtdbGit = rec {
                      url = "git@github.com:xtdb/xtdb.git";
                      dir = "xtdb";
                      version = "2.0.0";
                      tag = "v${xtdbGit.version}";
                    };
                  in
                  [
                    {
                      name = "build";
                      category = "flake";
                      help = "Build the Nix flake";
                      command = wrapCommand ''
                        nix build
                      '' + (if debugMode then " --print-build-logs --show-trace" else "");
                    }
                    {
                      name = "clone";
                      category = "flake";
                      help = "Clone the XTDB repository.";
                      command = wrapCommand ''
                        git-clone-idempotent.sh '${xtdbGit.url}' '${xtdbGit.dir}' '${xtdbGit.tag}'
                      '';
                    }
                    {
                      name = "flake-lock";
                      category = "flake";
                      help = "Lock the versions of Nix flakes in: `flake.lock`";
                      command = wrapCommand ''
                        nix flake lock --recreate-lock-file
                      '';
                    }
                    {
                      name = "gradle-lock";
                      category = "gradle";
                      help = "Lock the versions of gradle dependencies in: `gradle.lock`";
                      command =
                        let
                          gradleTasksAll = builtins.concatLists (builtins.attrValues gradlePhaseFlags);
                          cmdLineOptionsTask = builtins.concatStringsSep " " (map (task: "--task \"${task}\"") gradleTasksAll);
                        in
                        wrapCommand ''
                          pushd '${xtdbGit.dir}'
                          nix run ${gradle2nixUrl}#gradle2nix -- \
                        '' + (if debugMode then ''
                          --dump-events \
                          --log debug \
                        '' else "") + ''
                          ${cmdLineOptionsTask}
                          popd
                          cp '${xtdbGit.dir}/gradle.lock "$PRJ_ROOT/"
                        '';
                    }
                    {
                      name = "gradle-show-tasks";
                      category = "gradle";
                      help = "Show all of the gradle tasks";
                      command = wrapCommand ''
                        ./gradlew tasks --all
                      '';
                    }
                    {
                      name = "gradle-show-task-tree";
                      category = "gradle";
                      help = "Show the gradle task tree";
                      command = wrapCommand ''
                        ./gradlew taskTree --all
                      '';
                    }
                  ];
              };
            };
        };
    };
}

