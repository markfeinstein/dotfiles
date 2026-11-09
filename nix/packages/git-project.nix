{
  coreutils,
  git,
  gnused,
  jq,
  openssh,
  worktrunk,
  writeShellApplication,
}:
writeShellApplication {
  name = "git-project";
  runtimeInputs = [coreutils git gnused jq openssh worktrunk];
  text = builtins.readFile ../../bin/git-project;
}
