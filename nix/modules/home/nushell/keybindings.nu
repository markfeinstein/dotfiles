$env.config.keybindings = ($env.config.keybindings? | default []) ++ [
    {
        name: move_word_left
        modifier: alt
        keycode: left
        mode: [emacs, vi_insert, vi_normal]
        event: { edit: MoveWordLeft }
    }
    {
        name: move_word_right
        modifier: alt
        keycode: right
        mode: [emacs, vi_insert, vi_normal]
        event: { edit: MoveWordRightEnd }
    }
    {
        name: move_word_left_alt_b
        modifier: alt
        keycode: char_b
        mode: [emacs, vi_insert, vi_normal]
        event: { edit: MoveWordLeft }
    }
    {
        name: move_word_right_alt_f
        modifier: alt
        keycode: char_f
        mode: [emacs, vi_insert, vi_normal]
        event: { edit: MoveWordRightEnd }
    }
]
