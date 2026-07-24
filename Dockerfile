FROM node:20-alpine AS base

FROM base AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npx prisma generate
# Build-stage placeholders: lib/auth.ts throws at import when OAuth env is
# empty, and next build imports route modules during page-data collection.
# Real values come from .env at RUNTIME (standalone server reads process.env).
ENV GOOGLE_CLIENT_ID=build-placeholder \
    GOOGLE_CLIENT_SECRET=build-placeholder \
    NEXTAUTH_SECRET=build-placeholder \
    APP_SECRET=build-placeholder \
    NEXTAUTH_URL=http://localhost:3000 \
    DATABASE_URL=postgresql://build:build@localhost:5432/build
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
USER nextjs
EXPOSE 3000
ENV PORT=3000
# npx unpinned pulls prisma@latest (7.x rejects url= in schema) — pin to the project version.
CMD ["sh", "-c", "npx prisma@6.19.3 migrate deploy && node server.js"]
