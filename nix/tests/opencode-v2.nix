{
  personal,
  work,
  lib,
  pkgs,
}:
let
  configText = home: name: home.config.xdg.configFile."opencode/${name}".text;
  personalServerText = configText personal "opencode.json";
  workServerText = configText work "opencode.json";
  personalCliText = configText personal "cli.json";
  workCliText = configText work "cli.json";
  personalServer = builtins.fromJSON personalServerText;
  workServer = builtins.fromJSON workServerText;
  cli = builtins.fromJSON personalCliText;
  asksFor =
    resource:
    lib.any (rule: rule.effect == "ask" && rule.resource == resource) personalServer.permissions;
  personalServerFile = pkgs.writeText "opencode-personal.json" personalServerText;
  workServerFile = pkgs.writeText "opencode-work.json" workServerText;
  cliFile = pkgs.writeText "opencode-cli.json" personalCliText;
in
assert personalServer."$schema" == "https://opencode.ai/config.json";
assert personalServer.model == "openai/gpt-6.1-terra";
assert personalServer.default_agent == "plan";
assert personalServer.update == "disable";
assert personalServer.agents.build.model == "openai/gpt-6.1-terra#xhigh";
assert personalServer.agents.title.model == "openai/gpt-6-luna#low";
assert personalServer.compaction.keep.tokens == 24000;
assert personalServer.compaction.buffer == "20%";
assert personalServer.experimental.background_compaction;
assert personalServer.worktree.directory == "..";
assert personalServer.experimental.todo;
assert (
  if pkgs.stdenv.hostPlatform.isDarwin then
    personalServer.mcp.servers.solidcraft.command == [
      "/Applications/SolidCraft.app/Contents/MacOS/solidcraft-cli"
      "mcp"
    ]
  else
    personalServer.mcp.servers == { }
);
assert workServer.mcp.servers == { };
assert asksFor "git push *";
assert asksFor "rm *";
assert asksFor "sudo *";
assert asksFor "rebuild *";
assert asksFor "gh pr merge *";
assert lib.any (
  rule: rule.action == "generate_image" && rule.resource == "*" && rule.effect == "ask"
) personalServer.permissions;
assert cli."$schema" == "https://opencode.ai/v2/cli.json";
assert
  cli.theme == {
    name = "system";
    mode = "system";
  };
assert cli.session.permissions == "prompt";
assert cli.tabs.mode == "auto";
assert cli.mini.work_spinner == "density-wave";
assert cli.keybinds.leader == "ctrl+o";
assert cli.keybinds."open.menu" == "<leader>o";
assert cli.keybinds."diff.open" == "<leader>d";
assert cli.keybinds."session.toggle.thinking" == "<leader>shift+t";
assert cli.experimental."new-designs";
assert cli.experimental."client-mcp";
assert personalCliText == workCliText;
assert personal.config.xdg.configFile."opencode/opencode.json".force;
assert work.config.xdg.configFile."opencode/opencode.json".force;
pkgs.runCommand "opencode-v2-config-check"
  {
    nativeBuildInputs = [ pkgs.check-jsonschema ];
  }
  ''
    check-jsonschema --schemafile ${pkgs.opencode}/share/config.json \
      ${personalServerFile} ${workServerFile}
    check-jsonschema --schemafile ${pkgs.opencode}/share/cli.json ${cliFile}
    touch "$out"
  ''
