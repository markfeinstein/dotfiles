{config, ...}: {
  programs.git = {
    enable = true;

    ignores = [
      ".plans/**"
    ];

    settings = {
      init.defaultBranch = "main";

      user = {
        name = config.profile.user.fullName;
        email = config.profile.user.email;
      };
    };
  };
}
