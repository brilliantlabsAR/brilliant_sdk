# brilliant-msg

A TypeScript package for handling rich application-level messages for [Brilliant Labs Frame and Halo](https://brilliant.xyz/) devices, including sprites, text, audio, IMU data, photos, and click events.

[Frame SDK documentation](https://docs.brilliant.xyz/frame/frame-sdk/) | [GitHub Repo](https://github.com/brilliantlabsAR/brilliant_sdk/tree/main/webbluetooth/packages/brilliant-msg) | [API Docs](https://brilliantlabsAR.github.io/brilliant_sdk/brilliant-msg/api) | [Live Examples](https://brilliantlabsAR.github.io/brilliant_sdk/brilliant-msg/)

## Installation

```bash
npm install brilliant-msg
```

## Usage

```typescript
import { BrilliantMsg, StdLua, TxCaptureSettings, RxPhoto, BrilliantDeviceType } from 'brilliant-msg';
import frameApp from './lua/camera_frame_app.lua?raw';

// Take a photo using the Frame camera and display it
export async function run() {
  const frame = new BrilliantMsg();

  try {
    const deviceId = await frame.connect();

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CameraMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // hook up the RxPhoto receiver
    const rxPhoto = new RxPhoto({});
    const photoQueue = await rxPhoto.attach(frame);

    // give Frame some time for the autoexposure to settle
    await new Promise(resolve => setTimeout(resolve, 5000));

    // Request the photo by sending a TxCaptureSettings message
    await frame.sendMessage(0x0d, new TxCaptureSettings({}).pack());

    const jpegBytes = await photoQueue.get();

    // display the image on the web page
    const img = document.createElement('img');
    img.src = URL.createObjectURL(new Blob([jpegBytes], { type: 'image/jpeg' }));
    document.body.appendChild(img);

    // stop the photo listener and clean up its resources
    rxPhoto.detach(frame);

    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the device is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};
```

## Halo support

Frame and Halo are detected automatically after `connect()`. The `BrilliantDeviceType` enum is re-exported from `brilliant-msg` for convenience.

### Circular text layout (Halo)

Halo has a circular display. Use `CircularTextLayout` with `TxTextPage` to fit text within the circle:

```typescript
import { TxTextPage, CircularTextLayout, RectangularTextLayout } from 'brilliant-msg';

// For Halo's circular display
const layout = new CircularTextLayout({ width: 640, height: 400, fontSize: 36 });

// For Frame's rectangular display
// const layout = new RectangularTextLayout({ width: 640, height: 400, fontSize: 36 });

const page = new TxTextPage({ layout, text: 'Hello from Halo!' });
const pageData = await page.rasterizeNextPage();
if (pageData) {
  // Send header packet, then each sprite
  await frame.sendMessage(0x0a, pageData.pack());
  for (const sprite of pageData.rasterizedSprites) {
    await frame.sendMessage(0x0a, sprite.pack());
  }
}
```

### Click events (Halo)

Halo sends tap/click events with single, double, and long-press types:

```typescript
import { RxClick, ClickType } from 'brilliant-msg';

const rxClick = new RxClick();
const clickQueue = await rxClick.attach(frame);

const click = await clickQueue.get();
if (click === ClickType.SINGLE) console.log('single click');
if (click === ClickType.DOUBLE) console.log('double click');
if (click === ClickType.LONG)   console.log('long press');

rxClick.detach(frame);
```
