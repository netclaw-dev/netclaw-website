# Playwright runner for browser captures (Mattermost flow, docs page screenshots).
# Based on Microsoft's Playwright image so Chromium and its OS deps are preinstalled;
# the version is the one locked in package-lock.json (see screenshots/lib.sh), so the
# `playwright` module and the bundled browsers always match.
#
# The module is installed at /node_modules so scripts mounted anywhere under / resolve
# `import ... from 'playwright'` (ESM ignores NODE_PATH).
ARG PLAYWRIGHT_VERSION
FROM mcr.microsoft.com/playwright:v${PLAYWRIGHT_VERSION}-noble
ARG PLAYWRIGHT_VERSION
RUN mkdir /opt/pw && cd /opt/pw \
 && npm install --no-save --no-audit --no-fund --ignore-scripts playwright@${PLAYWRIGHT_VERSION} \
 && ln -s /opt/pw/node_modules /node_modules \
 && node -e "console.log('playwright', require('playwright/package.json').version)"
ENV HOME=/tmp
WORKDIR /work
