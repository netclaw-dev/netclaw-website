#!/usr/bin/env node
/**
 * Generates the option tables in src/content/docs/configuration/reference.md
 * from the netclaw JSON schema, plus a hand-maintained overrides file.
 *
 * Run by hand at each release, from the repo root. Do NOT wire this into
 * `npm run build`: the product repo is not available in CI.
 *
 *   node scripts/gen-config-reference.mjs
 *   node scripts/gen-config-reference.mjs --schema /path/to/netclaw-config.v1.schema.json
 *   NETCLAW_SCHEMA=/path/to/schema.json node scripts/gen-config-reference.mjs
 *   node scripts/gen-config-reference.mjs --check     # exit 1 if the page is stale
 *
 * Inputs
 *   --schema    JSON schema (default: $NETCLAW_SCHEMA, then the product clone at
 *               ~/repositories/netclaw-dev/netclaw/src/Netclaw.Configuration/Schemas/)
 *   --overrides scripts/config-reference-overrides.json (default). Defaults,
 *               descriptions and keys that the schema lacks, each with the C# file
 *               it came from. Re-verify these against the options classes at each release.
 *   --out       the page (default src/content/docs/configuration/reference.md)
 *
 * The script rewrites only the text between the BEGIN/END GENERATED markers in the
 * page. Everything else in the page is hand-written. It exits non-zero when a key
 * in the schema still has no default or no description after overrides are applied,
 * or when an override names a key that no longer exists, so a new release can't
 * silently ship an empty cell.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');

const args = process.argv.slice(2);
const arg = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const checkOnly = args.includes('--check');

const defaultSchema = join(
  homedir(),
  'repositories/netclaw-dev/netclaw/src/Netclaw.Configuration/Schemas/netclaw-config.v1.schema.json',
);
const schemaPath = resolve(arg('--schema') ?? process.env.NETCLAW_SCHEMA ?? defaultSchema);
const overridesPath = resolve(arg('--overrides') ?? join(here, 'config-reference-overrides.json'));
const outPath = resolve(arg('--out') ?? join(root, 'src/content/docs/configuration/reference.md'));

const BEGIN = '<!-- BEGIN GENERATED: config-reference (scripts/gen-config-reference.mjs). Do not edit by hand. -->';
const END = '<!-- END GENERATED: config-reference -->';

const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));
const overrides = JSON.parse(readFileSync(overridesPath, 'utf8'));
const keyOverrides = { ...(overrides.keys ?? {}) };
for (const prefix of overrides.shared?.prefixes ?? []) {
  for (const [key, spec] of Object.entries(overrides.shared?.keys ?? {})) {
    const path = `${prefix}.${key}`;
    if (!(path in keyOverrides)) keyOverrides[path] = spec;
  }
}
const extraKeys = overrides.extra ?? {};
const sectionMeta = overrides.sections ?? {};
const mapKeyNames = overrides.mapKeyNames ?? {};
const skipKeys = new Set(overrides.skip ?? []);

const problems = [];
const usedOverrides = new Set();

// ---- schema helpers -------------------------------------------------------

function deref(node) {
  while (node && typeof node === 'object' && node.$ref) {
    const parts = node.$ref.replace(/^#\//, '').split('/');
    let target = schema;
    for (const p of parts) target = target[p];
    const { $ref, ...rest } = node;
    node = { ...target, ...rest };
  }
  return node;
}

/** Collapse anyOf [X, null] and a multi-type with null into X plus nullable. */
function normalize(node) {
  node = deref(node);
  if (node === false) return { forbidden: true };
  if (node === true || node === undefined) return { type: 'any' };
  let nullable = false;
  if (Array.isArray(node.anyOf)) {
    const nonNull = node.anyOf.filter((n) => !(n.type === 'null'));
    nullable = nonNull.length !== node.anyOf.length;
    if (nonNull.length === 1) {
      const { anyOf, ...rest } = node;
      node = { ...deref(nonNull[0]), ...rest };
    }
  }
  if (Array.isArray(node.oneOf)) {
    // Models: legacy inline roles or named Definitions/Roles. Document the named shape.
    const named = node.oneOf.map(deref).find((n) => n.properties && n.properties.Definitions);
    if (named) {
      const { oneOf, ...rest } = node;
      node = { ...named, ...rest };
    }
  }
  if (Array.isArray(node.type)) {
    nullable = nullable || node.type.includes('null');
    const types = node.type.filter((t) => t !== 'null');
    node = { ...node, type: types.length === 1 ? types[0] : types };
  }
  return { ...node, nullable };
}

