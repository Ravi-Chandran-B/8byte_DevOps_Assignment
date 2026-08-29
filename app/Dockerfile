FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install --production

FROM node:20-alpine
WORKDIR /app

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=build /app/node_modules ./node_modules
COPY package*.json ./
COPY index.js ./
USER appuser

EXPOSE 80
CMD ["node", "index.js"]