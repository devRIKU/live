---
name: test-skill
description: A test skill that provides an echo MCP tool for testing tool approval.
tools: [mcp:test:echo]
---

# Test Skill

This is a sample Agent Skill used for testing the M6 tool approval flow.

## Capabilities

- `mcp:test:echo` — echoes back a message. Used to verify that the approval dialog appears before tool execution.

## Security

This skill cannot override approval requirements. Every tool call still requires explicit user approval.