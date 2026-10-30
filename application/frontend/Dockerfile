FROM node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS test
WORKDIR /app
COPY package*.json ./
RUN npm ci --ignore-scripts
COPY src ./src
COPY public ./public
COPY tests ./tests
RUN npm test

FROM node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS runtime
WORKDIR /app
COPY --from=test --chown=10001:10001 /app/package.json ./
COPY --from=test --chown=10001:10001 /app/src ./src
COPY --from=test --chown=10001:10001 /app/public ./public
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
USER 10001:10001
EXPOSE 8080
CMD ["node", "src/server.js"]
