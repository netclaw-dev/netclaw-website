import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import rehypeMermaid from 'rehype-mermaid';

export default defineConfig({
  site: 'https://netclaw.dev',
  // Mirrored in public/_redirects (301 on Cloudflare Pages). These also work in `astro preview`.
  redirects: {
    '/guides/custom-subagents': '/skills/custom-subagents/',
    '/guides/connecting-slack': '/channels/slack/',
  },
  markdown: {
    rehypePlugins: [[rehypeMermaid, { strategy: 'inline-svg', dark: true, mermaidConfig: { htmlLabels: false, flowchart: { htmlLabels: false, wrappingWidth: 280 } } }]],
  },
  vite: {
    server: {
      allowedHosts: ['.ts.net'],
    },
  },
  integrations: [
    starlight({
      title: 'netclaw',
      logo: {
        src: './src/assets/netclaw-icon-purple.svg',
      },
      favicon: '/assets/favicons/favicon.ico',
      components: {
        ThemeSelect: './src/components/ThemeSelect.astro',
        Header: './src/components/Header.astro',
        Footer: './src/components/Footer.astro',
      },
      head: [
        { tag: 'script', attrs: { async: true, src: 'https://www.googletagmanager.com/gtag/js?id=G-NY61NRBJ68' } },
        { tag: 'script', content: "window.dataLayer = window.dataLayer || [];function gtag(){dataLayer.push(arguments);}gtag('js', new Date());gtag('config', 'G-NY61NRBJ68');" },
        { tag: 'link', attrs: { rel: 'preconnect', href: 'https://fonts.googleapis.com' } },
        { tag: 'link', attrs: { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: true } },
        { tag: 'link', attrs: { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;700&family=JetBrains+Mono:wght@400;500&display=swap' } },
      ],
      routeMiddleware: ['./src/route-data-social-images.ts'],
      customCss: [
        './src/styles/custom.css',
      ],
      sidebar: [
        {
          label: 'Getting Started',
          items: [
            { label: 'Installation', slug: 'getting-started/installation' },
            { label: 'Quickstart', slug: 'getting-started/quickstart' },
            { label: 'Your first conversation', slug: 'getting-started/first-conversation' },
            { label: 'Build your first assistant', slug: 'getting-started/first-assistant' },
          ],
        },
        {
          label: 'Guides',
          items: [
            { label: 'Reduce or turn off approval prompts', slug: 'guides/reduce-approval-prompts' },
            { label: 'Run unattended', slug: 'guides/unattended-runs' },
            { label: 'Connect an OAuth MCP server', slug: 'guides/oauth-mcp-servers' },
            { label: 'Run netclaw with Mattermost on Docker Compose', slug: 'guides/mattermost-docker-compose' },
            { label: 'Upgrade netclaw', slug: 'guides/upgrading' },
            { label: 'Back up, restore and move netclaw', slug: 'guides/backup-and-restore' },
            { label: 'Use the CLI from another machine', slug: 'guides/pairing-remote-devices' },
            { label: 'MCP tool permissions', slug: 'guides/mcp-tool-permissions' },
            { label: 'Scripting headless sessions', slug: 'guides/scripting-sessions' },
            { label: 'Images, audio and other file types', slug: 'guides/multimodal-files' },
            { label: 'Migrating model configuration', slug: 'guides/migrating-model-config' },
          ],
        },
        {
          label: 'Channels',
          items: [
            { label: 'Slack', slug: 'channels/slack' },
            { label: 'Discord', slug: 'channels/discord' },
            { label: 'Mattermost', slug: 'channels/mattermost' },
            { label: 'Troubleshooting', slug: 'channels/troubleshooting' },
          ],
        },
        {
          label: 'Skills & Agents',
          items: [
            { label: 'Overview', slug: 'skills/overview' },
            { label: 'Native manifest & sync', slug: 'skills/native-manifest' },
            { label: 'Bundling resources with skills', slug: 'skills/bundled-resources' },
            { label: 'Custom subagents', slug: 'skills/custom-subagents' },
            { label: 'Skill feeds', slug: 'skills/skill-feeds' },
            { label: 'External skills', slug: 'skills/external-skills' },
            { label: 'Skill server', slug: 'skills/skill-server' },
            { label: 'skillserver CLI', slug: 'skills/skillserver-cli' },
            { label: 'Distributing subagents', slug: 'skills/distributing-subagents' },
          ],
        },
        {
          label: 'Configuration',
          items: [
            { label: 'Managed providers', slug: 'configuration/managed-providers' },
            { label: 'Self-hosted providers', slug: 'configuration/self-hosted-providers' },
            { label: 'Models', slug: 'configuration/models' },
            { label: 'Memory and embeddings', slug: 'configuration/memory' },
            { label: 'Search providers', slug: 'configuration/search-providers' },
            { label: 'MCP servers', slug: 'configuration/mcp-servers' },
            { label: 'Webhooks', slug: 'configuration/webhooks' },
            { label: 'Reminders', slug: 'configuration/reminders' },
            { label: 'Data retention', slug: 'configuration/data-retention' },
            { label: 'Configuration reference', slug: 'configuration/reference' },
          ],
        },
        {
          label: 'Security',
          items: [
            { label: 'Security model', slug: 'security/security-model' },
            { label: 'How tool approvals work', slug: 'security/approvals' },
            { label: 'Hardening', slug: 'security/hardening' },
            { label: 'Secrets management', slug: 'security/secrets' },
          ],
        },
        {
          label: 'Deployment',
          items: [
            { label: 'Docker', slug: 'deployment/docker' },
            { label: 'systemd', slug: 'deployment/systemd' },
            { label: 'Exposure modes', slug: 'deployment/exposure-modes' },
          ],
        },
        {
          label: 'Notifications & Observability',
          items: [
            { label: 'Operational alerts', slug: 'observability/operational-alerts' },
            { label: 'Health checks', slug: 'observability/health-checks' },
            { label: 'OpenTelemetry', slug: 'observability/opentelemetry' },
          ],
        },
        {
          label: 'CLI Reference',
          items: [
            { label: 'Overview', slug: 'cli/overview' },
            { label: 'init', slug: 'cli/init' },
            { label: 'config', slug: 'cli/config' },
            { label: 'chat', slug: 'cli/chat' },
            { label: 'sessions', slug: 'cli/sessions' },
            { label: 'status', slug: 'cli/status' },
            { label: 'doctor', slug: 'cli/doctor' },
            { label: 'stats', slug: 'cli/stats' },
            { label: 'daemon', slug: 'cli/daemon' },
            { label: 'update', slug: 'cli/update' },
            { label: 'provider', slug: 'cli/provider' },
            { label: 'model', slug: 'cli/model' },
            { label: 'memory', slug: 'cli/memory' },
            { label: 'mcp', slug: 'cli/mcp-tools' },
            { label: 'webhooks', slug: 'cli/webhooks' },
            { label: 'reminder', slug: 'cli/reminder' },
            { label: 'skill', slug: 'cli/skill' },
            { label: 'secrets', slug: 'cli/secrets' },
            { label: 'approvals', slug: 'cli/approvals' },
          ],
        },
        {
          label: 'Reference',
          items: [
            { label: 'Slash commands', slug: 'reference/slash-commands' },
            { label: 'Built-in tools', slug: 'reference/tools' },
            { label: 'Data directory layout', slug: 'reference/data-directory' },
            { label: 'Glossary', slug: 'reference/glossary' },
          ],
        },
        {
          label: 'Architecture & Philosophy',
          items: [
            { label: 'Design philosophy', slug: 'architecture/design-philosophy' },
            { label: 'Overview', slug: 'architecture/overview' },
            { label: 'Sessions & input model', slug: 'architecture/sessions' },
            { label: 'Context structure', slug: 'architecture/context-structure' },
            { label: 'Memory model', slug: 'architecture/memory-model' },
            { label: 'Security model', slug: 'architecture/security-model' },
          ],
        },
        {
          label: 'Troubleshooting',
          items: [
            { label: 'Troubleshooting by symptom', slug: 'troubleshooting/common-problems' },
            { label: 'FAQ', slug: 'troubleshooting/faq' },
            { label: 'llama.cpp', slug: 'troubleshooting/llama-cpp' },
            { label: 'vLLM', slug: 'troubleshooting/vllm' },
          ],
        },
        {
          label: 'Comparisons',
          items: [
            { label: 'vs. OpenClaw', slug: 'comparisons/openclaw' },
            { label: 'vs. Hermes Agent', slug: 'comparisons/hermes-agent' },
          ],
        },
        { label: 'Changelog', link: '/changelog' },
      ],
    }),
  ],
});
