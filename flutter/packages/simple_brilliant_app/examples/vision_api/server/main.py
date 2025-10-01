import random
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import PlainTextResponse
from PIL import Image
import io

app = FastAPI()

@app.post("/process")
async def process(
    image: UploadFile = File(...)
):
    try:
        # Read and validate the image
        image_bytes = await image.read()
        if not image.content_type.startswith('image/'):
            return PlainTextResponse(
                content="File must be an image",
                status_code=400
            )

        # Process the image using PIL if needed
        img = Image.open(io.BytesIO(image_bytes))

        # Your processing logic here
        # For example:
        # result_text = your_image_processing_function(img)

        # Example: return a simple text result
        items = ['tetrahedron', 'cube', 'octahedron', 'dodecahedron', 'icosahedron']
        result_text = random.choice(items)

        return PlainTextResponse(result_text)

    except Exception as e:
        return PlainTextResponse(
            content=f"Processing failed: {str(e)}",
            status_code=500
        )

# Optional: Add endpoint for API documentation
@app.get("/")
async def root():
    return {"message": "Image Processing API. Visit /docs for documentation"}
