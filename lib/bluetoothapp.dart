import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui';


// Enum to track connection states
enum ConnectionState { disconnected, connecting, connected }

// Enum to track device states
enum DeviceState { off, neutral, on }

class BluetoothApp extends StatefulWidget {
  const BluetoothApp({super.key});

  @override
  _BluetoothAppState createState() => _BluetoothAppState();
}

class _BluetoothAppState extends State<BluetoothApp> {
  // Constants
  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _snackBarDuration = Duration(seconds: 3);

  // State variables
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  final List<BluetoothDevice> _devicesList = [];
  
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  BluetoothDevice? _selectedDevice;
  BluetoothConnection? _connection;
  ConnectionState _connectionState = ConnectionState.disconnected;
  DeviceState _deviceState = DeviceState.neutral;
  
  bool _isBluetoothOperationInProgress = false;

  // Stream subscriptions
  StreamSubscription<BluetoothState>? _bluetoothStateSubscription;

  // Theme colors
  final Map<String, Color> _colors = {
    'on': Colors.green,
    'off': Colors.red,
    'neutral': Colors.blue,
    'disabled': Colors.grey,
  };

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  @override
  void dispose() {
    _cleanupConnections();
    super.dispose();
  }

  // Initialize Bluetooth and permissions
  Future<void> _initializeBluetooth() async {
    try {
      // Initialize state
      _bluetoothState = await _bluetooth.state;
      
      // Setup state change listener
      _bluetoothStateSubscription = _bluetooth.onStateChanged().listen((BluetoothState state) {
        if (mounted) {
          setState(() {
            _bluetoothState = state;
            if (state == BluetoothState.STATE_OFF) {
              _connectionState = ConnectionState.disconnected;
              _deviceState = DeviceState.neutral;
            }
          });
        }
      });

      // Check permissions
      await _checkAndRequestPermissions();
      
      // Get paired devices if Bluetooth is enabled
      if (_bluetoothState.isEnabled) {
        await _getPairedDevices();
      }
    } catch (e) {
      _showError('Failed to initialize Bluetooth: $e');
    }
  }

  // Permission handling
  Future<void> _checkAndRequestPermissions() async {
    final permissions = [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ];

    // Request all required permissions
    Map<Permission, PermissionStatus> statuses = await permissions.request();
    
    // Check if any permission is denied
    final denied = statuses.values.where((status) => status.isDenied).toList();
    if (denied.isNotEmpty) {
      _showError('Required permissions were denied. Please enable them in settings.');
    }
  }

  // Get paired devices
  Future<void> _getPairedDevices() async {
    try {
      final devices = await _bluetooth.getBondedDevices();
      if (mounted) {
        setState(() {
          _devicesList.clear();
          _devicesList.addAll(devices);
          if (_devicesList.isNotEmpty && _selectedDevice == null) {
            _selectedDevice = _devicesList.first;
          }
        });
      }
    } catch (e) {
      _showError('Failed to get paired devices: $e');
    }
  }

  // Connect to device with timeout and error handling
  Future<void> _connect() async {
    if (_selectedDevice == null || _isBluetoothOperationInProgress) return;

    setState(() {
      _isBluetoothOperationInProgress = true;
      _connectionState = ConnectionState.connecting;
    });

    try {
      _connection = await BluetoothConnection.toAddress(_selectedDevice!.address)
          .timeout(_connectionTimeout);
      
      if (mounted) {
        setState(() {
          _connectionState = ConnectionState.connected;
          _deviceState = DeviceState.neutral;
        });
        _showMessage('Connected to ${_selectedDevice!.name}');
      }
    } catch (e) {
      _showError('Connection failed: $e');
      if (mounted) {
        setState(() {
          _connectionState = ConnectionState.disconnected;
          _deviceState = DeviceState.neutral;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBluetoothOperationInProgress = false;
        });
      }
    }
  }

  // Disconnect handling
  Future<void> _disconnect() async {
    if (_isBluetoothOperationInProgress) return;

    setState(() {
      _isBluetoothOperationInProgress = true;
    });

    try {
      await _connection?.close();
    } catch (e) {
      _showError('Error during disconnection: $e');
    } finally {
      if (mounted) {
        setState(() {
          _connection = null;
          _connectionState = ConnectionState.disconnected;
          _deviceState = DeviceState.neutral;
          _isBluetoothOperationInProgress = false;
        });
      }
    }
  }

  // Send message to device with error handling
  Future<void> _sendMessage(String message, DeviceState newState) async {
    if (_connectionState != ConnectionState.connected) return;

    try {
      _connection!.output.add(utf8.encode('$message\r\n'));
      await _connection!.output.allSent;
      if (mounted) {
        setState(() => _deviceState = newState);
      }
    } catch (e) {
      _showError('Failed to send message: $e');
      await _disconnect();
    }
  }

  // Cleanup connections
  void _cleanupConnections() {
    _bluetoothStateSubscription?.cancel();
    _connection?.dispose();
    _connection = null;
  }

  // UI Helper methods
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: _snackBarDuration)
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: _snackBarDuration,
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: _buildAppBar(),
        body: _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Flutter Bluetooth'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _bluetoothState.isEnabled ? _getPairedDevices : null,
        ),
      ],
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBluetoothSwitch(),
          const Divider(height: 32),
          _buildDeviceSelector(),
          const Divider(height: 32),
          _buildDeviceControls(),
        ],
      ),
    );
  }

  Widget _buildBluetoothSwitch() {
    return SwitchListTile(
      title: const Text('Enable Bluetooth'),
      value: _bluetoothState.isEnabled,
      onChanged: _isBluetoothOperationInProgress
          ? null
          : (bool value) async {
              try {
                if (value) {
                  await _bluetooth.requestEnable();
                } else {
                  await _bluetooth.requestDisable();
                }
                await _getPairedDevices();
              } catch (e) {
                _showError('Failed to ${value ? 'enable' : 'disable'} Bluetooth');
              }
            },
    );
  }

  Widget _buildDeviceSelector() {
    return Row(
      children: [
        Expanded(
          child: DropdownButton<BluetoothDevice>(
            isExpanded: true,
            value: _selectedDevice,
            items: _devicesList.map((device) {
              return DropdownMenuItem(
                value: device,
                child: Text(device.name ?? 'Unknown device'),
              );
            }).toList(),
            onChanged: _isBluetoothOperationInProgress
                ? null
                : (BluetoothDevice? device) {
                    if (mounted && device != null) {
                      setState(() => _selectedDevice = device);
                    }
                  },
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: _isBluetoothOperationInProgress || !_bluetoothState.isEnabled
              ? null
              : _connectionState == ConnectionState.connected
                  ? _disconnect
                  : _connect,
          child: Text(_connectionState == ConnectionState.connected
              ? 'Disconnect'
              : 'Connect'),
        ),
      ],
    );
  }

  Widget _buildDeviceControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Device Control',
              style: TextStyle(
                fontSize: 20,
                color: _getStateColor(),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _connectionState == ConnectionState.connected
                      ? () => _sendMessage('1', DeviceState.on)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _colors['on'],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('ON'),
                ),
                ElevatedButton(
                  onPressed: _connectionState == ConnectionState.connected
                      ? () => _sendMessage('0', DeviceState.off)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _colors['off'],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('OFF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStateColor() {
    if (_connectionState != ConnectionState.connected) {
      return _colors['disabled']!;
    }
    switch (_deviceState) {
      case DeviceState.on:
        return _colors['on']!;
      case DeviceState.off:
        return _colors['off']!;
      case DeviceState.neutral:
        return _colors['neutral']!;
    }
  }
}