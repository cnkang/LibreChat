# 基础镜像
FROM node:lts AS base

# 数据提供者构建
FROM base AS data-provider-build
WORKDIR /app/packages/data-provider
COPY ./packages/data-provider ./
RUN npm install
RUN npm exec openai migrate
RUN npm run build

# React 客户端构建
FROM base AS client-build
WORKDIR /app/client
COPY ./client/ ./
# 从数据提供者构建阶段复制到客户端的 node_modules
COPY --from=data-provider-build /app/packages/data-provider /app/client/node_modules/librechat-data-provider
RUN npm install
ENV NODE_OPTIONS="--max-old-space-size=2048"
RUN npm run build

# Node.js API 设置
FROM base AS api-build
WORKDIR /app/api
COPY api/package*.json ./
COPY api/ ./
# 从数据提供者构建阶段复制到 API 的 node_modules
COPY --from=data-provider-build /app/packages/data-provider /app/api/node_modules/librechat-data-provider
RUN npm install
RUN npm exec openai migrate

# 从客户端构建阶段复制构建的静态文件
COPY --from=client-build /app/client/dist /app/client/dist

# 使用 MongoDB 官方镜像
FROM mongo:latest AS mongodb

# 使用 Meilisearch 官方镜像
#FROM getmeili/meilisearch:latest AS meilisearch

# 最终阶段：组合所有服务
FROM ubuntu:latest
RUN apt-get update && apt-get install -y libcurl4 curl
# 拷贝 MongoDB 和 Meilisearch 可执行文件
COPY --from=mongodb /usr/bin/mongod /usr/bin/mongod
#COPY --from=meilisearch /bin/meilisearch /usr/bin/meilisearch
RUN curl -sSfL https://install.meilisearch.com | sh > /dev/null 2>&1
RUN mv /meilisearch /usr/bin/meilisearch


# 拷贝 Node.js 和 npm
COPY --from=base /usr/local/bin/node /usr/local/bin/
COPY --from=base /usr/local/bin/npm /usr/local/bin/
COPY --from=base /usr/local/lib/node_modules /usr/local/lib/node_modules

# 创建 MongoDB 和 Meilisearch 所需的数据目录
RUN mkdir -p /data/db /meili_data

# 设置环境变量
ENV NODE_OPTIONS="--max-old-space-size=2048" \
    HOST=0.0.0.0

# 设置工作目录
WORKDIR /app/api

# 复制 API 和客户端文件
COPY --from=api-build /app/api /app/api
COPY --from=client-build /app/client/dist /app/client/dist

# 暴露端口
EXPOSE 3080 27017 7700

RUN apt-get remove -y curl
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# 启动 MongoDB、Meilisearch 和 Node.js API
CMD mongod --fork --logpath /var/log/mongod.log --noauth --dbpath /data/db && \
    meilisearch --http-addr 0.0.0.0:7700 --db-path /meili_data & \
    node server/index.js

