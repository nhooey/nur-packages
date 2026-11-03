# Home Manager module: services.jellyfin-settings. Declares Jellyfin's
# encoding settings, per-user settings and libraries, and applies them
# through Jellyfin's REST API on activation, only when they've changed since
# the last successful run. Listed keys are set; nothing else is touched, and
# no library or path is removed. The API key is read through SecretSpec
# from a 1Password item named by ID. Exported by the flake as
# `homeModules.jellyfin-settings`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.jellyfin-settings;
  inherit (lib) mkEnableOption mkOption types;
  package = pkgs.callPackage ./package.nix { };

  settingsFile = (pkgs.formats.json { }).generate "jellyfin-settings.json" {
    inherit (cfg)
      url
      encoding
      users
      libraries
      ;
  };
  stamp = "${config.xdg.stateHome}/jellyfin-settings/applied.sha256";
in
{
  options.services.jellyfin-settings = {
    enable = mkEnableOption "applying declared Jellyfin settings through its REST API";

    url = mkOption {
      type = types.str;
      default = "http://localhost:8096";
      description = "Jellyfin's base URL.";
    };

    encoding = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      example = {
        HardwareAccelerationType = "videotoolbox";
        H264Crf = 20;
      };
      description = "Keys of Jellyfin's encoding configuration (`/System/Configuration/encoding`) to set.";
    };

    users = mkOption {
      type = types.attrsOf (types.attrsOf types.anything);
      default = { };
      example = {
        alice = {
          SubtitleLanguagePreference = "eng";
          SubtitleMode = "Always";
        };
      };
      description = "Per Jellyfin user name, keys of that user's configuration to set.";
    };

    libraries = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            type = mkOption {
              type = types.enum [
                "movies"
                "tvshows"
                "music"
                "musicvideos"
                "homevideos"
                "boxsets"
                "books"
                "mixed"
              ];
              description = "Jellyfin's collection type for the library.";
            };
            paths = mkOption {
              type = types.listOf types.str;
              description = "The library's folders; `~/` is the user's home.";
            };
          };
        }
      );
      default = { };
      description = "Libraries by name. Missing ones are added and scanned; none is removed.";
    };

    apiKey = {
      provider = mkOption {
        type = types.str;
        default = "onepassword-uncached";
        description = ''
          The SecretSpec provider alias to read the key through, such as a
          user-global alias in ~/.config/secretspec/config.toml. Best
          uncached, since the key is an administrator's.
        '';
      };
      item = mkOption {
        type = types.str;
        description = "ID of the 1Password item holding the Jellyfin API key.";
      };
      field = mkOption {
        type = types.str;
        default = "credential";
        description = "Label of the item's field holding the key.";
      };
      title = mkOption {
        type = types.str;
        default = "";
        description = "The item's title, for the SecretSpec manifest's description.";
      };
    };

    secretspec = mkOption {
      type = types.str;
      default = "${config.home.profileDirectory}/bin/secretspec";
      defaultText = lib.literalExpression ''"''${config.home.profileDirectory}/bin/secretspec"'';
      description = ''
        The secretspec to run. The one on the user's PATH by default, since a
        keychain cache entry trusts only the build that wrote it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

    xdg.configFile."jellyfin-settings/settings.json".source = settingsFile;

    xdg.configFile."secretspec/jellyfin.toml".text = ''
      [project]
      name = "jellyfin"
      revision = "1.0"

      [profiles.default]
      JELLYFIN_API_KEY = { description = "Jellyfin API key${
        lib.optionalString (cfg.apiKey.title != "") " (1Password: ${cfg.apiKey.title})"
      }", required = true, providers = ["${cfg.apiKey.provider}"], ref = { item = "${cfg.apiKey.item}", field = "${cfg.apiKey.field}" } }
    '';

    home.activation.jellyfinSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe package} ${settingsFile} \
        --if-changed ${lib.escapeShellArg stamp} \
        --secretspec ${lib.escapeShellArg cfg.secretspec} \
        --manifest ${lib.escapeShellArg "${config.xdg.configHome}/secretspec/jellyfin.toml"}
    '';
  };
}
