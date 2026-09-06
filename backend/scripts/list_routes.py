from main import app
from fastapi.routing import APIRoute

for route in app.routes:
    print(f"{route.path} -> {route.name}")
