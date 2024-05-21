# v0.7.1

# Base node image
FROM node:20-alpine AS node

RUN apk --no-cache add curl

RUN mkdir -p /app && chown node:node /app
WORKDIR /app

USER node

COPY --chown=node:node . .

# 数据提供者构建
FROM base AS data-provider-build
WORKDIR /app/packages/data-provider
COPY ./packages/data-provider ./
RUN npm install
#RUN npm exec openai migrate
RUN npm run build

# React 客户端构建
FROM base AS client-build
WORKDIR /app/client
COPY ./client/ ./
# 从数据提供者构建阶段复制到客户端的 node_modules
COPY --from=data-provider-build /app/packages/data-provider /app/client/node_modules/librechat-data-provider

RUN \
    # Allow mounting of these files, which have no default
    touch .env ; \
    # Create directories for the volumes to inherit the correct permissions
    mkdir -p /app/client/public/images /app/api/logs ; \
    npm config set fetch-retry-maxtimeout 600000 ; \
    npm config set fetch-retries 5 ; \
    npm config set fetch-retry-mintimeout 15000 ; \
    npm install --no-audit; \
    # React client build
    NODE_OPTIONS="--max-old-space-size=2048" npm run frontend; \
    npm prune --production; \
    npm cache clean --force

RUN mkdir -p /app/client/public/images /app/api/logs

# Node API setup
EXPOSE 3080
ENV HOST=0.0.0.0
CMD ["npm", "run", "backend"]

# Optional: for client with nginx routing
# FROM nginx:stable-alpine AS nginx-client
# WORKDIR /usr/share/nginx/html
# COPY --from=node /app/client/dist /usr/share/nginx/html
# COPY client/nginx.conf /etc/nginx/conf.d/default.conf
# ENTRYPOINT ["nginx", "-g", "daemon off;"]
