#!/usr/bin/env node
// A tiny OpenAI-compatible endpoint that answers every first turn with one scripted
// shell_execute tool call, so the approval prompt shows up without a real model.
// Runs in the Playwright image (approval.sh). After the tool result it replies "Done."
//
// Env: PORT (8080), SCRIPTED_TOOL (mcp|shell, default mcp), SCRIPTED_COMMAND (shell command),
//      SCRIPTED_MCP_URL (URL the MCP call fetches)
import { createServer } from 'http';

const COMMAND = process.env.SCRIPTED_COMMAND || 'git push origin main';
const KIND = process.env.SCRIPTED_TOOL || 'mcp';
const MCP_URL = process.env.SCRIPTED_MCP_URL || 'https://status.example.com/api/v1/incidents';
const PORT = Number(process.env.PORT || 8080);
const id = () => 'chatcmpl-' + Math.random().toString(36).slice(2, 10);

function completion(body) {
  const tools = body.tools || [];
  const shell = KIND === 'shell' && tools.find(t => (t.function?.name || t.name) === 'shell_execute');
  const mcp = KIND === 'mcp' && tools.find(t => /http_fetch/.test(t.function?.name || t.name || ''));
  const answered = (body.messages || []).some(m => m.role === 'tool');
  const calledMcp = (body.messages || []).some(m => (m.tool_calls || []).some(c => /http_fetch/.test(c.function?.name || '')));
  const loader = KIND === 'mcp' && !mcp && !answered && tools.find(t => (t.function?.name || t.name) === 'load_tool');
  if (loader) {
    // MCP tools are deferred: the first turn loads the tool, the next one calls it.
    return { message: { role: 'assistant', content: null, tool_calls: [{ id: 'call_ap0', type: 'function', function: { name: 'load_tool', arguments: JSON.stringify({ name: 'demo-utilities/http_fetch', _rationale: 'Load the HTTP fetch tool.' }) } }] }, finish: 'tool_calls' };
  }
  if (mcp && !calledMcp) {
    const name = mcp.function?.name || mcp.name;
    return { message: { role: 'assistant', content: null, tool_calls: [{ id: 'call_ap1', type: 'function', function: { name, arguments: JSON.stringify({ url: MCP_URL, method: 'POST', _rationale: 'Open a status page incident for the website deploy.' }) } }] }, finish: 'tool_calls' };
  }
  if (shell && !answered) {
    return { message: { role: 'assistant', content: null, tool_calls: [{ id: 'call_ap1', type: 'function', function: { name: 'shell_execute', arguments: JSON.stringify({ command: COMMAND, _rationale: 'Push the pending website changes to origin.' }) } }] }, finish: 'tool_calls' };
  }
  return { message: { role: 'assistant', content: 'Done.' }, finish: 'stop' };
}

createServer((req, res) => {
  let raw = '';
  req.on('data', c => (raw += c));
  req.on('end', () => {
    if (req.method === 'GET') { res.setHeader('Content-Type', 'application/json'); return res.end(JSON.stringify({ object: 'list', data: [{ id: 'demo-model', object: 'model' }] })); }
    let body = {};
    try { body = JSON.parse(raw || '{}'); } catch {}
    const { message, finish } = completion(body);
    console.log(`${req.method} ${req.url} stream=${!!body.stream} -> ${finish}`);
    const base = { id: id(), object: 'chat.completion', created: Math.floor(Date.now() / 1000), model: 'demo-model' };
    if (body.stream) {
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      const delta = { ...message };
      if (delta.tool_calls) delta.tool_calls = delta.tool_calls.map((t, index) => ({ index, ...t }));
      res.write(`data: ${JSON.stringify({ ...base, object: 'chat.completion.chunk', choices: [{ index: 0, delta, finish_reason: null }] })}\n\n`);
      res.write(`data: ${JSON.stringify({ ...base, object: 'chat.completion.chunk', choices: [{ index: 0, delta: {}, finish_reason: finish }], usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 } })}\n\n`);
      res.end('data: [DONE]\n\n');
    } else {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ ...base, choices: [{ index: 0, message, finish_reason: finish }], usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 } }));
    }
  });
}).listen(PORT, () => console.log(`scripted llm on :${PORT}`));
