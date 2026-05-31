FROM node:20-alpine AS build

WORKDIR /app/frontend

# React Scripts cũ cần cờ này để build được trên Node 20
ENV NODE_OPTIONS=--openssl-legacy-provider

# Copy dependency manifests trước để tận dụng cache build
COPY frontend/package*.json ./
RUN npm install

# Copy toàn bộ source frontend và build static files
COPY frontend ./
RUN npm run build

FROM nginx:1.27-alpine

# Frontend now serves only static React files.
COPY --from=build /app/frontend/build /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
