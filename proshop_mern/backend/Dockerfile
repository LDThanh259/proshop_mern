FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY backend ./backend
COPY uploads ./uploads

EXPOSE 5000
CMD ["npm", "start"]

