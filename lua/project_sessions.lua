local M = {}

-- The catalog is deliberately limited to the external development volume. The
-- session directory remains untouched: it is only a source for a project's
-- most useful saved layout.
local catalog_root = "/Volumes/ZX10"
local scan_max_depth = 8
local scan_max_directories = 5000
local cache_ttl_ms = 30000

local root_markers = {
  ".git",
  "go.mod",
  "package.json",
  "composer.json",
  "pyproject.toml",
  "Cargo.toml",
  "Gemfile",
  "mix.exs",
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "CMakeLists.txt",
  "Makefile",
  "docker-compose.yml",
  "docker-compose.yaml",
}

local marker_set = {}
for _, marker in ipairs(root_markers) do
  marker_set[marker] = true
end

-- Never descend into dependency, build, backup, or volume-management folders.
-- Apart from keeping the scan fast, this prevents dependency manifests from
-- being presented as projects.
local ignored_directory_names = {
  ".git",
  ".cache",
  ".codex-e2e",
  ".codex-worktrees",
  ".fseventsd",
  ".next",
  ".next-dev",
  ".Spotlight-V100",
  ".turbo",
  ".TemporaryItems",
  ".Trash-1000",
  ".venv",
  ".worktrees",
  "__pycache__",
  "backups",
  "build",
  "cache",
  "coverage",
  "dist",
  "node_modules",
  "Pods",
  "target",
  "vendor",
  "venv",
}
local ignored_directories = {}
for _, directory in ipairs(ignored_directory_names) do
  ignored_directories[directory] = true
end

-- These top-level folders contain media or virtual-volume data rather than
-- source trees. They are pruned before the bounded recursive scan begins.
local ignored_volume_directory_names = {
  "osmo",
  "photos_from_my_phone",
  "volumes",
}
local ignored_volume_directories = {}
for _, directory in ipairs(ignored_volume_directory_names) do
  ignored_volume_directories[directory] = true
end

local catalog_cache

local function path_stat(path) return path and vim.uv.fs_stat(path) or nil end

local function is_directory(path)
  local stat = path_stat(path)
  return stat and stat.type == "directory"
end

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then return nil end
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local function is_within_catalog(path)
  path = normalize_path(path)
  return path and (path == catalog_root or vim.startswith(path, catalog_root .. "/")) or false
end

local function path_join(directory, name) return directory .. "/" .. name end

local function basename(path)
  local name = vim.fs.basename(path)
  return name ~= "" and name or path
end

local function is_project_marker(name)
  return marker_set[name] or name:match("%.sln$") ~= nil
end

-- Find the nearest Git worktree first. A non-Git manifest is a fallback, so
-- an opened file inside a Git project is never shown as a separate subproject.
local function find_project_root(path)
  local stat = path_stat(path)
  if not stat then return nil end

  local directory = stat.type == "directory" and path or vim.fs.dirname(path)
  directory = normalize_path(directory)
  if not directory or not is_within_catalog(directory) then return nil end

  local manifest_root
  while directory and is_within_catalog(directory) do
    if path_stat(path_join(directory, ".git")) then return directory, ".git" end
    if not manifest_root then
      for _, marker in ipairs(root_markers) do
        if marker ~= ".git" and path_stat(path_join(directory, marker)) then
          manifest_root = directory
          break
        end
      end
    end
    if directory == catalog_root then break end
    local parent = vim.fs.dirname(directory)
    if parent == directory then break end
    directory = parent
  end
  return manifest_root
end

local function is_ignored_directory(name, parent)
  if ignored_directories[name] then return true end
  return parent == catalog_root and ignored_volume_directories[name] or false
end

