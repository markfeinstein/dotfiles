{
  git,
  python3,
  writeShellApplication,
}:
writeShellApplication {
  name = "git-readonly";
  runtimeInputs = [
    git
    python3
  ];
  text = ''
    exec python3 ${../../bin/git-readonly.py} "$@"
  '';
}
