import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:atriarch/widgets.dart';
import 'Screens/ProgramA.dart';
import 'Screens/ProgramB.dart';

void main() {
  runApp(FlutterBlueApp());
}

class FlutterBlueApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      color: Colors.lightBlue,
      home: StreamBuilder<BluetoothAdapterState>(
          stream: FlutterBluePlus.adapterState,
          initialData: BluetoothAdapterState.unknown,
          builder: (c, snapshot) {
            final state = snapshot.data;
            if (state == BluetoothAdapterState.on) {
              return FindDevicesScreen();
            }
            return BluetoothOffScreen(state: state);
          }),
    );
  }
}

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({Key? key, this.state}) : super(key: key);

  final BluetoothAdapterState? state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.bluetooth_disabled,
              size: 200.0,
              color: Colors.white54,
            ),
            Text(
              'Bluetooth Adapter is ${state != null ? state.toString().split('.').last : 'not available'}.',
            ),
          ],
        ),
      ),
    );
  }
}

class FindDevicesScreen extends StatefulWidget {
  const FindDevicesScreen({Key? key}) : super(key: key);

  @override
  _FindDevicesScreenState createState() => _FindDevicesScreenState();
}

class _FindDevicesScreenState extends State<FindDevicesScreen> {
  @override
  void initState() {
    super.initState();
    FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('Find Transmission Unit'),
        ),
        body: RefreshIndicator(
          onRefresh: () =>
              FlutterBluePlus.startScan(timeout: Duration(seconds: 4)),
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                StreamBuilder<List<BluetoothDevice>>(
                  stream: Stream.periodic(Duration(seconds: 2))
                      .map((_) => FlutterBluePlus.connectedDevices),
                  initialData: [],
                  builder: (c, snapshot) => Column(
                    children: snapshot.data!
                        .map((d) => ListTile(
                              title: Text(d.platformName),
                              subtitle: Text(d.remoteId.toString()),
                              trailing:
                                  StreamBuilder<BluetoothConnectionState>(
                                stream: d.connectionState,
                                initialData:
                                    BluetoothConnectionState.disconnected,
                                builder: (c, snapshot) {
                                  if (snapshot.data ==
                                      BluetoothConnectionState.connected) {
                                    return ElevatedButton(
                                      child: Text('OPEN'),
                                      onPressed: () =>
                                          Navigator.of(context).push(
                                              MaterialPageRoute(
                                                  builder: (context) =>
                                                      DeviceScreen(
                                                          device: d))),
                                    );
                                  }
                                  return Text(snapshot.data.toString());
                                },
                              ),
                            ))
                        .toList(),
                  ),
                ),
                StreamBuilder<List<ScanResult>>(
                  stream: FlutterBluePlus.scanResults,
                  initialData: [],
                  builder: (c, snapshot) => Column(
                    children: snapshot.data!
                        .map(
                          (r) => ScanResultTile(
                            result: r,
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (context) {
                              r.device.connect();
                              return DeviceScreen(device: r.device);
                            })),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: StreamBuilder<bool>(
          stream: FlutterBluePlus.isScanning,
          initialData: false,
          builder: (c, snapshot) {
            if (snapshot.data!) {
              return FloatingActionButton(
                child: Icon(Icons.stop),
                onPressed: () => FlutterBluePlus.stopScan(),
                backgroundColor: Colors.red,
              );
            } else {
              return FloatingActionButton(
                  backgroundColor: Colors.deepPurpleAccent[400],
                  child: Icon(Icons.search),
                  onPressed: () => FlutterBluePlus.startScan(
                      timeout: Duration(seconds: 4)));
            }
          },
        ),
      ),
    );
  }
}

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({Key? key, required this.device}) : super(key: key);
  final BluetoothDevice device;
  @override
  _DeviceScreenState createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  final String SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String CHARACTERISTIC_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb";
  BluetoothCharacteristic? chObj1;
  bool discover = false;
  bool isLoading = true;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _connectionSubscription =
        widget.device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Device disconnected'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            leading: IconButton(
                icon: Icon(Icons.close_outlined, color: Colors.white),
                onPressed: () {
                  if (discover) {
                    widget.device.disconnect();
                  }
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          const FindDevicesScreen(),
                    ),
                  );
                }),
            title: Text("Jeremy's App"),
            actions: <Widget>[
              StreamBuilder<BluetoothConnectionState>(
                stream: widget.device.connectionState,
                initialData: BluetoothConnectionState.disconnected,
                builder: (c, snapshot) {
                  switch (snapshot.data) {
                    case BluetoothConnectionState.connected:
                      if (discover == false) {
                        discover = true;
                        discoverServices();
                      }
                      break;
                    case BluetoothConnectionState.disconnected:
                      print("not connected");
                      break;
                    default:
                      break;
                  }
                  return Container();
                },
              )
            ],
          ),
          body: (isLoading == true)
              ? Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: 20),
                      Container(
                        width: 200,
                        height: 200,
                        child:
                            Image(image: AssetImage('assets/logo.png')),
                      ),
                      SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildMenuButton(
                            label: "A",
                            description: "Randomized timing program",
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ProgramA(
                                        device: widget.device,
                                        chObj1: chObj1,
                                      )),
                            ),
                          ),
                          _buildMenuButton(
                            label: "B",
                            description: "Fixed timing program",
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ProgramB(
                                        device: widget.device,
                                        chObj1: chObj1,
                                      )),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 30),
                    ],
                  ),
                )),
    );
  }

  Widget _buildMenuButton({
    required String label,
    required String description,
    required VoidCallback onPressed,
    Color color = Colors.blue,
  }) {
    return Column(
      children: [
        MaterialButton(
          minWidth: 150,
          height: 150,
          color: color,
          child: Text(
            label,
            style: TextStyle(fontSize: 25, color: Colors.white),
          ),
          onPressed: onPressed,
        ),
        SizedBox(height: 10),
        Container(
          width: 150,
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  discoverServices() async {
    try {
      List<BluetoothService> services =
          await widget.device.discoverServices();
      print("Discovering services........");
      for (BluetoothService s in services) {
        print(s.uuid.toString());
        if (s.uuid.toString() == SERVICE_UUID) {
          print("Service found!=============================");

          for (BluetoothCharacteristic c in s.characteristics) {
            if (c.uuid.toString() == CHARACTERISTIC_UUID) {
              chObj1 = c;
              print("charis found!===========================");
              setState(() {
                isLoading = false;
              });
              return;
            }
          }
        }
      }
      // Service not found
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Required BLE service not found on this device'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print("Error discovering services: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to discover services: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