local function scan_projects()
  local roots = {}
  local queue = { { path = catalog_root, depth = 0 } }
  local head, scanned = 1, 0

  while head <= #queue and scanned < scan_max_directories do
    local entry = queue[head]
    head = head + 1
    scanned = scanned + 1

    local directory, marker = entry.path
    local handle = vim.uv.fs_scandir(directory)
    if handle then
      local child_directories = {}
      while true do
        local name, kind = vim.uv.fs_scandir_next(handle)
        if not name then break end

        if name == ".git" then
          marker = ".git"
        elseif not marker and is_project_marker(name) then
          marker = name
        end

        if kind == "directory" and entry.depth < scan_max_depth and not is_ignored_directory(name, directory) then
          table.insert(child_directories, path_join(directory, name))
        end
      end

      -- A Git worktree is already a project root. Do not waste the bounded
      -- scan walking its source tree (or its nested dependencies). Non-Git
      -- marker roots keep being traversed, because they may be containers for
      -- separately versioned services.
      if marker == ".git" then child_directories = {} end

      -- Stable traversal makes a refresh deterministic and keeps the scan
      -- useful even if the bounded directory limit is reached.
      table.sort(child_directories)
      for _, child in ipairs(child_directories) do
        table.insert(queue, { path = child, depth = entry.depth + 1 })
      end
    end

    if marker then
      local root, root_marker = find_project_root(directory)
      roots[root or directory] = root_marker or marker
    end
  end

  return roots, scanned, head <= #queue
end

local function add_root_score(scores, root, score, exact)
  local item = scores[root] or { score = 0, exact = false }
  item.score = item.score + score
  item.exact = item.exact or exact
  scores[root] = item
end

local function session_candidates(data)
  local candidates = {}
  local function add(path, weight, can_be_exact)
    if type(path) ~= "string" or path == "" then return end
    table.insert(candidates, { path = path, weight = weight, can_be_exact = can_be_exact })
  end

  add(data and data.global and data.global.cwd, 100, true)
  for _, tab in ipairs((data and data.tabs) or {}) do
    add(tab.cwd, 100, true)
  end
  for _, buffer in ipairs((data and data.buffers) or {}) do
    add(buffer.name, 1, false)
  end
  return candidates
end

local function session_info(name, data, filename)
  local info = {
    name = name,
    mtime = (path_stat(filename) or {}).mtime or { sec = 0, nsec = 0 },
    has_scoped_path = false,
    has_existing_scoped_path = false,
    root_scores = {},
  }

  for _, candidate in ipairs(session_candidates(data)) do
    local path = normalize_path(candidate.path)
    if is_within_catalog(path) then
      info.has_scoped_path = true
      if path_stat(path) then
        info.has_existing_scoped_path = true
        local root = find_project_root(path)
        if root then
          add_root_score(info.root_scores, root, candidate.weight, candidate.can_be_exact and path == root)
        end
      end
    end
  end

  for root, score in pairs(info.root_scores) do
    if not info.root or score.score > info.score.score or (score.score == info.score.score and root < info.root) then
      info.root, info.score = root, score
    end
  end
  return info
end

local function mtime_is_newer(left, right)
  local left_mtime, right_mtime = left.mtime or {}, right.mtime or {}
  if (left_mtime.sec or 0) ~= (right_mtime.sec or 0) then return (left_mtime.sec or 0) > (right_mtime.sec or 0) end
  if (left_mtime.nsec or 0) ~= (right_mtime.nsec or 0) then return (left_mtime.nsec or 0) > (right_mtime.nsec or 0) end
  return left.name < right.name
end

local function preferred_session(candidate, current)
  if not current then return candidate end
  if candidate.score.exact ~= current.score.exact then return candidate.score.exact and candidate or current end
  return mtime_is_newer(candidate, current) and candidate or current
end

local function session_label(item) return string.format("%s  —  %s", basename(item.path), item.path) end