function typeLabel(node) {
  const n = normalize(node);
  if (n.type === 'array') {
    const item = normalize(n.items ?? {});
    const inner = item.type === 'object' ? 'object' : (item.enum ? 'string' : (item.type ?? 'any'));
    return `array of ${inner}` + (n.nullable ? ' (nullable)' : '');
  }
  if (n.type === 'object' && n.additionalProperties && typeof n.additionalProperties === 'object' && !n.properties) {
    const v = normalize(n.additionalProperties);
    return `map of ${v.type === 'object' ? 'object' : (v.type ?? 'any')}` + (n.nullable ? ' (nullable)' : '');
  }
  const t = Array.isArray(n.type) ? n.type.join(' or ') : (n.type ?? 'any');
  return t + (n.nullable ? ' (nullable)' : '');
}

const code = (s) => '`' + String(s).replace(/\|/g, '\\|') + '`';
// Escape pipes that code() has not already escaped, and keep em dashes out of the page.
const cell = (s) => String(s ?? '-').replace(/\r?\n/g, ' ').replace(/(?<!\\)\|/g, '\\|').replace(/\s*\u2014\s*/g, ': ');

function renderDefault(value) {
  if (value === undefined) return undefined;
  if (typeof value === 'string') return code(JSON.stringify(value));
  return code(JSON.stringify(value));
}

function allowed(node) {
  const n = normalize(node);
  const parts = [];
  if (n.enum) parts.push(n.enum.filter((v) => v !== null).map((v) => code(v)).join(', '));
  else if (n.type === 'array') {
    const item = normalize(n.items ?? {});
    if (item.enum) parts.push('items: ' + item.enum.map((v) => code(v)).join(', '));
  } else if (n.type === 'object' && n.additionalProperties && typeof n.additionalProperties === 'object') {
    const v = normalize(n.additionalProperties);
    if (v.enum) parts.push('values: ' + v.enum.map((x) => code(x)).join(', '));
  }
  if (n.minimum !== undefined && n.maximum !== undefined) parts.push(`${n.minimum} to ${n.maximum}`);
  else if (n.minimum !== undefined) parts.push(`${n.minimum} or more`);
  else if (n.maximum !== undefined) parts.push(`${n.maximum} or less`);
  if (n.pattern) parts.push('pattern ' + code(n.pattern));
  return parts.length ? parts.join('; ') : '-';
}

// ---- flattening -----------------------------------------------------------

const AUDIENCES = ['Public', 'Team', 'Personal'];
const rows = []; // { section, path, type, def, allowed, desc, secret }

function mapKeyName(path) {
  return mapKeyNames[path] ?? 'key';
}

function pushRow(section, path, node, extra = {}) {
  const ov = keyOverrides[path];
  if (ov) usedOverrides.add(path);
  const n = normalize(node);
  const schemaDefault = n.default !== undefined ? renderDefault(n.default) : undefined;
  let def = ov?.default ?? schemaDefault;
  if (def === undefined && n.nullable) def = 'unset';
  const desc = ov?.description ?? n.description;
  const row = {
    section,
    path,
    type: ov?.type ?? typeLabel(node),
    def,
    allowed: ov?.allowed ?? allowed(node),
    desc,
    ...extra,
  };
  if (def === undefined) problems.push(`no default: ${path}`);
  if (!desc) problems.push(`no description: ${path}`);
  rows.push(row);
}

function visit(section, path, node, isRoot = false) {
  const n = normalize(node);
  if (n.forbidden) return;
  if (skipKeys.has(path)) return;

  if (n.type === 'object' && n.properties) {
    if (!isRoot && (n.description || keyOverrides[path])) {
      // A container with its own description gets a row so the section reads completely.
      pushContainer(section, path, n);
    }
    const props = Object.entries(n.properties);
    const audienceProps = props.filter(([k]) => AUDIENCES.includes(k));
    const sameShape =
      audienceProps.length === 3 &&
      new Set(audienceProps.map(([, v]) => v.$ref)).size === 1 &&
      audienceProps[0][1].$ref;
    let emittedAudience = false;
    for (const [key, child] of props) {
      if (sameShape && AUDIENCES.includes(key)) {
        if (!emittedAudience) {
          emittedAudience = true;
          visit(section, `${path}.<audience>`, child);
        }
        continue;
      }
      visit(section, `${path}.${key}`, child);
    }
    return;
  }

  if (n.type === 'object' && n.additionalProperties && typeof n.additionalProperties === 'object') {
    const v = normalize(n.additionalProperties);
    if (v.type === 'object' && v.properties) {
      if (keyOverrides[path]) pushContainer(section, path, { ...n, type: 'object' });
      pushContainer(section, `${path}.<${mapKeyName(path)}>`, { ...v, description: keyOverrides[`${path}.<${mapKeyName(path)}>`]?.description ?? v.description ?? n.description, type: 'object' });
      for (const [key, child] of Object.entries(v.properties)) {
        visit(section, `${path}.<${mapKeyName(path)}>.${key}`, child);
      }
      return;
    }
    pushRow(section, path, node);
    return;
  }

  if (n.type === 'array') {
    const item = normalize(n.items ?? {});
    if (item.type === 'object' && item.properties) {
      pushRow(section, path, node);
      for (const [key, child] of Object.entries(item.properties)) {
        visit(section, `${path}[].${key}`, child);
      }
      return;
    }
  }

  pushRow(section, path, node);
}

