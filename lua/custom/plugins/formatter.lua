return {
  "mhartington/formatter.nvim",
  config = function()
    local util = require "formatter.util"
    require("formatter").setup {
      logging = true,
      log_level = vim.log.levels.WARN,
      filetype = {
        -- Formatter configurations for filetype "lua" go here
        -- and will be executed in order
        lua = {
          -- "formatter.filetypes.lua" defines default configurations for the
          -- "lua" filetype
          require("formatter.filetypes.lua").stylua,
          -- You can also define your own configuration
          function()
            -- Supports conditional formatting
            if util.get_current_buffer_file_name() == "special.lua" then
              return nil
            end
            -- Full specification of configurations is down below and in Vim help
            -- files
            return {
              exe = "stylua",
              args = {
                "--search-parent-directories",
                "--stdin-filepath",
                util.escape_path(util.get_current_buffer_file_path()),
                "--",
                "-",
              },
              stdin = true,
            }
          end
        },
        -- javascript = {
        --   function()
        --     return {
        --       exe = "prettierd",
        --       args = { vim.api.nvim_buf_get_name(0) },
        --       stdin = true
        --     }
        --   end
        -- },
        javascript = {
          require("formatter.filetypes.javascript").prettierd
        },
        typescript = {
          require("formatter.filetypes.typescript").prettierd
        },
        javascriptreact = {
          require("formatter.filetypes.javascriptreact").prettierd
        },
        html = {
          function()
            return {
              exe = "prettierd",
              args = { vim.api.nvim_buf_get_name(0) },
              stdin = true
            }
          end
        },
        css = {
          function()
            return {
              exe = "prettierd",
              args = { vim.api.nvim_buf_get_name(0) },
              stdin = true
            }
          end
        },
        yaml = {
          function()
            return {
              exe = "prettierd",
              args = { vim.api.nvim_buf_get_name(0) },
              stdin = true
            }
          end
        },
        json = {
          function()
            return {
              exe = "prettierd",
              args = { vim.api.nvim_buf_get_name(0) },
              stdin = true
            }
          end
        },
        -- Use the special "*" filetype for defining formatter configurations on
        -- any filetype
        ["*"] = {
          -- "formatter.filetypes.any" defines default configurations for any
          -- filetype
          require("formatter.filetypes.any").remove_trailing_whitespace
        }
      }
    }
  end,
}
