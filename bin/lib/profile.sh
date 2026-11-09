#!/bin/sh

# This sourced library reads and sets variables owned by its caller.
# shellcheck disable=SC2034,SC2154
persist_dotfiles_profile() {
  profile_dir=$(dirname "$profile_file")
  umask 077
  mkdir -p "$profile_dir" || fail "could not create profile directory: $profile_dir"
  profile_tmp=$(mktemp "$profile_dir/profile.tmp.XXXXXX") || fail 'could not create profile temp file'
  printf '%s\n' "$profile" >"$profile_tmp"
  chmod 600 "$profile_tmp"
  mv -f "$profile_tmp" "$profile_file"
  profile_tmp=
}

select_dotfiles_profile() {
  persist_profile=0
  if [ -z "$profile" ] && [ -n "${DOTFILES_PROFILE:-}" ]; then
    profile=$DOTFILES_PROFILE
  elif [ -z "$profile" ] && [ -f "$profile_file" ]; then
    IFS= read -r profile <"$profile_file" || fail "could not read persisted profile: $profile_file"
  elif [ -z "$profile" ]; then
    [ -r /dev/tty ] || fail 'pass --profile, set DOTFILES_PROFILE, or create the persisted profile file'
    printf 'Select profile: 1) personal  2) work\nSelection: ' >/dev/tty
    IFS= read -r answer </dev/tty || fail 'could not read profile'
    case $answer in
      1|personal) profile=personal ;;
      2|work) profile=work ;;
      *) fail 'invalid profile' ;;
    esac
    persist_profile=1
  fi

  case $profile in
    personal|work) ;;
    *) fail "invalid profile: $profile" ;;
  esac
  [ "$profile_from_flag" -eq 0 ] || persist_profile=1
  [ "$persist_profile" -eq 0 ] || persist_dotfiles_profile
}

resolve_dotfiles_system() {
  case $(uname -s) in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    *) fail 'unsupported OS (macOS and Linux only)' ;;
  esac
  case $(uname -m) in
    arm64|aarch64) arch=aarch64 ;;
    x86_64|amd64) arch=x86_64 ;;
    *) fail 'unsupported CPU architecture' ;;
  esac
  system="${arch}-${os}"
}
