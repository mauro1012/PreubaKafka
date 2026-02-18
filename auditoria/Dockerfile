FROM node:20-slim

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY . .

# Al ser un consumidor de eventos, no requiere puertos abiertos
CMD ["node", "index.js"]