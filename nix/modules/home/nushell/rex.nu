def --env history-picker-workspace [cwd: string] {
    if (($env.HIST_PICKER_WORKSPACE_CWD? | default "") == $cwd) {
        return $env.HIST_PICKER_WORKSPACE_ROOT
    }

    let root = (try {
        ^git rev-parse --show-toplevel e> /dev/null | str trim
    } catch {
        $cwd
    })
    $env.HIST_PICKER_WORKSPACE_CWD = $cwd
    $env.HIST_PICKER_WORKSPACE_ROOT = $root
    $root
}

def apply-history-picker-result [result] {
    match $result.action {
        "run" => { commandline edit --replace --accept $result.command }
        "insert" => { commandline edit --replace $result.command }
        "copy" => { $result.command | pbcopy }
        _ => null
    }
}

def --env consume-rex-history-picker-result [] {
    let result_file = ($env.HIST_PICKER_RESULT_FILE? | default "")
    if ($result_file | is-empty) or not ($result_file | path exists) {
        return
    }

    let result = (try { open $result_file } catch { null })
    rm -f $result_file
    hide-env HIST_PICKER_RESULT_FILE
    if $result != null {
        apply-history-picker-result $result
    }
}

def --env open-history-picker [] {
    let helper = ($env.HOME + "/.local/bin/rex-history-picker")
    let db = ($nu.history-path | str replace ".txt" ".sqlite3")
    let history_session = (history session)
    let cwd = (pwd)
    let workspace = (history-picker-workspace $cwd)
    let initial_query = (commandline)
    let rex_session = ($env.REX_SESSION? | default "")
    let rex_block = ($env.REX_BLOCK? | default "")

    if (($env.HIST_PICKER_RESULT_FILE? | default "") | is-not-empty) {
        rm -f $env.HIST_PICKER_RESULT_FILE
        hide-env HIST_PICKER_RESULT_FILE
    }

    if ($rex_session | is-not-empty) and ($rex_block | is-not-empty) {
        let result_file = (mktemp --suffix .json)
        $env.HIST_PICKER_RESULT_FILE = $result_file
        let args = {
            database: $db
            history_session: $history_session
            working_directory: $cwd
            workspace: $workspace
            result_file: $result_file
            initial_query: $initial_query
        }
        let launched = (
            ^rex --autostart=false do history_picker -s $rex_session -b $rex_block --args ($args | to json)
            | complete
        )
        if $launched.exit_code != 0 {
            rm -f $result_file
            hide-env HIST_PICKER_RESULT_FILE
            error make {msg: ($launched.stderr | str trim)}
        }
        return
    }

    let picked = (
        ^$helper "" "" $db $history_session $cwd $workspace "" $initial_query
        | complete
    )
    if $picked.exit_code != 0 {
        error make {msg: ($picked.stderr | str trim)}
    }
    let output = ($picked.stdout | str trim)
    if ($output | is-not-empty) {
        apply-history-picker-result ($output | from json)
    }
}

$env.config.keybindings ++= [
    {
        name: history-search
        modifier: control
        keycode: char_r
        mode: [emacs, vi_insert, vi_normal]
        event: {send: ExecuteHostCommand, cmd: "open-history-picker"}
    }
    {
        name: rex-history-picker-result
        modifier: none
        keycode: f13
        mode: [emacs, vi_insert, vi_normal]
        event: {send: ExecuteHostCommand, cmd: "consume-rex-history-picker-result"}
    }
]

# Keep generated Rex tab labels aligned with the active repository and branch.
let rex_label_window = ($env.HOME + "/.local/bin/rex-label-window")
let rex_label_hook_installed = (
    $env.config.hooks.env_change.PWD?
    | default []
    | any {|hook|
        (try { view source $hook } catch { "" }) =~ "rex-label-window"
    }
)
if (
    $nu.is-interactive
    and ($env.REX_SESSION? | is-not-empty)
    and ($env.REX_BLOCK? | is-not-empty)
    and not $rex_label_hook_installed
) {
    $env.config.hooks.env_change.PWD = (
        $env.config.hooks.env_change.PWD?
        | default []
        | append {|_before, after|
            try { ^$rex_label_window $after } catch { null }
        }
    )
    try { ^$rex_label_window $env.PWD } catch { null }
}
