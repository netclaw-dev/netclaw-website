FROM python:3.12-slim
WORKDIR /app
# server.py uses the 1.x FastMCP API; mcp 2.x renamed it.
RUN pip install --no-cache-dir "mcp[cli]<2"
COPY server.py .
EXPOSE 8080
CMD ["python", "server.py"]
