import uvicorn
from main import app

if __name__ == "__main__":
    print("Listing routes:")
    for route in app.routes:
        print(f"route: {route.path}, name: {route.name}")
    
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="debug")
