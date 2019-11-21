# BleMesh

 ![CocoaPods](https://img.shields.io/badge/pod-1.0.0-3388CC.svg) ![Target](https://img.shields.io/badge/target-iOS%2011.0+-CC8833.svg) ![Languages](https://img.shields.io/badge/languages-Objective--C%20%7C%20Swift-338888.svg)

BleMesh makes it easy to mesh devices to let them share messages over Bluetooth Low Energy (BLE).

1. [Why use the BleMesh framework?](#why-use-the-afklblemesh-framework)
2. [Requirements](#requirements)
3. [Integration](#integration)
4. [Usage](#usage)
   - [Project configuration](#project-configuration)
   - [Initialization](#initialization)
   - [Broadcast](#broadcast)
   - [Stopping and restarting](#stopping-and-restarting)
   - [Protocol adoption](#protocol-adoption)
   - [Encryption](#encryption)
5. [Logger](#logger)
6. [Samples](#samples#)
   
<br>

## Why use the BleMesh framework?
---

The iOS CoreBlutooth framework is very close to the BLE specification. No high level of abstractionis made and everything is left to the responsibility of the developer.

For example, if a developer wants to send a text via BLE, as he would simply do an HTTP POST, he will have to:

- decide whether the device acts as a Central or as a Peripheral
- initialize and signal itself as such
- find the recipient (scan) or notify its entourage of its presence (advertisement)
- match the service and characteristics
- establish a connection or expect one
- split the document into paquets not exceeding the MTU (Maximum Transmission Unit) length
- send them by managing any saturation of the Bluetooth stack, errors, the resending of packets
- and so on...

**And what if the recipient is not within the signal range?** The developer will have to establish himself a route to the recipient and make sure that the intermediate devices act as gateways.

BleMesh framework does all this for the developer and much more.<br>
It allows to create a BLE mesh between the devices entering a same session in order to share messages.<br>
**No more need for wifi or mobile network to make peripherals communicate with each other in one place.**

This framework is limited to uses where the space and the number of devices are mastered. It is not suitable for use in open or over-extended locations, where the number of devices entering the mesh could grow too much.
Moreover, even if it is technically capable, the framework is not suitable for the exchange of large volumes of data.

<br>

## Requirements
----

- iOS 11.0+
- Swift | Objective-C

<br>

## Integration
---

#### CocoaPods (iOS 11+)

You can use [CocoaPods](http://cocoapods.org/) to install `BleMesh` by adding it to your `Podfile`:

```ruby
platform :ios, '11.0'

source 'https://github.com/jjwaxym/podrepo.git'

use_frameworks!

target 'MyApp' do
pod 'BleMesh'
end
```

Note that this requires your iOS deployment target to be at least 11.0.<br>
Don't forget the `use_frameworks!` directive to integrate with Objective-C projects.

<br>

#### Manually

To use this library in your project manually you may:

1. for Projects, just drag the swift files to the project tree
2. for Workspaces, include the whole BleMesh.xcodeproj

<br>

## Usage
---

While BleMesh is compliant with Objective-c and Swift, code examples below are all provided in swift.

<br>

#### Project configuration

Your project must activate Background modes (`Project > Capabilities`) for `Uses Bluetooth LE accessories` and `Acts as a Bluetooth LE accessory`.
Plus you shall specify the reason for your app to use Bluetooth ( `NSBluetoothAlwaysUsageDescription` key in your project property list).

<br>

#### Initialization

```swift
import BleMesh
```

```swift
let sessionId: UInt64 = 1
let terminalId: BleTerminalId = 2
BleManager.shared.delegate = self
BleManager.shared.start(session: sessionId, terminal: terminalId)
```

**Important!** Only peripherals sharing the same session identifier will enter the mesh. So it is essential for your project to choose and share well the session ID.<br>
**Important!** The terminal identifier shall remain the same and be unique throughout a single session.

Note that this requires your `class` to adopt the `BleManagerDelegate` protocol. [See `Protocol adoption` below](#protocol-adoption).

<br>

#### Broadcast

```swift
let nextItemIndex: BleItemIndex = 0
let itemData = "My first message shared over BleMesh".data(using: .utf8) ?? Data()
let headerData = "A cool title".data(using: .utf8) ?? Data()
let item = BleItem(terminalId: terminalId, itemIndex: nextItemIndex, previousIndexes: nil, size: itemData.count, headerData: headerData)
BleManager.shared.broadcast(item: item)

...

func bleManagerItemSliceFor(terminalId: BleTerminalId, index: BleItemIndex, offset: UInt32, length: UInt32) -> Data? {
    guard offset < itemData.count else {
        return nil
    }
    return itemData[offset..<min(itemData.count, offset + length)]
}
```
**Important!** The item index shall be unique throughout a single session for a single terminal ID. This means that two peripherals may have different items with the same inner item index, but a single peripheral will never have the same item index for two items it broadcasts. Item indexes should start at 0 and increase in increments of 1.

**Important!** If `BleItem.headerData` exceeds 255 bytes, it will be truncated to 255 bytes before sending.

When an item is modified, it should be given a new `itemIndex` and its previous index is appended to the `previousIndexes` array.

When deleting an item, you must never remove it from the items list of a session. Instead, do as if it was modified (new `itemIndex` and previous one appended to `previousIndexes`) and choose a `headerData` content you identify as a deletion.

<br>

#### Stopping and restarting

```swift
BleManager.shared.stop()
```
```swift
BleManager.shared.start()
```
or

```swift
BleManager.shared.start(session: sessionId, terminal: terminalId)
```
The short `start` version shall be used only if the long has been called successfully at least once since the application launched.
Calling the long version with a different `sessionId` or a different `terminalId` stops the `BleManager` and restarts it.
An optional third parameter `cryptoHandler` may be provided. [See `Encryption` below](#encryption).

<br>

#### Protocol adoption

In order to work well, `BleManager` needs one of your classes to adopt the `BleManagerDelegate` and be registered as its `delegate`. Without this, it will be impossible for BleMesh to let you know a new message was shared on the mesh and to let other peripherals know what they missed when they will join the mesh.

**Important!** Every call is executed on a dispatch queue created by the framework!

```swift
var bleItems: [BleItem] { get }
```
This is used to provide the list of all the items you broadcasted and the items you received from the beginning of the session.

You must also implement the following function so that BleMesh can retrieve a slive of the content of an item before sharing it with new entrants.

```swift
func bleManagerItemSliceFor(terminalId: BleTerminalId, index: BleItemIndex, offset: UInt32, length: UInt32) -> Data?
```
You are encouraged to implement the following function to let BleMesh inform you a new message was received on the mesh. Be aware that you may receive the same message several times.

```swift
func bleManagerDidReceive(item: BleItem, data: Data)
```
`bleManagerDidStart`, `bleManagerDidStop`, `bleManagerDidConnect`, and `bleManagerDidDisconnect` let you know respectively that BleMesh has started and is ready to communicate, that it has stopped, that a new peripheral has joined the mesh and is within your signal range, and that a periphal has exited the mesh or your signal range.

`bleManagerDidUpdateBluetoothState` let you be informed when the device's Bluetooth state changes. Current state can also be retrieved:

```swift
BleManager.shared.bluetoothState
```
To be informed of progress information of sendings and receivings, you can implement those two functions:

```swift
func bleManagerIsSending(item: BleItem, totalSizeReceived: UInt32)
func bleManagerIsReceiving(item: BleItem, totalSizeReceived: UInt32)
```

<br>

#### Encryption

If you want to encrypt the data transfer, you may adopt the `BleCryptoHandler` protocol and provide its implementation when calling the start function.

```swift
func encrypt(message: Data) -> Data?
func decrypt(message: Data) -> Data?
```

Your implementation of `encrypt` ans `decrypt` functions must return a `nil` result when an error occured during encryption or decryption. You are responsible for error handling and management.
**Important!** When `encrypt` returns `nil`, the message is not broadcasted on the mesh.
**Important!** When `decrypt` returns `nil`, the message received on the mesh is trashed.

<br>

## Logger
---

By default, BleMesh prints its output logs in the console. And the default log severity is configured to `.debug`

To change the logger outputs, adopt the `BleLoggerHandler` protocol and change de `BleLogger` handler:
```swift
BleLogger.loggerHandler = myLoggerHandler
```
You can configure a new log severity:
```swift
BleLogger.logSeverity = BleLogSeverity.warn
```

<br>

## Samples
---

<br>

#### BleBroadcaster

This sample shows how to integrate BleMesh with an Objective-C project and how to encrypt data transfer using AES-128 algorithm.

<br>

#### BleChat

This sample shows how to integrate BleMesh with a Swift project transfering more complex data than BleBroadcaster, without using encryption.

<br>


