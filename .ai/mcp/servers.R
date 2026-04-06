mcp_servers <- list(
  openaiDeveloperDocs = list(
    type = "http",
    url = "https://developers.openai.com/mcp",
    description = paste(
      "Official OpenAI developer documentation MCP server.",
      "Use it for authoritative OpenAI API, model, and Codex docs."
    ),
    copilot_tools = "*"
  )
)
