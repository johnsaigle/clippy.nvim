local M = {}

local namespace = nil

-- Default configuration
local defaults = {
	-- Enable the plugin by default
	enabled = true,
	severity_map = {
		deny = vim.diagnostic.severity.ERROR,
		-- NOTE that clippy rules can be configured as "warn" but the JSON value is "warning"
		warning = vim.diagnostic.severity.WARN,
		info = vim.diagnostic.severity.INFO,
	},
	-- Default severity if not specified
	default_severity = vim.diagnostic.severity.WARN,
	-- Additional semgrep CLI arguments
	extra_args = {},
}

M.config = vim.deepcopy(defaults)

-- Debug function to print current config.
function M.print_config()
    local config_lines = {"Current clippy.nvim configuration:"}
    for k, v in pairs(M.config) do
        if type(v) == "table" then
            table.insert(config_lines, string.format("%s: %s", k, vim.inspect(v)))
        else
            table.insert(config_lines, string.format("%s: %s", k, tostring(v)))
        end
    end
    vim.notify(table.concat(config_lines, "\n"), vim.log.levels.INFO)
end

-- Function to toggle the plugin. Clears current diagnostics.
function M.toggle()
	if not namespace then
		namespace = vim.api.nvim_create_namespace("clippy")
	end

	-- Toggle the enabled state
	M.config.enabled = not M.config.enabled
	if not M.config.enabled then
		-- Clear all diagnostics when disabling
		-- Get all buffers
		local bufs = vim.api.nvim_list_bufs()
		for _, buf in ipairs(bufs) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.diagnostic.reset(namespace, buf)
			end
		end
		vim.notify("Clippy diagnostics disabled", vim.log.levels.INFO)
	else
		vim.notify("Clippy diagnostics enabled", vim.log.levels.INFO)
		M.clippy()
	end
end

-- Helper function to convert semgrep_config to a table if it's a string
-- local function normalize_config(config)
-- 	if type(config) == "string" then
-- 		return { config }
-- 	end
-- 	return config
-- end

-- Run semgrep and populate diagnostics with the results.
function M.clippy()
	-- Load and setup null-ls integration
	local null_ls_ok, null_ls = pcall(require, "null-ls")
	if not null_ls_ok then
		vim.notify("null-ls is required for clippy.nvim", vim.log.levels.ERROR)
		return
	end

	local clippy_generator = {
		method = null_ls.methods.DIAGNOSTICS,
		filetypes = { "rust" },
		generator = {
			-- Configure when to run the diagnostics
			runtime_condition = function()
				return M.config.enabled
			end,
			-- Run on file open and after saves
			on_attach = function(client, bufnr)
				vim.api.nvim_buf_attach(bufnr, false, {
					on_load = function()
						if M.config.enabled then
							null_ls.generator()(
								{ bufnr = bufnr }
							)
						end
					end
				})
			end,
			fn = function(params)
				-- Get semgrep executable path
				local cmd = vim.fn.exepath("cargo")
				if cmd == "" then
					vim.notify("cargo clippy executable not found in PATH", vim.log.levels.ERROR)
					return {}
				end
				-- TODO add a check for a Cargo.toml file in the path

				-- Build command arguments
				local args = {
					"clippy",
					"--message-format=json",
					"--quiet",
					"--workspace",
					"--all-targets",
				}

				-- Create async system command
				vim.notify("Running clippy...", vim.diagnostic.levels.INFO)
				vim.system(
					vim.list_extend({ "cargo" }, args),
					{
						text = true,
						cwd = vim.fn.getcwd(),
						env = vim.env,
					},
					function(obj)
						local diags = {}
						-- Clippy's JSON output contains one JSON object per new-line
						local lines = vim.split(obj.stdout, "\n")
						for _, line in ipairs(lines) do
							-- Parse JSON output
							local ok, parsed = pcall(vim.json.decode, line)
							-- if ok and parsed and parsed.message then
							if ok and parsed
								and parsed.message
								-- filter out other compiler messages
								and parsed.message["$message_type"] == "diagnostic"
								-- this should only happen in unusual cases, e.g. a clippy rule has been renamed and we are invoking the old one
								and not parsed.message.spans == nil then

								-- Map clippy's severities to the onces used by diagnostics
								local severity = M.config.default_severity
								if parsed.message.level then
									severity = M.config.severity_map
									    [parsed.message.level] or
									    M.config.default_severity
								end

								-- Convert results to diagnostics
								local diag = {
									-- Lines must be offset by 1
									lnum = parsed.message.spans[1].line_start - 1,
									col = parsed.message.spans[1].column_start,
									-- Lines must be offset by 1
									end_lnum = parsed.message.spans[1].line_end - 1,
									end_col = parsed.message.spans[1].column_end,
									-- Clippy rule name like clippy:integer_division
									source = parsed.message.code.code,
									-- Rule warning and URL
									message = parsed.message.children[1].message,
									severity = severity,
								}
								table.insert(diags, diag)
							end
						end
						-- Schedule the diagnostic updates
						vim.schedule(function()
							local namespace = vim.api.nvim_create_namespace(
								"clippy")
							vim.diagnostic.set(namespace, params.bufnr, diags)
						end)
					end
				)
				return {}
			end
		}
	}

	null_ls.register(clippy_generator)
end

-- Setup function to initialize the plugin
function M.setup(opts)
	if opts then
		for k, v in pairs(opts) do
			M.config[k] = v
		end
	end

	if M.config.enabled then
		M.clippy()
	end
end

return M
