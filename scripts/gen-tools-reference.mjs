#!/usr/bin/env node
/**
 * Generates the tool tables in src/content/docs/reference/tools.md from the product source.
 *
 * Run by hand at each release, from the repo root. Do NOT wire this into
 * `npm run build`: the product repo is not available in CI.
 *
 *   node scripts/gen-tools-reference.mjs
 *   node scripts/gen-tools-reference.mjs --src /path/to/netclaw/src
 *   NETCLAW_SRC=/path/to/netclaw/src node scripts/gen-tools-reference.mjs
 *   node scripts/gen-tools-reference.mjs --check     # exit 1 if the page is stale
 *
 * What it reads from the product source (re-read these files if the script's output looks wrong):
 *   - every [NetclawTool(...)] attribute: tool name, grant category, LLM-facing description
 *   - Netclaw.Daemon/Configuration/Channel*Tools.cs: the three channel tools declared with `Name => "..."`
 *   - Register / RegisterCore / ReplaceCore calls: whether a tool is loaded up front (core) or on demand (deferred)
 *   - Netclaw.Configuration/ToolAudienceProfiles.cs: the Public and Team default allow lists,
 *     which tools are profile-managed, and the Personal profile (ToolsMode All)
 *   - Netclaw.Actors/Tools/ToolAccessPolicy.cs: shell-coupled tools and the subsystem feature gates
 *   - each tool's own source file: an `audience == TrustAudience.Public` guard that makes the tool return
 *     "This tool is not available." for Public even when the allow list would let it through
 *
 * Hand-written inputs live in scripts/tools-reference-overrides.json: the one-line summary shown for each
 * tool, the approval default and the config keys. The run fails when a tool has no summary, when an
 * override names a tool that no longer exists, or when a source assertion no longer holds.
 *
 * The script rewrites only the text between the BEGIN/END GENERATED markers in the page.
 */
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const args = process.argv.slice(2);
const arg = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const checkOnly = args.includes('--check');

const srcDir = resolve(arg('--src') ?? process.env.NETCLAW_SRC ?? join(homedir(), 'repositories/netclaw-dev/netclaw/src'));
const overridesPath = resolve(arg('--overrides') ?? join(here, 'tools-reference-overrides.json'));
const outPath = resolve(arg('--out') ?? join(root, 'src/content/docs/reference/tools.md'));

const BEGIN = '<!-- BEGIN GENERATED: tools-reference (scripts/gen-tools-reference.mjs). Do not edit by hand. -->';
const END = '<!-- END GENERATED: tools-reference -->';

const overrides = JSON.parse(readFileSync(overridesPath, 'utf8'));
const toolOverrides = overrides.tools ?? {};
const groups = overrides.groups ?? [];
const problems = [];

// ---- read the source tree -------------------------------------------------

function* walk(dir) {
  for (const entry of readdirSync(dir)) {
    if (entry === 'bin' || entry === 'obj' || entry === 'node_modules') continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      if (/Tests$/.test(entry)) continue;
      yield* walk(full);
    } else if (entry.endsWith('.cs')) {
      yield full;
    }
  }
}

const files = [...walk(srcDir)].map((path) => ({ path, rel: relative(srcDir, path), text: readFileSync(path, 'utf8') }));
const file = (rel) => {
  const f = files.find((x) => x.rel === rel);
  if (!f) {
    problems.push(`source file not found: ${rel}`);
    return { rel, text: '' };
  }
  return f;
};

/** Returns the balanced-parenthesis argument text that starts at text[open] === '('. */
function balanced(text, open) {
  let depth = 0;
  let inString = false;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (inString) {
      if (c === '\\') i++;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === '(') depth++;
    else if (c === ')') {
      depth--;
      if (depth === 0) return text.slice(open + 1, i);
    }
  }
  return '';
}

/** Splits on commas that are not inside a string or nested brackets. */
function splitArgs(text) {
  const parts = [];
  let depth = 0;
  let inString = false;
  let current = '';
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inString) {
      current += c;
      if (c === '\\') current += text[++i];
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    if ('([{'.includes(c)) depth++;
    if (')]}'.includes(c)) depth--;
    if (c === ',' && depth === 0) {
      parts.push(current.trim());
      current = '';
    } else current += c;
  }
  if (current.trim()) parts.push(current.trim());
  return parts;
}

