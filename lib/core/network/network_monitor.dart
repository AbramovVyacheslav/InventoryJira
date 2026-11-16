import 'package:connectivity_plus/connectivity_plus.dart';

/// Монитор сети: отслеживает восстановление Wi-Fi,
/// чтобы фоновая очередь синхронизации отправлялась автоматически.
class NetworkMonitor {
  final Connectivity _connectivity = Connectivity();

  /// true — есть подключение (Wi-Fi/мобильная сеть).
  Stream<bool> get onlineStream {
    return _connectivity.onConnectivityChanged.map(
      (results) => results.any((r) => r != ConnectivityResult.none),
    );
  }

  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }
}
