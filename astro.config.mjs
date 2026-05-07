import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import rehypeMermaid from 'rehype-mermaid';

export default defineConfig({
  site: 'https://netclaw.dev',
  markdown: {
    rehypePlugins: [[rehypeMermaid, { strategy: 'inline-svg', dark: true }]],
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
            { label: 'Your First Conversation', slug: 'getting-started/first-conversation' },
          ],
        },
        {
          label: 'Channels',
          items: [
            { label: 'Slack', slug: 'channels/slack' },
            { label: 'Discord', slug: 'channels/discord' },
            { label: 'Troubleshooting', slug: 'channels/troubleshooting' },
          ],
        },
        {
          label: 'Skills',
          items: [
            { label: 'Overview', slug: 'skills/overview' },
            { label: 'Skill Server', slug: 'skills/skill-server' },
            { label: 'External Skills', slug: 'skills/external-skills' },
            { label: 'Skill Feeds', slug: 'skills/skill-feeds' },
          ],
        },
        {
          label: 'Security',
          items: [
            { label: 'Security Model', slug: 'security/security-model' },
            { label: 'Hardening', slug: 'security/hardening' },
            { label: 'Secrets Management', slug: 'security/secrets' },
          ],
        },
        {
          label: 'Configuration',
          items: [
            { label: 'Managed Providers', slug: 'configuration/managed-providers' },
            { label: 'Self-Hosted Providers', slug: 'configuration/self-hosted-providers' },
            { label: 'Models', slug: 'configuration/models' },
            { label: 'Search Providers', slug: 'configuration/search-providers' },
            { label: 'MCP Servers', slug: 'configuration/mcp-servers' },
            { label: 'Webhooks', slug: 'configuration/webhooks' },
            { label: 'Reminders', slug: 'configuration/reminders' },
          ],
        },
        {
          label: 'Notifications & Observability',
          items: [
            { label: 'Operational Alerts', slug: 'observability/operational-alerts' },
            { label: 'Health Checks', slug: 'observability/health-checks' },
            { label: 'OpenTelemetry', slug: 'observability/opentelemetry' },
          ],
        },
        {
          label: 'CLI Reference',
          items: [
            { label: 'Overview', slug: 'cli/overview' },
            { label: 'init', slug: 'cli/init' },
            { label: 'chat', slug: 'cli/chat' },
            { label: 'sessions', slug: 'cli/sessions' },
            { label: 'status', slug: 'cli/status' },
            { label: 'doctor', slug: 'cli/doctor' },
            { label: 'stats', slug: 'cli/stats' },
            { label: 'provider', slug: 'cli/provider' },
            { label: 'model', slug: 'cli/model' },
            { label: 'mcp-tools', slug: 'cli/mcp-tools' },
            { label: 'webhooks', slug: 'cli/webhooks' },
            { label: 'reminder', slug: 'cli/reminder' },
            { label: 'skill', slug: 'cli/skill' },
            { label: 'secrets', slug: 'cli/secrets' },
          ],
        },
        {
          label: 'Deployment',
          items: [
            { label: 'Docker', slug: 'deployment/docker' },
            { label: 'systemd', slug: 'deployment/systemd' },
            { label: 'Exposure Modes', slug: 'deployment/exposure-modes' },
          ],
        },
        {
          label: 'Architecture',
          items: [
            { label: 'Overview', slug: 'architecture/overview' },
            { label: 'Security Model', slug: 'architecture/security-model' },
          ],
        },
        {
          label: 'Guides',
          items: [
            { label: 'Connecting Slack', slug: 'guides/connecting-slack' },
            { label: 'MCP Tool Permissions', slug: 'guides/mcp-tool-permissions' },
            { label: 'Pairing Remote Devices', slug: 'guides/pairing-remote-devices' },
          ],
        },
      ],
    }),
  ],
});
