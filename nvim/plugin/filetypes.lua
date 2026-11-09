vim.filetype.add({
	extension = {
		gotmpl = "gotmpl",
		mdx = "markdown",
		tmpl = "gotmpl",
		tpl = "gotmpl",
	},
	filename = {
		["buf.yaml"] = "buf-config",
		["buf.gen.yaml"] = "buf-config",
		["buf.work.yaml"] = "buf-config",
		["docker-compose.yaml"] = "yaml.docker-compose",
		["docker-compose.yml"] = "yaml.docker-compose",
		["compose.yaml"] = "yaml.docker-compose",
		["compose.yml"] = "yaml.docker-compose",
	},
})