const stringLiterals = (expr) => [...expr.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => m[1].replace(/\\"/g, '"')).join('');

// ---- tools declared with [NetclawTool] -----------------------------------

const tools = new Map(); // name -> { name, className, grant, description, source }

for (const f of files) {
  let from = 0;
  for (;;) {
    const at = f.text.indexOf('[NetclawTool(', from);
    if (at < 0) break;
    from = at + 1;
    const open = at + '[NetclawTool'.length;
    const argText = balanced(f.text, open);
    const rest = f.text.slice(open + argText.length + 2);
    const cls = /class\s+(\w+)/.exec(rest)?.[1];
    if (!cls || !argText) continue;
    const parts = splitArgs(argText);
    if (parts.length < 2) continue;
    let name;
    if (parts[0].startsWith('"')) name = stringLiterals(parts[0]);
    else {
      const constName = parts[0].trim();
      name = new RegExp(`const\\s+string\\s+${constName}\\s*=\\s*"([^"]+)"`).exec(f.text)?.[1];
    }
    if (!name || !/^[a-z_]+$/.test(name)) continue; // skips doc-comment mentions and non-tool uses
    const grant = /Grant\s*=\s*"([^"]+)"/.exec(argText)?.[1] ?? 'default';
    tools.set(name, { name, className: cls, grant, description: stringLiterals(parts[1]), source: f.rel });
  }
}

// ---- channel tools (IChannelTool implementations) -------------------------

const channelRegistration = file('Netclaw.Daemon/Configuration/ChannelToolRegistration.cs').text;
const channelToolsDeferred = /registry\.Register\(tool\)/.test(channelRegistration);
if (!channelToolsDeferred) problems.push('ChannelToolRegistration no longer calls registry.Register(tool): re-check how channel tools load');

