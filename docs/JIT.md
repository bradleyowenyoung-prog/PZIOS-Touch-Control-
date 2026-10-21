# JIT

iOS 26 and later on devices with TXM only allow executable memory for processes with a debugger attached. Two ways are supported:

- **Built-in**: a helper app extension attaches StikJIT to the game. Needs a pairing file, a loopback VPN (LocalDevVPN) and Developer Mode.
- **Manual**: run `scripts/pzios-jvm.js` in StikDebug after pressing Play.

The Setup guide inside the app walks through both.
