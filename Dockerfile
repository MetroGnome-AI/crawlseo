FROM node:20-alpine AS base

FROM base AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# Prisma generate needs a syntactically valid DATABASE_URL but never connects.
# Inline it so it does not persist as an image layer.
RUN DATABASE_URL="postgresql://build:build@localhost/build" npx prisma generate
RUN npm run build

FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
# local: upstream copies a subset of the Prisma CLI's packages into the runner,
# which misses transitive deps (@prisma/debug, @prisma/config's deps, the CLI's
# sibling WASM) and crashes `migrate deploy` at boot. Install the pinned CLI
# into the runner at build time instead — no runtime network, complete tree.
RUN npm install --no-save --no-audit --no-fund --omit=dev prisma@6.19.3
USER nextjs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
# local: .bin/prisma is an npm symlink; COPY flattens it and the bundled CLI then
# cannot find its sibling WASM (prisma_schema_build_bg.wasm). Run the real entry.
CMD ["sh", "-c", "node_modules/.bin/prisma migrate deploy && node server.js"]
