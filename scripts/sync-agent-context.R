args <- commandArgs(trailingOnly = TRUE)

trim_blank_edges <- function(lines) {
  if (!length(lines)) {
    return(lines)
  }

  start <- 1L
  end <- length(lines)

  while (start <= end && !nzchar(trimws(lines[start]))) {
    start <- start + 1L
  }

  while (end >= start && !nzchar(trimws(lines[end]))) {
    end <- end - 1L
  }

  if (start > end) {
    character()
  } else {
    lines[start:end]
  }
}

read_utf8 <- function(path) {
  trim_blank_edges(readLines(path, warn = FALSE, encoding = "UTF-8"))
}

read_source_object <- function(path, object_name) {
  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)

  if (!exists(object_name, envir = env, inherits = FALSE)) {
    stop("Expected object `", object_name, "` in ", path, call. = FALSE)
  }

  get(object_name, envir = env, inherits = FALSE)
}

write_utf8 <- function(path, lines) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, open = "w", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  writeLines(lines, con = con, useBytes = TRUE)
}

json_escape <- function(x) {
  x <- gsub("\\\\", "\\\\\\\\", x)
  x <- gsub("\"", "\\\\\"", x)
  x <- gsub("\b", "\\\\b", x, fixed = TRUE)
  x <- gsub("\f", "\\\\f", x, fixed = TRUE)
  x <- gsub("\n", "\\\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\\\r", x, fixed = TRUE)
  gsub("\t", "\\\\t", x, fixed = TRUE)
}

render_json <- function(x, indent = 0L) {
  pad <- strrep("  ", indent)
  child_pad <- strrep("  ", indent + 1L)

  if (is.null(x)) {
    return("null")
  }

  if (is.list(x)) {
    is_object <- !is.null(names(x)) && all(nzchar(names(x)))

    if (!length(x)) {
      return(if (is_object) "{}" else "[]")
    }

    rendered <- vapply(x, render_json, character(1), indent = indent + 1L)

    if (is_object) {
      entries <- sprintf('%s"%s": %s', child_pad, json_escape(names(x)), rendered)
      return(paste0(
        "{\n",
        paste0(entries, collapse = ",\n"),
        "\n",
        pad,
        "}"
      ))
    }

    entries <- sprintf("%s%s", child_pad, rendered)
    return(paste0(
      "[\n",
      paste0(entries, collapse = ",\n"),
      "\n",
      pad,
      "]"
    ))
  }

  if (length(x) > 1L) {
    return(render_json(as.list(unname(as.vector(x))), indent = indent))
  }

  if (is.character(x)) {
    return(sprintf('"%s"', json_escape(x)))
  }

  if (is.logical(x)) {
    return(if (isTRUE(x)) "true" else "false")
  }

  if (is.numeric(x)) {
    return(as.character(x))
  }

  stop("Unsupported JSON value type: ", typeof(x), call. = FALSE)
}

write_json <- function(path, x) {
  write_utf8(path, c(render_json(x), ""))
}

toml_escape <- function(x) {
  gsub("\"", "\\\\\"", x)
}

render_toml_value <- function(x) {
  if (length(x) > 1L) {
    values <- vapply(x, render_toml_value, character(1))
    return(sprintf("[ %s ]", paste(values, collapse = ", ")))
  }

  if (is.character(x)) {
    return(sprintf('"%s"', toml_escape(x)))
  }

  if (is.logical(x)) {
    return(if (isTRUE(x)) "true" else "false")
  }

  if (is.numeric(x)) {
    return(as.character(x))
  }

  stop("Unsupported TOML value type: ", typeof(x), call. = FALSE)
}

render_codex_toml <- function(mcp_servers) {
  lines <- c(
    "# Generated from `.ai/mcp/servers.R` by `Rscript scripts/sync-agent-context.R`.",
    "# Merge these entries into `~/.codex/config.toml` to enable the shared MCP servers.",
    ""
  )

  for (server_name in names(mcp_servers)) {
    server <- mcp_servers[[server_name]]
    lines <- c(lines, sprintf("[mcp_servers.%s]", server_name))

    if (!is.null(server$url)) {
      lines <- c(lines, sprintf("url = %s", render_toml_value(server$url)))
    }

    if (!is.null(server$command)) {
      lines <- c(lines, sprintf("command = %s", render_toml_value(server$command)))
    }

    if (!is.null(server$args)) {
      lines <- c(lines, sprintf("args = %s", render_toml_value(server$args)))
    }

    if (!is.null(server$env)) {
      env_names <- names(server$env)
      lines <- c(lines, "[mcp_servers.%s.env]")
      lines[length(lines)] <- sprintf("[mcp_servers.%s.env]", server_name)
      for (env_name in env_names) {
        lines <- c(
          lines,
          sprintf("%s = %s", env_name, render_toml_value(server$env[[env_name]]))
        )
      }
    }

    lines <- c(lines, "")
  }

  lines
}

normalize_mcp_server <- function(server) {
  fields <- c("type", "url", "command", "args", "env")
  server[intersect(fields, names(server))]
}

