return {
	-- nvim-lspconfig's htmx defaults include markdown/mdx. htmx-lsp returns
	-- invalid empty completion responses for plain Markdown buffers, which
	-- spams LSP[htmx] INVALID_SERVER_MESSAGE while typing prompts/notes.
	filetypes = require("mark.lsp_servers").filetypes.htmx,
}
