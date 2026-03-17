local M = {}

M.REACTION_EMOJI = {
  THUMBS_UP = "👍",
  THUMBS_DOWN = "👎",
  LAUGH = "😄",
  CONFUSED = "😕",
  HEART = "❤️",
  HOORAY = "🎉",
  ROCKET = "🚀",
  EYES = "👀",
}

M.REACTION_ORDER = { "THUMBS_UP", "THUMBS_DOWN", "LAUGH", "HOORAY", "CONFUSED", "HEART", "ROCKET", "EYES" }

M.state = {
  pr_number = nil,
  pr_id = nil,
  head_sha = nil,
  owner = nil,
  repo = nil,
  threads = {},
  threads_by_file = {},
  changed_files = {},
  repo_root = nil,
  base_branch = nil,
  viewer_login = nil,
  repo_prs = nil,
  pending_comments = {},
}

function M.get_repo_root()
  if M.state.repo_root then return M.state.repo_root end
  local result = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or #result == 0 then return nil end
  M.state.repo_root = result[1]
  return M.state.repo_root
end

function M.get_base_branch()
  if M.state.base_branch then return M.state.base_branch end
  local result = vim.fn.systemlist({ "git", "symbolic-ref", "refs/remotes/origin/HEAD" })
  if vim.v.shell_error == 0 and #result > 0 then
    local branch = result[1]:match("refs/remotes/origin/(.+)")
    if branch then
      M.state.base_branch = "origin/" .. branch
      return M.state.base_branch
    end
  end
  for _, name in ipairs({ "main", "master", "develop" }) do
    local check = vim.fn.systemlist({ "git", "rev-parse", "--verify", "origin/" .. name })
    if vim.v.shell_error == 0 and #check > 0 then
      M.state.base_branch = "origin/" .. name
      return M.state.base_branch
    end
  end
  return nil
end

function M.get_repo_info()
  if M.state.owner and M.state.repo then
    return M.state.owner, M.state.repo
  end
  local result = vim.fn.systemlist({
    "gh", "repo", "view", "--json", "owner,name",
    "-q", '.owner.login + "/" + .name',
  })
  if vim.v.shell_error ~= 0 or #result == 0 then return nil, nil end
  local owner, repo = result[1]:match("^(.+)/(.+)$")
  M.state.owner = owner
  M.state.repo = repo
  return owner, repo
end

function M.get_pr_number()
  if M.state.pr_number then return M.state.pr_number end
  local result = vim.fn.systemlist({ "gh", "pr", "view", "--json", "number", "-q", ".number" })
  if vim.v.shell_error ~= 0 or #result == 0 then return nil end
  M.state.pr_number = tonumber(result[1])
  return M.state.pr_number
end

function M.get_repo_info_async(callback)
  if M.state.owner and M.state.repo then
    callback(M.state.owner, M.state.repo)
    return
  end
  vim.fn.jobstart({
    "gh", "repo", "view", "--json", "owner,name",
    "-q", '.owner.login + "/" + .name',
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local output = table.concat(data, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      if output == "" then return end
      local owner, repo = output:match("^(.+)/(.+)$")
      if owner and repo then
        M.state.owner = owner
        M.state.repo = repo
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code ~= 0 or not M.state.owner then
          callback(nil, nil)
        else
          callback(M.state.owner, M.state.repo)
        end
      end)
    end,
  })
end

function M.get_pr_number_async(callback)
  if M.state.pr_number then
    callback(M.state.pr_number)
    return
  end
  vim.fn.jobstart({
    "gh", "pr", "view", "--json", "number", "-q", ".number",
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local output = table.concat(data, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      if output == "" then return end
      M.state.pr_number = tonumber(output)
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code ~= 0 or not M.state.pr_number then
          callback(nil)
        else
          callback(M.state.pr_number)
        end
      end)
    end,
  })
end

