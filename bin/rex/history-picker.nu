def main [
    rex_session: string
    rex_block: string
    database: string
    history_session: int
    working_directory: string
    workspace: string
    result_file: string
    initial_query: string
] {
    cd $working_directory
    let db = $database
    let sid = $history_session
    let ws_sql = ($workspace | str replace --all "'" "''")
    let ws_like = ($ws_sql | str replace --all "\\" "\\\\" | str replace --all "%" "\\%" | str replace --all "_" "\\_")
    let now_ms = ((date now | into int) / 1_000_000)
    let dir = (mktemp -d)

    open $db | query db "CREATE INDEX IF NOT EXISTS idx_history_session_id ON history(session_id, id DESC)"
    open $db | query db "CREATE INDEX IF NOT EXISTS idx_history_cwd_id ON history(cwd, id DESC)"

    # SQL handles display formatting and keeps the original command available
    # by hidden history ID, including commands containing tabs or newlines.
    let query_tpl = ("WITH recent AS (
      SELECT id, command_line,
        TRIM(REPLACE(REPLACE(REPLACE(command_line, CHAR(9), ' '), CHAR(10), ' '), CHAR(13), ' ')) as cmd,
        COALESCE(exit_status, 0) as exit_status,
        duration_ms,
        start_timestamp
      FROM history __WHERE__
      ORDER BY id DESC LIMIT __SCAN_LIMIT__
    ), dedup AS (
      SELECT MAX(id) as mid, cmd FROM recent GROUP BY cmd ORDER BY mid DESC LIMIT __LIMIT__
    )
    SELECT r.id || CHAR(9) ||
      CASE
        WHEN r.exit_status = 0 THEN CHAR(27) || '[38;2;49;116;143m'
        ELSE CHAR(27) || '[38;2;235;111;146m'
      END ||
      PRINTF('%6s', CASE
        WHEN r.duration_ms IS NULL OR r.duration_ms < 1000
          THEN COALESCE(CAST(r.duration_ms AS TEXT), '0') || 'ms'
        WHEN r.duration_ms < 60000 THEN CAST(r.duration_ms/1000 AS TEXT) || 's'
        ELSE CAST(r.duration_ms/60000 AS TEXT) || 'm'
      END) || CHAR(27) || '[0m  ' || CHAR(27) || '[38;2;110;106;134m' ||
      PRINTF('%8s', CASE
        WHEN r.start_timestamp IS NULL THEN '?'
        WHEN (__NOW__ - r.start_timestamp) < 60000
          THEN CAST(ROUND((__NOW__ - r.start_timestamp)/1000.0) AS INTEGER) || 's ago'
        WHEN (__NOW__ - r.start_timestamp) < 3600000
          THEN CAST(ROUND((__NOW__ - r.start_timestamp)/60000.0) AS INTEGER) || 'm ago'
        WHEN (__NOW__ - r.start_timestamp) < 86400000
          THEN CAST(ROUND((__NOW__ - r.start_timestamp)/3600000.0) AS INTEGER) || 'h ago'
        ELSE CAST(ROUND((__NOW__ - r.start_timestamp)/86400000.0) AS INTEGER) || 'd ago'
      END) || CHAR(27) || '[0m' || CHAR(9) || dedup.cmd as line
    FROM recent r JOIN dedup ON r.id = dedup.mid
    ORDER BY r.id DESC" | str replace --all "__NOW__" $"($now_ms)")
    let scope_query = {|where_clause: string, limit: int, scan_limit: int|
        $query_tpl | str replace "__WHERE__" $where_clause | str replace "__LIMIT__" $"($limit)" | str replace "__SCAN_LIMIT__" $"($scan_limit)"
    }
    let format_scope = {|scope_name: string|
        let q = (open $"($dir)/($scope_name).sql")
        let entries = (open $db | query db $q)
        let lines = ($entries | each { |row| $row.line })
        $lines | str join "\n" | save -f $"($dir)/($scope_name)"
        $entries | is-not-empty
    }

    do $scope_query $"WHERE session_id = ($sid)" 200 1000 | save -f $"($dir)/session.sql"
    do $scope_query $"WHERE cwd = '($ws_sql)' OR cwd LIKE '($ws_like)/%' ESCAPE '\\'" 500 2500 | save -f $"($dir)/workspace.sql"
    do $scope_query "" 1000 5000 | save -f $"($dir)/global.sql"
    let has_session = (do $format_scope session)
    let has_workspace = (if $has_session { false } else { do $format_scope workspace })
    let has_global = (if ($has_session or $has_workspace) { false } else { do $format_scope global })
    let initial = (if $has_session {
        "session"
    } else if $has_workspace {
        "workspace"
    } else if $has_global {
        "global"
    } else {
        rm -rf $dir
        if ($result_file | is-not-empty) { rm -f $result_file }
        return
    })

    $initial | save -f $"($dir)/scope"
    $db | save -f $"($dir)/db"
    ("#!/usr/bin/env nu
let dir = 'DIR'
let db = (open $'($dir)/db')
let scope = $env.SCOPE
let q = (open $'($dir)/($scope).sql')
let entries = (open $db | query db $q)
let lines = ($entries | each { |row| $row.line })
$lines | str join '\n' | save -f $'($dir)/($scope)'" | str replace --all DIR $dir | save -f $"($dir)/render-scope.nu")
    ("#!/bin/sh\ns=$(cat DIR/scope)\ncase $s in session) ns=workspace;; workspace) ns=global;; *) ns=session;; esac\nprintf '%s' \"$ns\" > DIR/scope\nif [ ! -s \"DIR/$ns\" ]; then SCOPE=\"$ns\" nu --no-config-file DIR/render-scope.nu >/dev/null 2>&1; fi\nprintf 'reload-sync(cat \"DIR/%s\")+change-prompt(  %s history ❯ )\n' \"$ns\" \"$ns\"" | str replace --all DIR $dir | save -f $"($dir)/cycle-scope.sh")
    chmod +x $"($dir)/cycle-scope.sh" $"($dir)/render-scope.nu"

    let bind = ("ctrl-r:transform(DIR/cycle-scope.sh),tab:accept,ctrl-o:accept,ctrl-y:accept,ctrl-d:half-page-down,ctrl-u:half-page-up,scroll-up:up,scroll-down:down" | str replace --all DIR $dir)
    let hint = $"(ansi dark_gray)Ctrl-R switches scope · Tab inserts · Ctrl-O edits(ansi reset)"
    let raw = (
        ^cat $"($dir)/($initial)"
        | ^$env.FZF_BIN_PATH --ansi --bind $bind --expect "tab,ctrl-o,ctrl-y" --layout=reverse --no-sort --info=inline-right --color $"($env.DOTFILES_FZF_COLORS),info:8" --delimiter "\t" --with-nth "2.." --nth "2.." --prompt $"  ($initial) history ❯ " --footer $hint --query $initial_query
        | decode utf-8
        | str trim --right
    )
    rm -rf $dir
    if ($raw | is-empty) {
        if ($result_file | is-not-empty) { rm -f $result_file }
        return
    }

    let output_lines = ($raw | split row "\n")
    let key_to_action = {tab: insert, "ctrl-o": edit, "ctrl-y": insert}
    let expect_key = ($output_lines | first)
    let action = if $expect_key in ($key_to_action | columns) {
        $key_to_action | get $expect_key
    } else {
        "run"
    }
    let selection = ($output_lines | skip 1 | str join "\n")
    if ($selection | is-empty) {
        if ($result_file | is-not-empty) { rm -f $result_file }
        return
    }
    let history_id = try {
        $selection | split row "\t" | first | into int
    } catch {
        if ($result_file | is-not-empty) { rm -f $result_file }
        return
    }
    mut command = try {
        open $db | query db $"SELECT command_line FROM history WHERE id = ($history_id) LIMIT 1" | get 0.command_line
    } catch {
        if ($result_file | is-not-empty) { rm -f $result_file }
        return
    }
    mut result_action = $action

    if $action == "edit" {
        let edit_file = (mktemp --suffix .sh)
        $command | save -f $edit_file
        ^$env.EDITOR $edit_file
        $command = (open $edit_file | str trim)
        rm -f $edit_file
        if ($command | is-empty) {
            if ($result_file | is-not-empty) { rm -f $result_file }
            return
        }
        $result_action = "insert"
    }

    let result = {command: $command, action: $result_action}
    if ($result_file | is-not-empty) {
        $result | to json | save -f $result_file
        ^$env.REX_BIN_PATH send-key -s $rex_session -b $rex_block f13
    } else {
        print ($result | to json)
    }
}
