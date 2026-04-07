import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectionStatus extends StatefulWidget {
  const ConnectionStatus({super.key});

  @override
  State<ConnectionStatus> createState() => _ConnectionStatusState();
}

class _ConnectionStatusState extends State<ConnectionStatus> {
  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  
  @override
  void initState() {
    super.initState();
    _checkConnection();
  }
  
  Future<void> _checkConnection() async {
    final result = await Connectivity().checkConnectivity();
    setState(() => _connectionStatus = result);
  }
  
  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionStatus != ConnectivityResult.none;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green : Colors.orange,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.wifi : Icons.wifi_off,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            isConnected ? 'متصل' : 'غير متصل',
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