for (const rel of ['Netclaw.Daemon/Configuration/ChannelSendTools.cs', 'Netclaw.Daemon/Configuration/ChannelLookupTools.cs']) {
  const f = file(rel);
  for (const m of f.text.matchAll(/class\s+(\w+)[^{]*?\{[\s\S]*?string Name\s*=>\s*"(\w+)";/g)) {
    tools.set(m[2], { name: m[2], className: m[1], grant: 'channel', description: '', source: rel, channel: true });
  }
}

// Channel-specific lookup tools declared with [NetclawTool] already have a grant of "default" and live in the channel projects.

// ---- loading tier ---------------------------------------------------------

const tierByClass = new Map();
for (const f of files) {
  for (const m of f.text.matchAll(/\.(RegisterCore|Register|ReplaceCore)\(\s*new\s+(\w+)\(/g)) {
    const tier = m[1] === 'Register' ? 'Deferred' : 'Core';
    if (tierByClass.get(m[2]) !== 'Core') tierByClass.set(m[2], tier);
  }
}

// ---- audience defaults ----------------------------------------------------

const profilesFile = file('Netclaw.Configuration/ToolAudienceProfiles.cs');
const catalogText = /static class ToolAudienceProfileToolCatalog[\s\S]*?static class ToolAudienceProfileDefaults/.exec(profilesFile.text)?.[0] ?? '';
const constants = new Map([...catalogText.matchAll(/public const string (\w+) = "([^"]+)";/g)].map((m) => [m[1], m[2]]));
const lists = new Map();
for (const m of catalogText.matchAll(/public static IReadOnlyList<string> (\w+) \{ get; \} =\s*\[([\s\S]*?)\];/g)) {
  const items = [];
  for (const raw of m[2].split(',').map((s) => s.trim()).filter(Boolean)) {
    if (raw.startsWith('..')) items.push(...(lists.get(raw.slice(2).trim()) ?? []));
    else if (constants.has(raw)) items.push(constants.get(raw));
    else problems.push(`unresolved catalog item ${raw} in ${m[1]}`);
  }
  lists.set(m[1], items);
}
const publicDefault = lists.get('PublicDefaultAllowedTools') ?? [];
const teamDefault = lists.get('TeamDefaultAllowedTools') ?? [];
const profileManaged = new Set(lists.get('ProfileManagedTools') ?? []);
if (!publicDefault.length || !teamDefault.length || !profileManaged.size) problems.push('could not read the audience default lists from ToolAudienceProfiles.cs');

const personalAll = /CreatePersonal\(\)[\s\S]*?ToolsMode\s*=\s*ToolProfileMode\.All/.test(profilesFile.text);
if (!personalAll) problems.push('CreatePersonal no longer sets ToolsMode = All: the Personal column is wrong');
const shellApproval = /CreateProfilesForPosture[\s\S]*?\[ToolAudienceProfileToolCatalog\.ShellExecute\]\s*=\s*ToolApprovalMode\.Approval/.test(profilesFile.text);
if (!shellApproval) problems.push('the Personal posture no longer defaults shell_execute to Approval: re-check the approval column');

const policy = file('Netclaw.Actors/Tools/ToolAccessPolicy.cs').text;
const shellCoupled = /IsShellCoupledTool\(INetclawTool tool\)\s*=>\s*IsShellTool\(tool\)\s*\|\|\s*string\.Equals\(tool\.Name, CheckBackgroundJobTool\.ToolName/.test(policy);
if (!shellCoupled) problems.push('IsShellCoupledTool changed: re-check which tools need shell execution');
const shellCoupledTools = ['shell_execute', 'check_background_job'];

const gateConfig = {
  MemoryEnabled: 'Memory.Enabled',
  SearchEnabled: 'Search.Enabled',
  SkillSyncEnabled: 'SkillSync.Enabled',
  SubAgentsEnabled: 'SubAgents.Enabled',
  SchedulingEnabled: 'Scheduling.Enabled',
};
const gateByTool = new Map();
const gateBlock = /IsFeatureDisabledTool\(string toolName\)[\s\S]*?\n    \}/.exec(policy)?.[0] ?? '';
for (const m of gateBlock.matchAll(/((?:"\w+"\s*(?:or\s*)?)+)\s*=>\s*!_featureGates\.(\w+)/g)) {
  for (const t of m[1].matchAll(/"(\w+)"/g)) gateByTool.set(t[1], gateConfig[m[2]] ?? m[2]);
}
if (!gateByTool.size) problems.push('could not read the feature gates from ToolAccessPolicy.IsFeatureDisabledTool');

// ---- compute rows ---------------------------------------------------------

// Tools whose own code refuses Public regardless of the allow lists.
const publicGuard = /^[^/\n]*(?:audience|Audience)\s*==\s*TrustAudience\.Public/m;
const publicBlocked = new Set([...tools.values()].filter((t) => publicGuard.test(files.find((f) => f.rel === t.source)?.text ?? '')).map((t) => t.name));
for (const name of Object.keys(toolOverrides)) {
  if (toolOverrides[name].publicBlocked && !publicBlocked.has(name)) problems.push(`override says ${name} is blocked for Public but the source has no guard`);
}
for (const name of publicBlocked) {
  if (!toolOverrides[name]?.publicBlocked) problems.push(`source blocks ${name} for Public: add "publicBlocked": true to its override`);
}

function availability(tool) {
  const n = tool.name;
  if (publicBlocked.has(n)) {
    return { Public: 'No', Team: profileManaged.has(n) && !teamDefault.includes(n) ? 'No' : 'Yes', Personal: 'Yes', profileManaged: profileManaged.has(n) };
  }
  if (!profileManaged.has(n)) return { Public: 'Yes', Team: 'Yes', Personal: 'Yes', profileManaged: false };
  const inPublic = publicDefault.includes(n);
  const inTeam = teamDefault.includes(n);
  return {
    Public: inPublic ? 'Yes' : 'No',
    Team: inTeam ? 'Yes' : 'No',
    Personal: 'Yes',
    profileManaged: true,
  };
}

const rows = [...tools.values()].map((t) => {
  const ov = toolOverrides[t.name];
  if (!ov) problems.push(`no override (summary, group) for tool: ${t.name}`);
  const a = availability(t);
  const requires = [];
  if (shellCoupledTools.includes(t.name)) requires.push('`Tools.ShellMode` or `Security.ShellExecutionMode`, which must resolve to `HostAllowed`');
  if (gateByTool.has(t.name)) requires.push(`\`${gateByTool.get(t.name)}\``);
  if (ov?.requires) requires.push(...ov.requires);
  const tier = (t.channel || t.source.startsWith('Netclaw.Channels.')) ? 'Deferred' : (tierByClass.get(t.className) ?? 'Deferred');
  if (!t.channel && !t.source.startsWith('Netclaw.Channels.') && !tierByClass.has(t.className)) problems.push(`no Register call found for ${t.className}: loading tier assumed Deferred`);
  const shell = shellCoupledTools.includes(t.name);
  return {
    ...t,
    ...a,
    Public: shell ? 'No' : a.Public,
    Team: shell ? 'No' : a.Team,
    tier,
    requires,
    summary: ov?.summary,
    group: ov?.group,
    approval: ov?.approval ?? 'Runs without a prompt',
    config: ov?.config ?? [],
  };
});

for (const name of Object.keys(toolOverrides)) {
  if (!tools.has(name)) problems.push(`override names a tool that is not in the source: ${name}`);
}
for (const g of groups) {
  if (!rows.some((r) => r.group === g.id)) problems.push(`group with no tools: ${g.id}`);
}
for (const r of rows) {
  if (r.group && !groups.some((g) => g.id === r.group)) problems.push(`unknown group ${r.group} for ${r.name}`);
}

// ---- render ---------------------------------------------------------------

const cell = (s) => String(s).replace(/(?<!\\)\|/g, '\\|');
const out = [];

const count = rows.length;
const coreCount = rows.filter((r) => r.tier === 'Core').length;
out.push(`netclaw 0.27.1 registers ${count} built-in tools. ${coreCount} are loaded into every prompt (core) and the rest are found with \`search_tools\` and loaded with \`load_tool\` (deferred). The table columns say which audiences get each tool by default. A tool outside the profile-managed set is available to every audience when its subsystem is enabled, except that Public never gets ${[...publicBlocked].sort().map((t) => `\`${t}\``).join(', ').replace(/, ([^,]*)$/, ' or $1')}: those tools refuse Public in their own code.`.replace('0.27.1', overrides.version ?? '0.27.1'));
out.push('');

for (const g of groups) {
  const list = rows.filter((r) => r.group === g.id).sort((x, y) => (toolOverrides[x.name]?.order ?? 0) - (toolOverrides[y.name]?.order ?? 0) || x.name.localeCompare(y.name));
  if (!list.length) continue;
  out.push(`### ${g.title}`);
  out.push('');
  if (g.intro) {
    out.push(g.intro);
    out.push('');
  }
  out.push('| Tool | What it does | Loaded | Public | Team | Personal | Approval by default | Controlled by |');
  out.push('|------|--------------|--------|--------|------|----------|---------------------|---------------|');
  for (const r of list) {
    const needs = [...r.requires, ...r.config.map((c) => `\`${c}\``)];
    out.push(`| \`${r.name}\` | ${cell(r.summary ?? '')} | ${r.tier} | ${r.Public} | ${r.Team} | ${r.Personal} | ${cell(r.approval)} | ${cell(needs.length ? needs.join(', ') : '-')} |`);
  }
  out.push('');
}

out.push('### Default allow lists');
out.push('');
out.push('The lists below are the 0.27.1 defaults for `Tools.AudienceProfiles.<audience>.AllowedTools`. Personal uses `ToolsMode: All` and has no list.'.replace('0.27.1', overrides.version ?? '0.27.1'));
out.push('');
out.push('| Audience | Default `AllowedTools` |');
out.push('|----------|------------------------|');
out.push(`| Public | ${publicDefault.map((t) => `\`${t}\``).join(', ')} |`);
out.push(`| Team | ${teamDefault.map((t) => `\`${t}\``).join(', ')} |`);
out.push('');

const generated = out.join('\n');

// ---- write ----------------------------------------------------------------

const page = readFileSync(outPath, 'utf8');
const start = page.indexOf(BEGIN);
const end = page.indexOf(END);
if (start < 0 || end < 0 || end < start) {
  console.error(`Markers not found in ${outPath}. Expected:\n${BEGIN}\n${END}`);
  process.exit(2);
}
const next = page.slice(0, start + BEGIN.length) + '\n\n' + generated + '\n' + page.slice(end);

if (problems.length) console.error('Tools reference problems:\n  ' + problems.join('\n  '));

if (checkOnly) {
  if (next !== page) {
    console.error(`${outPath} is stale. Run: node scripts/gen-tools-reference.mjs`);
    process.exit(1);
  }
} else if (next !== page) {
  writeFileSync(outPath, next);
  console.log(`Wrote ${outPath}`);
} else {
  console.log(`${outPath} already up to date`);
}
console.log(`${count} tools (${coreCount} core), public default ${publicDefault.length}, team default ${teamDefault.length}`);
if (problems.length) process.exit(1);
