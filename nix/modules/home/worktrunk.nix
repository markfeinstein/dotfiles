{
  lib,
  pkgs,
  ...
}: let
  worktrunk = pkgs.worktrunk;
  wt = lib.getExe' worktrunk "wt";

  nushellIntegration =
    pkgs.runCommand "worktrunk.nu" {
      nativeBuildInputs = [worktrunk];
    } ''
      wt config shell init nu > "$out"
    '';

  nushellAutoload =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "Library/Application Support/nushell/vendor/autoload/wt.nu"
    else ".local/share/nushell/vendor/autoload/wt.nu";
in {
  home.packages = [worktrunk];

  xdg.configFile."worktrunk/config.toml".text = ''
    worktree-path = "{{ repo_path }}/../{{ branch | sanitize }}"
    skip-shell-integration-prompt = true
  '';

  # Worktrunk needs a shell wrapper to change the parent shell's
  # directory. The installer would otherwise modify HM-owned files.
  programs.zsh.initContent = lib.mkAfter ''
    eval "$(${wt} config shell init zsh)"
  '';

  home.file."${nushellAutoload}".source = nushellIntegration;
}