function M.fetch_threads(callback)
  M.get_repo_info_async(function(owner, repo)
    if not owner or not repo then
      if callback then callback(nil, "Could not detect repo (offline?)") end
      return
    end
    M.get_pr_number_async(function(pr)
      if not pr then
        if callback then callback(nil, "Not on a PR branch (or offline)") end
        return
      end
      M._fetch_threads_graphql(owner, repo, pr, callback)
    end)
  end)
end

function M._fetch_threads_graphql(owner, repo, pr, callback)
  local query = [[
    query($owner: String!, $repo: String!, $pr: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          id
          headRefOid
          files(first: 100) {
            nodes {
              path
              additions
              deletions
              changeType
              viewerViewedState
            }
          }
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              isOutdated
              line
              startLine
              path
              diffSide
              comments(first: 50) {
                nodes {
                  id
                  databaseId
                  body
                  author { login }
                  createdAt
                  url
                  reactions(first: 20) {
                    nodes {
                      content
                      user { login }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  ]]

  vim.fn.jobstart({
    "gh", "api", "graphql",
    "-F", "owner=" .. owner,
    "-F", "repo=" .. repo,
    "-F", "pr=" .. tostring(pr),
    "-f", "query=" .. query,
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local json_str = table.concat(data, "\n")
      if json_str:match("^%s*$") then return end

      local ok, decoded = pcall(vim.json.decode, json_str)
      if not ok or not decoded or not decoded.data then
        vim.schedule(function()
          if callback then callback(nil, "Failed to parse API response") end
        end)
        return
      end

      local pr_data = decoded.data.repository.pullRequest
      M.state.pr_id = pr_data.id
      M.state.head_sha = pr_data.headRefOid
      M.state.changed_files = pr_data.files and pr_data.files.nodes or {}
      M.state.threads = pr_data.reviewThreads.nodes or {}

      -- Sanitize vim.NIL → nil for fields that can be JSON null
      for _, thread in ipairs(M.state.threads) do
        if type(thread.line) ~= "number" then thread.line = nil end
        if type(thread.startLine) ~= "number" then thread.startLine = nil end
        local comments = type(thread.comments) == "table" and thread.comments.nodes or {}
        for _, comment in ipairs(comments) do
          if type(comment.author) ~= "table" then comment.author = nil end
          if type(comment.reactions) ~= "table" then comment.reactions = nil end
        end
      end

      M.state.threads_by_file = {}
      for _, thread in ipairs(M.state.threads) do
        if thread.path then
          if not M.state.threads_by_file[thread.path] then
            M.state.threads_by_file[thread.path] = {}
          end
          table.insert(M.state.threads_by_file[thread.path], thread)
        end
      end

      vim.schedule(function()
        if callback then callback(M.state.threads) end
      end)
    end,
  })
end

function M.add_comment(path, line, body, callback)
  local owner, repo = M.get_repo_info()
  local pr = M.get_pr_number()
  if not owner or not pr or not M.state.head_sha then
    if callback then callback(false, "Missing PR info. Run :GhPrRefresh first.") end
    return
  end

  vim.fn.jobstart({
    "gh", "api",
    string.format("repos/%s/%s/pulls/%d/comments", owner, repo, pr),
    "-f", "body=" .. body,
    "-f", "commit_id=" .. M.state.head_sha,
    "-f", "path=" .. path,
    "-F", "line=" .. tostring(line),
    "-f", "side=RIGHT",
    "-f", "subject_type=line",
  }, {
    stdout_buffered = true,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if callback then callback(exit_code == 0) end
      end)
    end,
  })
end

function M.reply_to_comment(comment_db_id, body, callback)
  local owner, repo = M.get_repo_info()
  local pr = M.get_pr_number()
  if not owner or not pr then
    if callback then callback(false, "Missing PR info") end
    return
  end

  vim.fn.jobstart({
    "gh", "api",
    string.format("repos/%s/%s/pulls/%d/comments/%d/replies", owner, repo, pr, comment_db_id),
    "-f", "body=" .. body,
  }, {
    stdout_buffered = true,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if callback then callback(exit_code == 0) end
      end)
    end,
  })
end

function M.resolve_thread(thread_id, callback)
  vim.fn.jobstart({
    "gh", "api", "graphql",
    "-f", "query=mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { id isResolved } } }",
    "-f", "id=" .. thread_id,
  }, {
    stdout_buffered = true,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if callback then callback(exit_code == 0) end
      end)
    end,
  })
end

function M.unresolve_thread(thread_id, callback)
  vim.fn.jobstart({
    "gh", "api", "graphql",
    "-f", "query=mutation($id: ID!) { unresolveReviewThread(input: {threadId: $id}) { thread { id isResolved } } }",
    "-f", "id=" .. thread_id,
  }, {
    stdout_buffered = true,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if callback then callback(exit_code == 0) end
      end)
    end,
  })
end

function M.mark_file_viewed(path, callback)
  if not M.state.pr_id then
    if callback then callback(false, "Missing PR ID. Run :GhPrRefresh first.") end
    return
  end

  vim.fn.jobstart({
    "gh", "api", "graphql",
    "-f", "query=mutation($prId: ID!, $path: String!) { markFileAsViewed(input: {pullRequestId: $prId, path: $path}) { clientMutationId } }",
    "-f", "prId=" .. M.state.pr_id,
    "-f", "path=" .. path,
  }, {
    stdout_buffered = true,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        for _, file in ipairs(M.state.changed_files) do
          if file.path == path then
            file.viewerViewedState = "VIEWED"
            break
          end
        end
      end
      vim.schedule(function()
        if callback then callback(exit_code == 0) end
      end)
    end,
  })
end

function M.mark_file_unviewed(path, callback)
  if not M.state.pr_id then
    if callback then callback(false, "Missing PR ID. Run :GhPrRefresh first.") end
    return
  end

  vim.fn.jobstart({
    "gh", "api", "graphql",
    "-f", "query=mutation($prId: ID!, $path: String!) { unmarkFileAsViewed(input: {pullRequestId: $prId, path: $path}) { clientMutationId } }",
    "-f", "prId=" .. M.state.pr_id,
    "-f", "path=" .. path,
  }, {
    stdout_buffered = true,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        for _, file in ipairs(M.state.changed_files) do
          if file.path == path then
            file.viewerViewedState = "UNVIEWED"
            break
          end
        end
      end
      vim.schedule(function()
        if callback then callback(exit_code == 0) end
      end)
    end,
  })
end

function M.buf_relative_path(bufnr)
  local bufpath = vim.api.nvim_buf_get_name(bufnr or 0)
  local root = M.get_repo_root()
  if not root or bufpath == "" then return nil end
  if bufpath:sub(1, #root) == root then
    return bufpath:sub(#root + 2)
  end
  return nil
end

function M.invalidate()
  M.state.pr_number = nil
  M.state.pr_id = nil
  M.state.head_sha = nil
  M.state.owner = nil
  M.state.repo = nil
  M.state.threads = {}
  M.state.threads_by_file = {}
  M.state.changed_files = {}
  M.state.repo_root = nil
  M.state.base_branch = nil
  M.state.viewer_login = nil
  M.state.repo_prs = nil
end

function M.get_viewer_login_async(callback)
  if M.state.viewer_login then
    callback(M.state.viewer_login)
    return
  end
  vim.fn.jobstart({ "gh", "api", "user", "-q", ".login" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local output = table.concat(data, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      if output ~= "" then
        M.state.viewer_login = output
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code ~= 0 or not M.state.viewer_login then
          callback(nil)
        else
          callback(M.state.viewer_login)
        end
      end)
    end,
  })
end

function M.fetch_repo_prs(callback)
  M.get_viewer_login_async(function(login)
    if not login then
      if callback then callback(nil, "Could not detect GitHub user") end
      return
    end
    local config = require("gh-review.config")
    local limit = tostring(config.get().pr_list.limit)
    local fields = "number,title,body,url,isDraft,createdAt,updatedAt,author,headRefName,reviewDecision,additions,deletions,statusCheckRollup,reviews"
    vim.fn.jobstart({
      "gh", "pr", "list",
      "--state", "open",
      "--limit", limit,
      "--json", fields,
    }, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        local json_str = table.concat(data, "\n")
        if json_str:match("^%s*$") then return end

        local ok, decoded = pcall(vim.json.decode, json_str)
        if not ok or not decoded then
          vim.schedule(function()
            if callback then callback(nil, "Failed to parse PR list response") end
          end)
          return
        end

        table.sort(decoded, function(a, b)
          return (a.createdAt or "") > (b.createdAt or "")
        end)

        M.state.repo_prs = decoded

        vim.schedule(function()
          if callback then callback(decoded) end
        end)
      end,
      on_exit = function(_, exit_code)
        if exit_code ~= 0 then
          vim.schedule(function()
            if not M.state.repo_prs and callback then
              callback(nil, "gh pr list failed")
            end
          end)
        end
      end,
    })
  end)
end

function M.add_pending_comment(path, line, start_line, body)
  table.insert(M.state.pending_comments, {
    path = path,
    line = line,
    start_line = start_line,
    body = body,
  })
end

function M.pending_count()
  return #M.state.pending_comments
end

function M.discard_pending()
  M.state.pending_comments = {}
end

function M.submit_review(event, body, callback)
  local owner, repo = M.get_repo_info()
  local pr = M.get_pr_number()
  if not owner or not pr then
    if callback then callback(false, "Missing PR info") end
    return
  end

  local comments = {}
  for _, c in ipairs(M.state.pending_comments) do
    local comment = {
      path = c.path,
      line = c.line,
      side = "RIGHT",
      body = c.body,
    }
    if c.start_line then
      comment.start_line = c.start_line
      comment.start_side = "RIGHT"
    end
    table.insert(comments, comment)
  end

  local payload = { event = event }
  if body and body ~= "" then
    payload.body = body
  end
  if #comments > 0 then
    payload.comments = comments
  end

  local json_str = vim.json.encode(payload)
  local endpoint = string.format("repos/%s/%s/pulls/%d/reviews", owner, repo, pr)

  local job_id = vim.fn.jobstart({ "gh", "api", endpoint, "--input", "-" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code == 0 then
          M.state.pending_comments = {}
          if callback then callback(true) end
        else
          if callback then callback(false, "API request failed") end
        end
      end)
    end,
  })
  vim.fn.chansend(job_id, json_str)
  vim.fn.chanclose(job_id, "stdin")
end

function M.toggle_reaction(comment_id, content, has_reacted, callback)
  local mutation
  if has_reacted then
    mutation = "mutation($id: ID!, $content: ReactionContent!) { removeReaction(input: {subjectId: $id, content: $content}) { reaction { content } } }"
  else
    mutation = "mutation($id: ID!, $content: ReactionContent!) { addReaction(input: {subjectId: $id, content: $content}) { reaction { content } } }"
  end

  vim.fn.jobstart({
    "gh", "api", "graphql",
    "-f", "query=" .. mutation,
    "-f", "id=" .. comment_id,
    "-f", "content=" .. content,
  }, {
    stdout_buffered = true,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if callback then callback(exit_code == 0) end
      end)
    end,
  })
end

function M.merge_pr(method, callback)
  local pr = M.get_pr_number()
  if not pr then
    if callback then callback(false, "Not on a PR branch") end
    return
  end

  vim.fn.jobstart({ "gh", "pr", "merge", tostring(pr), "--" .. method }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if callback then callback(exit_code == 0) end
      end)
    end,
  })
end

return M
