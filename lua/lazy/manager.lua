local Config = require("lazy.core.config")
local Task = require("lazy.task")
local Runner = require("lazy.runner")
local State = require("lazy.core.state")

local M = {}

---@alias ManagerOpts {wait?: boolean, plugins?: LazyPlugin[], clear?: boolean, show?: boolean}

---@param operation TaskType
---@param opts? ManagerOpts
---@param filter? fun(plugin:LazyPlugin):boolean?
function M.run(operation, opts, filter)
  opts = opts or {}
  local plugins = opts.plugins or Config.plugins

  if opts.clear then
    M.clear()
  end

  if opts.show then
    require("lazy.view").show()
  end

  ---@type Runner
  local runner = Runner.new()

  local on_done = function()
    vim.cmd([[do User LazyRender]])
  end

  -- install missing plugins
  for _, plugin in pairs(plugins) do
    if filter == nil or filter(plugin) then
      runner:add(Task.new(plugin, operation))
    end
  end

  if runner:is_empty() then
    return on_done()
  end

  vim.cmd([[do User LazyRender]])

  -- wait for install to finish
  runner:wait(function()
    -- check if we need to do any post-install hooks
    for _, plugin in ipairs(runner:plugins()) do
      if plugin.dirty then
        runner:add(Task.new(plugin, "docs"))
        if plugin.opt == false or plugin.run then
          runner:add(Task.new(plugin, "run"))
        end
      end
      plugin.dirty = false
      if opts.show and operation == "update" and plugin.updated and plugin.updated.from ~= plugin.updated.to then
        runner:add(Task.new(plugin, "log", {
          log = {
            from = plugin.updated.from,
            to = plugin.updated.to,
          },
        }))
      end
    end
    -- wait for post-install to finish
    runner:wait(on_done)
  end)

  -- auto show if there are tasks running
  if opts.show == nil then
    require("lazy.view").show()
  end

  if opts.wait then
    runner:wait()
  end
  return runner
end

---@param opts? ManagerOpts
function M.install(opts)
  ---@param plugin LazyPlugin
  M.run("install", opts, function(plugin)
    return plugin.uri and not plugin.installed
  end)
end

---@param opts? ManagerOpts
function M.update(opts)
  ---@param plugin LazyPlugin
  M.run("update", opts, function(plugin)
    return plugin.uri and plugin.installed
  end)
end

---@param opts? ManagerOpts
function M.log(opts)
  ---@param plugin LazyPlugin
  M.run("log", opts, function(plugin)
    return plugin.uri and plugin.installed
  end)
end

---@param opts? ManagerOpts
function M.docs(opts)
  ---@param plugin LazyPlugin
  M.run("docs", opts, function(plugin)
    return plugin.installed
  end)
end

---@param opts? ManagerOpts
function M.clean(opts)
  opts = opts or {}
  State.update_state(true)
  opts.plugins = vim.tbl_values(Config.to_clean)
  M.run("clean", opts)
end

function M.clear()
  for _, plugin in pairs(Config.plugins) do
    -- clear updated status
    plugin.updated = nil
    -- clear finished tasks
    if plugin.tasks then
      ---@param task LazyTask
      plugin.tasks = vim.tbl_filter(function(task)
        return task.running
      end, plugin.tasks)
    end
  end
  vim.cmd([[do User LazyRender]])
end

return M
