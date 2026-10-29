import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'fs';
import { join, relative, dirname, basename } from 'path';
import { createHash } from 'crypto';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const DOCS_DIR = join(ROOT, 'src', 'content', 'docs');
const MANIFEST_PATH = join(ROOT, 'social-images-manifest.json');

const HCTI_USER_ID = process.env.HCTI_USER_ID;
const HCTI_API_KEY = process.env.HCTI_API_KEY;
const HCTI_DOC_TEMPLATE_ID = process.env.HCTI_DOC_TEMPLATE_ID || 't-019dfa11-cf0f-79e2-9be2-a24c95bef027';
const HOMEPAGE_MOCKUP = join(ROOT, 'mockups', 'hcti-social-card-homepage-c.html');

const SECTION_MAP = {
  'getting-started': 'Getting Started',
  'channels': 'Channels',
  'skills': 'Skills',
  'security': 'Security',
  'configuration': 'Configuration',
  'observability': 'Observability',
  'cli': 'CLI Reference',
  'deployment': 'Deployment',
  'architecture': 'Architecture',
  'guides': 'Guides',
  'reference': 'Reference',
  'troubleshooting': 'Troubleshooting',
  'comparisons': 'Comparisons',
};

function loadManifest() {
  if (existsSync(MANIFEST_PATH)) {
    return JSON.parse(readFileSync(MANIFEST_PATH, 'utf-8'));
  }
  return { pages: {} };
}

function saveManifest(manifest) {
  writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n');
}

function parseFrontmatter(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return {};
  const fm = {};
  for (const line of match[1].split('\n')) {
    const m = line.match(/^(\w+):\s*"?([^"]*)"?\s*$/);
    if (m) fm[m[1]] = m[2];
  }
  return fm;
}

function scanDocs() {
  const pages = [];
  function walk(dir) {
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      if (statSync(full).isDirectory()) {
        walk(full);
      } else if (entry.endsWith('.md') || entry.endsWith('.mdx')) {
        const rel = relative(DOCS_DIR, full).replace(/\\/g, '/');
        const slug = rel.replace(/\.(md|mdx)$/, '').replace(/\/index$/, '');
        const content = readFileSync(full, 'utf-8');
        const fm = parseFrontmatter(content);
        if (!fm.title) return;

        const section = slug.split('/')[0];
        const tag = SECTION_MAP[section] || section;

        let description = fm.description || '';
        if (description.length > 150) {
          description = description.slice(0, 147) + '...';
        }

        pages.push({ slug, title: fm.title, description, tags: [tag] });
      }
    }
  }
  walk(DOCS_DIR);
  return pages;
}

function computeHash(templateId, title, description, tags) {
  return createHash('sha256')
    .update(`${templateId}:${title}:${description}:${tags.join(',')}`)
    .digest('hex');
}

async function generateImage(templateId, templateValues) {
  const resp = await fetch(`https://hcti.io/v1/image/${templateId}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Basic ' + Buffer.from(`${HCTI_USER_ID}:${HCTI_API_KEY}`).toString('base64'),
    },
    body: JSON.stringify({
      template_values: templateValues,
      viewport_width: 1200,
      viewport_height: 630,
    }),
  });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`HCTI API ${resp.status}: ${body}`);
  }

  const data = await resp.json();
  return data.url;
}

async function generateHomepageImage(manifest) {
  if (!existsSync(HOMEPAGE_MOCKUP)) {
    console.log('  [skip] Homepage mockup not found');
    return;
  }

  const html = readFileSync(HOMEPAGE_MOCKUP, 'utf-8');
  const hash = createHash('sha256').update(html).digest('hex');
  const existing = manifest.pages['__homepage__'];
  if (existing && existing.hash === hash) {
    console.log('  [cached] homepage');
    return;
  }

  console.log('  [generate] homepage');
  const resp = await fetch('https://hcti.io/v1/image', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Basic ' + Buffer.from(`${HCTI_USER_ID}:${HCTI_API_KEY}`).toString('base64'),
    },
    body: JSON.stringify({ html, viewport_width: 1200, viewport_height: 630 }),
  });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`HCTI API ${resp.status}: ${body}`);
  }

  const data = await resp.json();
  manifest.pages['__homepage__'] = { hash, imageUrl: data.url };
}

async function run() {
  if (!HCTI_USER_ID || !HCTI_API_KEY) {
    console.log('HCTI credentials not set — skipping social image generation.');
    process.exit(0);
  }

  if (!HCTI_DOC_TEMPLATE_ID) {
    console.log('HCTI_DOC_TEMPLATE_ID not set — skipping social image generation.');
    process.exit(0);
  }

  console.log('Generating social images...');
  const manifest = loadManifest();
  const pages = scanDocs();
  let generated = 0;
  let cached = 0;

  // Generate homepage image
  await generateHomepageImage(manifest);

  // Generate doc page images
  for (const page of pages) {
    const hash = computeHash(HCTI_DOC_TEMPLATE_ID, page.title, page.description, page.tags);
    const existing = manifest.pages[page.slug];

    if (existing && existing.hash === hash) {
      cached++;
      continue;
    }

    console.log(`  [generate] ${page.slug}`);
    try {
      const imageUrl = await generateImage(HCTI_DOC_TEMPLATE_ID, {
        title: page.title,
        description: page.description,
        tags: page.tags,
      });
      manifest.pages[page.slug] = { hash, imageUrl };
      generated++;
    } catch (err) {
      console.error(`  [error] ${page.slug}: ${err.message}`);
    }
  }

  saveManifest(manifest);
  console.log(`Done: ${generated} generated, ${cached} cached, ${pages.length} total pages.`);
}

run();
