# Lambda base image (Node.js 20)
FROM public.ecr.aws/lambda/nodejs:20

# App code
WORKDIR /var/task
COPY src/ ./src/
COPY package*.json ./
RUN npm ci --omit=dev

# Lambda entrypoint: module.function
CMD ["src/handler.handler"]