build_mcp_json <- function(mcp_servers, field_name = "mcpServers",
    include_copilot_tools = FALSE) {
  servers <- lapply(mcp_servers, function(server) {
    entry <- normalize_mcp_server(server)

    if (include_copilot_tools) {
      tools <- server$copilot_tools %||% "*"
      entry$tools <- as.list(unname(as.vector(tools)))
    }

    entry
  })

  names(servers) <- names(mcp_servers)
  structure(list(servers), names = field_name)
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

parse_frontmatter <- function(skill_path) {
  lines <- readLines(skill_path, warn = FALSE, encoding = "UTF-8")

  if (length(lines) < 3L || lines[1] != "---") {
    stop("Skill is missing YAML frontmatter: ", skill_path, call. = FALSE)
  }

  end_idx <- which(lines[-1] == "---")[1] + 1L

  if (is.na(end_idx)) {
    stop("Skill frontmatter is not closed: ", skill_path, call. = FALSE)
  }

  frontmatter <- lines[2:(end_idx - 1L)]

  name_line <- frontmatter[grepl("^name\\s*:", frontmatter)]
  desc_start <- which(grepl("^description\\s*:", frontmatter))[1]

  if (!length(name_line) || is.na(desc_start)) {
    stop("Skill frontmatter must include name and description: ", skill_path,
      call. = FALSE
    )
  }

  description_lines <- frontmatter[desc_start:length(frontmatter)]
  description_lines[1] <- sub("^description\\s*:\\s*>?\\s*", "", description_lines[1])
  description <- trimws(paste(trimws(description_lines), collapse = " "))

  list(
    name = trimws(sub("^name\\s*:\\s*", "", name_line[1])),
    description = description
  )
}

generated_note <- c(
  "> Generated from `.ai/shared/` and `.ai/skills/` by",
  "> `Rscript scripts/sync-agent-context.R`.",
  "> Do not edit this file directly.",
  ""
)

render_skill_registry <- function(skill_meta, for_copilot = FALSE) {
  lines <- c("## Shared Repo Skills", "")

  if (!length(skill_meta)) {
    return(c(lines, "- No repo-local shared skills are currently defined."))
  }

  entries <- vapply(
    skill_meta,
    function(meta) sprintf("- `%s` — %s", meta$name, meta$description),
    character(1)
  )

  lines <- c(lines, entries)

  if (for_copilot) {
    lines <- c(
      lines,
      "",
      "Copilot does not load `SKILL.md` files directly. Apply the matching",
      "repo-local guidance from the shared skill list when it is relevant."
    )
  }

  lines
}

render_instruction_file <- function(title, intro = character(), project, rules,
    skills) {
  c(
    sprintf("# %s", title),
    "",
    generated_note,
    intro,
    if (length(intro)) "" else character(),
    project,
    "",
    rules,
    "",
    skills,
    ""
  )
}

skill_dirs <- list.dirs(".ai/skills", recursive = FALSE, full.names = TRUE)
skill_dirs <- skill_dirs[file.exists(file.path(skill_dirs, "SKILL.md"))]
skill_meta <- lapply(file.path(skill_dirs, "SKILL.md"), parse_frontmatter)
mcp_servers <- read_source_object(".ai/mcp/servers.R", "mcp_servers")

project_context <- read_utf8(".ai/shared/project-context.md")
agent_rules <- read_utf8(".ai/shared/agent-rules.md")

claude_intro <- c(
  "Repository guidance for Claude Code. Edit the canonical sources in `.ai/`",
  "and re-run the sync script when the shared instructions change."
)

agents_intro <- c(
  "Repository guidance for Codex. Prefer the shared rules here and the",
  "`r-efficient-dev` skill when working on R code in this repo."
)

copilot_intro <- c(
  "Repository guidance for GitHub Copilot. This file mirrors the same repo-local",
  "instruction source used to generate `CLAUDE.md` and `AGENTS.md`."
)

write_utf8(
  "CLAUDE.md",
  render_instruction_file(
    "CLAUDE.md",
    intro = claude_intro,
    project = project_context,
    rules = agent_rules,
    skills = render_skill_registry(skill_meta)
  )
)

write_utf8(
  "AGENTS.md",
  render_instruction_file(
    "AGENTS.md",
    intro = agents_intro,
    project = project_context,
    rules = agent_rules,
    skills = render_skill_registry(skill_meta)
  )
)

write_utf8(
  ".github/copilot-instructions.md",
  render_instruction_file(
    "Copilot Instructions",
    intro = copilot_intro,
    project = project_context,
    rules = agent_rules,
    skills = render_skill_registry(skill_meta, for_copilot = TRUE)
  )
)

write_json(".mcp.json", build_mcp_json(mcp_servers, field_name = "mcpServers"))
write_json(
  ".vscode/mcp.json",
  build_mcp_json(mcp_servers, field_name = "servers")
)
write_json(
  ".ai/mcp/copilot-coding-agent-mcp.json",
  build_mcp_json(
    mcp_servers,
    field_name = "mcpServers",
    include_copilot_tools = TRUE
  )
)
write_utf8(".ai/mcp/codex-config.toml", render_codex_toml(mcp_servers))

for (target_root in c(".claude/skills", ".agents/skills")) {
  dir.create(target_root, recursive = TRUE, showWarnings = FALSE)

  for (skill_dir in skill_dirs) {
    skill_name <- basename(skill_dir)
    target_dir <- file.path(target_root, skill_name)
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
    file.copy(
      file.path(skill_dir, "SKILL.md"),
      file.path(target_dir, "SKILL.md"),
      overwrite = TRUE
    )
  }
}

message(
  "Synced instruction files, ",
  length(skill_dirs),
  " shared skill(s), and ",
  length(mcp_servers),
  " MCP server definition(s)."
)
