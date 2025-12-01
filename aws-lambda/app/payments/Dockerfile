FROM public.ecr.aws/lambda/python:3.11

WORKDIR /var/task
COPY src/ ./src/
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt || true  # optional if no deps

CMD ["src.handler.handler"]
