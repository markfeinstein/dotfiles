{config}: let
  primaryUser = config.system.primaryUser;
  primaryHome = config.profile.user.homeDirectory;
  asPrimaryUser = command: ''
    launchctl asuser "$(id -u ${primaryUser})" sudo -u "${primaryUser}" -- \
      ${command}
  '';
in {
  inherit asPrimaryUser;

  configureMacosSymbolicHotKeys = {
    disabledMacosSymbolicHotKeysArgs,
    enabledMacosSymbolicHotKeysArgs,
  }: ''
    # Preserve each shortcut's existing parameters while changing only its
    # enabled state. Explicitly re-enable shortcuts released by the selected
    # manager so switching managers reverses earlier activation changes.
    macos_persisted_preferences_changed=0
    disabled_hotkeys_result="$(
      ${asPrimaryUser "/usr/bin/python3 ${./scripts/set-macos-symbolic-hotkeys.py} ${primaryHome}/Library/Preferences/com.apple.symbolichotkeys.plist disable ${disabledMacosSymbolicHotKeysArgs}"}
    )"
    case "$disabled_hotkeys_result" in
      changed) macos_persisted_preferences_changed=1 ;;
      unchanged) ;;
      *) echo "unexpected symbolic-hotkey update result: $disabled_hotkeys_result" >&2; exit 1 ;;
    esac
    enabled_hotkeys_result="$(
      ${asPrimaryUser "/usr/bin/python3 ${./scripts/set-macos-symbolic-hotkeys.py} ${primaryHome}/Library/Preferences/com.apple.symbolichotkeys.plist enable ${enabledMacosSymbolicHotKeysArgs}"}
    )"
    case "$enabled_hotkeys_result" in
      changed) macos_persisted_preferences_changed=1 ;;
      unchanged) ;;
      *) echo "unexpected symbolic-hotkey update result: $enabled_hotkeys_result" >&2; exit 1 ;;
    esac
  '';

  disableSafariSidebarShortcut = ''
    # Safari owns Cmd+Shift+L as View -> Show/Hide Sidebar. If global shortcut
    # interception ever misses the event (for example while macOS is showing a
    # native text selection overlay), Safari can handle it and steal focus. Assign the menu
    # items to a zero-width-space key equivalent globally, which effectively
    # disables the default shortcut while keeping the menu items available.
    #
    # Do not write Safari's containerized preference plists here: recent macOS
    # versions may deny activation scripts access to app containers even when
    # running as the target user, producing noisy Operation not permitted
    # warnings during every rebuild.
    safari_sidebar_result="$(
      ${asPrimaryUser "/usr/bin/python3 ${./scripts/disable-safari-sidebar-shortcut.py}"}
    )"
    case "$safari_sidebar_result" in
      changed) macos_persisted_preferences_changed=1 ;;
      unchanged) ;;
      *) echo "unexpected Safari shortcut update result: $safari_sidebar_result" >&2; exit 1 ;;
    esac
  '';

  reloadPreferencesAndConfigureLiveHotKeys = {configureMacosSymbolicHotKeys}: ''
    # Reload the plist, then apply both disabled and enabled states to the live
    # WindowServer session without requiring logout.
    if [ "''${macos_persisted_preferences_changed:-0}" -eq 1 ]; then
      ${asPrimaryUser "/usr/bin/killall cfprefsd 2>/dev/null || true"}
      ${asPrimaryUser "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u"}
    fi
    ${asPrimaryUser "${configureMacosSymbolicHotKeys}/bin/configure-macos-symbolic-hotkeys"}
  '';
}
