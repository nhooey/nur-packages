# The `jellyfin-apply-settings` command (see jellyfin-apply-settings.py)
# that services.jellyfin-settings runs on Home Manager activation.
{
  lib,
  writers,
}:
(writers.writePython3Bin "jellyfin-apply-settings" {
  # Long lines are URLs and option names; breaking them reads worse.
  flakeIgnore = [ "E501" ];
} (builtins.readFile ./jellyfin-apply-settings.py)).overrideAttrs
  (old: {
    meta = (old.meta or { }) // {
      description = "Apply declared Jellyfin settings through its REST API";
      license = lib.licenses.mit;
      mainProgram = "jellyfin-apply-settings";
    };
  })