local function build_catalog()
  local roots, scanned_directories, truncated = scan_projects()
  local resession = require "resession"
  local files = require "resession.files"
  local util = require "resession.util"
  local selected_sessions = {}
  local stats = {
    scanned_directories = scanned_directories,
    scan_limit = scan_max_directories,
    truncated = truncated,
    discovered = vim.tbl_count(roots),
    session_files = 0,
    session_mapped = 0,
    session_backed_projects = 0,
    deduplicated = 0,
    stale = 0,
    outside_scope = 0,
    unmatched = 0,
    unreadable = 0,
  }

  for _, name in ipairs(resession.list { dir = "dirsession" }) do
    stats.session_files = stats.session_files + 1
    local filename = util.get_session_file(name, "dirsession")
    local ok, data = pcall(files.load_json_file, filename)
    if not ok or type(data) ~= "table" then
      stats.unreadable = stats.unreadable + 1
    else
      local info = session_info(name, data, filename)
      if not info.has_scoped_path then
        stats.outside_scope = stats.outside_scope + 1
      elseif not info.has_existing_scoped_path then
        stats.stale = stats.stale + 1
      elseif not info.root or not roots[info.root] then
        stats.unmatched = stats.unmatched + 1
      else
        stats.session_mapped = stats.session_mapped + 1
        selected_sessions[info.root] = preferred_session(info, selected_sessions[info.root])
      end
    end
  end

  local items = {}
  for path, marker in pairs(roots) do
    local session = selected_sessions[path]
    if session then stats.session_backed_projects = stats.session_backed_projects + 1 end
    table.insert(items, {
      path = path,
      marker = marker,
      name = session and session.name or nil,
      label = session_label { path = path },
    })
  end
  stats.deduplicated = stats.session_mapped - stats.session_backed_projects

  table.sort(items, function(left, right)
    local left_name, right_name = basename(left.path):lower(), basename(right.path):lower()
    return left_name == right_name and left.path < right.path or left_name < right_name
  end)
  return { items = items, stats = stats }
end

---Return the current catalog. Pass true to force a bounded rescan.
---@param force? boolean
---@return { items: table[], stats: table }
function M.catalog(force)
  local now = vim.uv.now()
  if not force and catalog_cache and now - catalog_cache.at < cache_ttl_ms then return catalog_cache.value end
  local value = build_catalog()
  catalog_cache = { at = now, value = value }
  return value
end

local function sync_neotree(path)
  local ok, command = pcall(require, "neo-tree.command")
  if not ok then return end
  command.execute {
    source = "filesystem",
    action = "show",
    position = "left",
    dir = path,
    -- Do not let follow_current_file immediately replace the selected root
    -- with the directory of a buffer from the previously active project.
    reveal = false,
  }
end

---Switch the current workspace to a project without creating an empty tab.
---This avoids AstroNvim's startup dashboard taking over the new tab before
---Neo-tree is rendered.
---@param path string
---@param opts? { keep_sidebar?: boolean }
function M.open(path, opts)
  opts = opts or {}
  if not is_directory(path) then
    catalog_cache = nil
    vim.notify("Project folder is no longer available: " .. path, vim.log.levels.WARN)
    return false
  end

  vim.cmd("tcd " .. vim.fn.fnameescape(path))
  vim.t.project_root = path

  -- Build the project sidebar first. Neo-tree otherwise briefly becomes the
  -- only window in a new tab and its close-if-last-window guard closes it.
  local ok, sidebar = pcall(require, "project_sidebar")
  if ok and not opts.keep_sidebar then sidebar.show() end
  if ok then sidebar.ensure_leftmost() end
  sync_neotree(path)
  -- Filesystem navigation is debounced by Neo-tree, which can create its
  -- left sidebar after the synchronous check above. Restore Projects to the
  -- far-left position once Neo-tree has finished opening.
  if ok then vim.defer_fn(sidebar.ensure_leftmost, 200) end
  vim.notify("Project opened: " .. path)
  return true
end

---Refresh the project-root scan without changing any saved session files.
function M.refresh()
  local catalog = M.catalog(true)
  local stats = catalog.stats
  local suffix = stats.truncated and string.format(" (limited to %d folders)", stats.scan_limit) or ""
  vim.notify(string.format("Project catalog refreshed: %d projects%s", stats.discovered, suffix))
  return catalog
end

---Show one entry for every existing project root on /Volumes/ZX10.
function M.select()
  local catalog = M.catalog()
  if #catalog.items == 0 then
    vim.notify("No project roots found on " .. catalog_root, vim.log.levels.WARN)
    return
  end

  vim.ui.select(catalog.items, {
    kind = "resession_load",
    prompt = "Open project",
    format_item = function(item) return item.label end,
  }, function(selected)
    if not selected then return end
    M.open(selected.path)
  end)
end

return M
