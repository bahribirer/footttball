import asyncio
import websockets

async def hello():
    uri = "ws://localhost:8000/ws/testroom"
    try:
        async with websockets.connect(uri) as websocket:
            print("Connected!")
            await websocket.send("Hello")
            response = await websocket.recv()
            print(f"Received: {response}")
    except Exception as e:
        print(f"Failed: {e}")

asyncio.run(hello())
