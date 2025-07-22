FROM node:22.17.1-alpine

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json* ./

RUN npm i -g serve

# Copy source code
COPY . .

# Build the app
RUN npm run build

EXPOSE 5173

CMD [ "serve", "-s", "dist" ]
