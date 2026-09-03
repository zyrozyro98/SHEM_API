FROM node:18-slim

WORKDIR /usr/src/app

COPY package.json package-lock.json* ./
RUN npm ci --only=production

COPY . .

EXPOSE 8080

CMD ["node", "index.js"]