function pushContainer(section, path, n) {
  const ov = keyOverrides[path];
  if (ov) usedOverrides.add(path);
  const desc = ov?.description ?? n.description;
  if (!desc) problems.push(`no description: ${path}`);
  rows.push({
    section,
    path,
    type: ov?.type ?? 'object',
    def: ov?.default ?? '-',
    allowed: '-',
    desc,
  });
}

// ---- walk the schema ------------------------------------------------------

const sectionNames = Object.keys(schema.properties).filter((k) => k !== 'configVersion');
const forbiddenSections = [];

for (const name of sectionNames) {
  const node = schema.properties[name];
  if (node === false) {
    forbiddenSections.push(name);
    continue;
  }
  visit(name, name, node, true);
}

// Keys the schema doesn't carry (secrets, provider entries, keys the daemon reads that the schema omits).
for (const [path, spec] of Object.entries(extraKeys)) {
  const section = path.split('.')[0];
  if (!sectionNames.includes(section)) {
    problems.push(`extra key in unknown section: ${path}`);
    continue;
  }
  rows.push({
    section,
    path,
    type: spec.type,
    def: spec.default ?? 'unset',
    allowed: spec.allowed ?? '-',
    desc: spec.description,
    after: spec.after,
  });
  if (!spec.description || !spec.type) problems.push(`incomplete extra key: ${path}`);
}

for (const path of Object.keys(keyOverrides)) {
  if (!usedOverrides.has(path)) problems.push(`override names a key that is not in the schema: ${path}`);
}
for (const name of sectionNames) {
  if (!forbiddenSections.includes(name) && !sectionMeta[name]) problems.push(`no section summary: ${name}`);
}

// ---- render ---------------------------------------------------------------

function renderRows(list) {
  const out = [];
  out.push('| Key | Type | Default | Allowed values | Description |');
  out.push('|-----|------|---------|----------------|-------------|');
  for (const r of list) {
    out.push(`| ${code(r.path)} | ${cell(r.type)} | ${r.def === undefined ? '-' : cell(r.def)} | ${cell(r.allowed)} | ${cell(r.desc)} |`);
  }
  return out.join('\n');
}

/** Order rows so an extra key with `after` lands right behind the key it names. */
function orderRows(list) {
  const base = list.filter((r) => !r.after);
  for (const r of list.filter((x) => x.after)) {
    const idx = base.findIndex((b) => b.path === r.after);
    if (idx < 0) base.push(r);
    else base.splice(idx + 1, 0, r);
  }
  return base;
}

const out = [];
for (const name of sectionNames) {
  if (forbiddenSections.includes(name)) continue;
  const meta = sectionMeta[name] ?? {};
  const list = orderRows(rows.filter((r) => r.section === name));
  out.push(`### ${name}`);
  out.push('');
  if (meta.summary) {
    out.push(meta.summary);
    out.push('');
  }
  if (list.length) {
    out.push(renderRows(list));
    out.push('');
  }
  if (meta.notes) {
    out.push(meta.notes);
    out.push('');
  }
}

const generated = out.join('\n').replace(/\n+$/, '\n');

// ---- write ----------------------------------------------------------------

const page = readFileSync(outPath, 'utf8');
const start = page.indexOf(BEGIN);
const end = page.indexOf(END);
if (start < 0 || end < 0 || end < start) {
  console.error(`Markers not found in ${outPath}. Expected:\n${BEGIN}\n${END}`);
  process.exit(2);
}
const next = page.slice(0, start + BEGIN.length) + '\n\n' + generated + '\n' + page.slice(end);

if (problems.length) {
  console.error('Config reference problems:\n  ' + problems.join('\n  '));
}

if (checkOnly) {
  if (next !== page) {
    console.error(`${outPath} is stale. Run: node scripts/gen-config-reference.mjs`);
    process.exit(1);
  }
} else if (next !== page) {
  writeFileSync(outPath, next);
  console.log(`Wrote ${outPath}`);
} else {
  console.log(`${outPath} already up to date`);
}
console.log(`${sectionNames.length} sections, ${rows.length} rows, ${forbiddenSections.length} forbidden section(s): ${forbiddenSections.join(', ') || 'none'}`);
if (problems.length) process.exit(1);
