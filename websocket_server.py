import asyncio
import websockets
import json

connected_clients = set()

async def handler(websocket):
    connected_clients.add(websocket)
    print("Client connected")

    try:
        async for message in websocket:
            data = json.loads(message)
            command = data.get("command", "unknown")
            print(f"Received from Flutter: {command}")

            if command == "GET_LOCATION":
                # Static location for testing (near Cairo, Egypt)
                location_data = {
                    "location": {
                        "lat": 29.36342,
                        "lon": 30.99788
                    }
                }
                await websocket.send(json.dumps(location_data))
            else:
                response = f"Python received: {command}"
                await websocket.send(json.dumps({"response": response}))
    except websockets.exceptions.ConnectionClosed:
        print("Client disconnected")
    finally:
        connected_clients.remove(websocket)

async def main():
    async with websockets.serve(handler, "127.0.0.1", 8765):
        print("WebSocket server started on ws://127.0.0.1:8765")
        await asyncio.Future()  # Run forever

if __name__ == "__main__":
    asyncio.run(main())