{config, ...}: let
  goPath = "${config.home.homeDirectory}/go";
in {
  programs.go = {
    enable = true;
    env.GOPATH = goPath;
  };

  home.sessionPath = [
    "${goPath}/bin"
  ];
}
