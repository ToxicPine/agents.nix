{ options, ... }:
let
  settings = {
    substituters = [ "https://cache.numtide.com" ];
    trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
in
{
  config =
    if options ? launchd && options ? determinateNix then
      {
        determinateNix.customSettings = {
          extra-substituters = settings.substituters;
          extra-trusted-public-keys = settings.trusted-public-keys;
        };
      }
    else
      {
        nix.settings = settings;
      };
}
