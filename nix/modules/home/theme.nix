{
  config,
  lib,
  ...
}: let
  theme = import ../../lib/theme.nix;
in {
  options.dotfiles.theme.darkVariant = lib.mkOption {
    type = lib.types.enum [
      "rose-pine"
      "rose-pine-moon"
    ];
    default = "rose-pine";
    description = "Preferred Rosé Pine variant for dark appearance";
  };

  config = {
    assertions = [
      {
        assertion = (theme.variant config.dotfiles.theme.darkVariant).appearance == "dark";
        message = "dotfiles.theme.darkVariant must select a dark theme";
      }
    ];

    home.sessionVariables.DOTFILES_ROSE_PINE_DARK_VARIANT =
      config.dotfiles.theme.darkVariant;
  };
}
