# Stage 1: Frontend dependencies
FROM node:20-alpine AS frontend-dependencies
WORKDIR /opt/app
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

# Stage 2: Build frontend
FROM node:20-alpine AS frontend-builder
WORKDIR /opt/app
COPY ./frontend .
COPY --from=frontend-dependencies /opt/app/node_modules ./node_modules
RUN npm run build

# Stage 3: Backend dependencies
FROM node:20-alpine AS backend-dependencies
RUN apk add --no-cache python3
WORKDIR /opt/app
COPY backend/package.json backend/package-lock.json ./
RUN npm ci

# Stage 4: Build backend
FROM node:20-alpine AS backend-builder
WORKDIR /opt/app
COPY ./backend .
COPY --from=backend-dependencies /opt/app/node_modules ./node_modules
RUN npx prisma generate
RUN npm run build && npm prune --production

# Stage 5: Final image
FROM node:20-alpine AS runner
ENV NODE_ENV=docker

# Alpine specific dependencies
RUN apk update --no-cache
RUN apk upgrade --no-cache
RUN apk add --no-cache curl nginx

COPY ./nginx/nginx.conf /etc/nginx/nginx.conf

WORKDIR /opt/app/frontend
COPY --from=frontend-builder /opt/app/public ./public
COPY --from=frontend-builder /opt/app/.next/standalone ./
COPY --from=frontend-builder /opt/app/.next/static ./.next/static
COPY --from=frontend-builder /opt/app/public/img /tmp/img

WORKDIR /opt/app/backend
COPY --from=backend-builder /opt/app/node_modules ./node_modules
COPY --from=backend-builder /opt/app/dist ./dist
COPY --from=backend-builder /opt/app/prisma ./prisma
COPY --from=backend-builder /opt/app/package.json ./

WORKDIR /opt/app

EXPOSE 3200

# Add a health check to ensure the container is healthy
HEALTHCHECK --interval=10s --timeout=3s CMD curl -f http://localhost:3200/api/health || exit 1

# Application startup
# HOSTNAME=0.0.0.0 fixes https://github.com/vercel/next.js/issues/51684. It can be removed as soon as the issue is fixed
CMD cp -rn /tmp/img/* /opt/app/frontend/public/img && nginx && PORT=3333 HOSTNAME=0.0.0.0 node frontend/server.js & cd backend && npm run prod