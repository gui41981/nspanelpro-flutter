import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'states.dart';
import 'panels.dart';
import 'transport.dart';

enum HaStatus { connecting, online, offline, authFailed }

typedef TransportFactory = Future<HaTransport> Function();

/// The Home Assistant websocket, and nothing else.
///
/// A port of kiosk/app.js from the cards repo, which was verified against a
/// fake HA speaking the real protocol: auth handshake, get_states, a
/// state_changed subscription, call_service, and generic subscribeMessage for
/// the weather forecast. Reconnects with backoff.
class HaConnection {
  HaConnection({
    required this.transportFactory,
    required this.token,
    required this.states,
  });

  final TransportFactory transportFactory;
  final String token;
  final HaStates states;

  final ValueNotifier<HaStatus> status = ValueNotifier(HaStatus.connecting);

  /// Called after every successful auth + state seed, so the app can
  /// (re)load the dashboard config on each reconnect.
  void Function()? onReady;

  HaTransport? _t;
  StreamSubscription<String>? _listen;

  int _id = 1;

  final _pending = <int, Completer<dynamic>>{};
  final _subs = <int, void Function(dynamic)>{};

  /// Counts successful connections. Subscriptions do not survive a socket,
  /// so anything that subscribes once per connection compares against this.
  int generation = 0;

  Duration _backoff = const Duration(seconds: 1);
  Timer? _retryTimer;

  bool _closed = false;
  bool _authed = false;

  bool get isOnline => _authed;

  bool _started = false;

  /// Starts the connection asynchronously.
  /// The application can use unawaited(start()) so UI startup never waits
  /// for Home Assistant, while tests and explicit callers can await it.
  Future<void> start() {
    if (_closed || _started) return Future<void>.value();
    _started = true;
    return _connect();
  }

  Future<void> dispose() async {
    _closed = true;

    _retryTimer?.cancel();

    await _listen?.cancel();
    await _t?.close();

    _failPending();
  }

  Future<void> _connect() async {
    if (_closed) {
      return;
    }

    status.value = HaStatus.connecting;

    try {
      debugPrint('ha: connecting');

      _t = await transportFactory();

      debugPrint('ha: websocket connected');
    } catch (e, st) {
      debugPrint('ha: websocket connect failed: $e');
      debugPrint('$st');

      _retry();
      return;
    }

    _listen = _t!.messages.listen(
      _onMessage,
      onDone: () {
        if (!_closed) {
          _retry();
        }
      },
      onError: (error) {
        debugPrint('ha: websocket error: $error');

        if (!_closed) {
          _retry();
        }
      },
    );
  }

  void _failPending() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('socket closed'));
      }
    }

    _pending.clear();
    _subs.clear();
  }

  void _retry() {
    if (_closed || (_retryTimer?.isActive ?? false)) return;

    _authed = false;
    status.value = HaStatus.offline;
    _failPending();

    final listen = _listen;
    _listen = null;
    if (listen != null) {
      unawaited(listen.cancel().catchError((Object _) {}));
    }

    final transport = _t;
    _t = null;
    if (transport != null) {
      unawaited(transport.close().catchError((Object _) {}));
    }

    final delay = _backoff;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_connect());
    });

    _backoff = Duration(
      milliseconds: min(_backoff.inMilliseconds * 2, 15000),
    );
  }
  void _onMessage(String raw) {
    debugPrint('ha: message: $raw');

    final dynamic msg;

    try {
      msg = jsonDecode(raw);
    } catch (_) {
      return;
    }

    if (msg is! Map) {
      return;
    }

    switch (msg['type']) {
      case 'auth_required':
        _t!.send(jsonEncode({'type': 'auth', 'access_token': token}));

      case 'auth_invalid':
        _closed = true;
        status.value = HaStatus.authFailed;

      case 'auth_ok':
        _authed = true;
        _backoff = const Duration(seconds: 1);
        status.value = HaStatus.online;

        _seed();

      case 'result':
        final completer = _pending.remove(msg['id']);

        if (completer == null) {
          return;
        }

        if (msg['success'] == true) {
          completer.complete(msg['result']);
        } else {
          final error = msg['error'];

          completer.completeError(
            StateError(error is Map ? '${error['message']}' : 'call failed'),
          );
        }

      case 'event':
        _subs[msg['id']]?.call(msg['event']);
    }
  }

  Future<dynamic> send(Map<String, dynamic> payload) {
    if (!_authed || _t == null) {
      return Future.error(StateError('not connected'));
    }

    final id = _id++;
    final completer = Completer<dynamic>();

    _pending[id] = completer;

    _t!.send(jsonEncode({'id': id, ...payload}));

    return completer.future;
  }

  /// Same shape as the frontend's connection.subscribeMessage.
  /// Resolves to an unsubscribe function.
  Future<Future<void> Function()> subscribe(
    Map<String, dynamic> payload,
    void Function(dynamic event) onEvent,
  ) {
    if (!_authed || _t == null) {
      return Future.error(StateError('not connected'));
    }

    final id = _id++;

    _subs[id] = onEvent;

    final completer = Completer<dynamic>();
    _pending[id] = completer;

    _t!.send(jsonEncode({'id': id, ...payload}));

    return completer.future
        .then(
          (_) => () async {
            _subs.remove(id);

            try {
              await send({'type': 'unsubscribe_events', 'subscription': id});
            } catch (_) {
              // The socket may already be gone.
              // There is nothing left to release locally.
            }
          },
        )
        .catchError((Object error) {
          _subs.remove(id);
          throw error;
        });
  }

  /// get_states once, then every state_changed. Not subscribe_entities:
  /// its compressed diff format is more code to get right, and a panel's
  /// handful of cards filters client-side cheaply.
  Future<void> _seed() async {
    try {
      final list = await send({'type': 'get_states'}) as List;

      states.replaceAll({
        for (final s in list.cast<Map>())
          s['entity_id'] as String: HaState.fromJson(s.cast<String, dynamic>()),
      });

      await subscribe(
        {'type': 'subscribe_events', 'event_type': 'state_changed'},
        (event) {
          final data = (event as Map?)?['data'];

          if (data is! Map) {
            return;
          }

          final entityId = data['entity_id'];

          if (entityId is! String) {
            return;
          }

          final newState = data['new_state'];

          states.update(
            entityId,
            newState is Map
                ? HaState.fromJson(newState.cast<String, dynamic>())
                : null,
          );
        },
      );

      generation++;
      onReady?.call();
    } catch (e) {
      debugPrint('ha: initial state seed failed: $e');
      if (!_closed) _retry();
    }
  }

  /// False when HA refused the service (a wrong alarm code, for example)
  /// or the socket is down.
  ///
  /// The transport/protocol error is converted here into the boolean result
  /// expected by the UI layer. Callers therefore do not need to catch
  /// WebSocket errors for ordinary service calls.

  Future<HaPanels?> fetchPanels() async {
    try {
      final result = await send({
        'type': 'get_panels',
      });

      return HaPanels.fromJson(result);
    } catch (error) {
      debugPrint('ha: get_panels failed: $error');
      return null;
    }
  }

  Future<bool> callService(
    String domain,
    String service, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      await send({
        'type': 'call_service',
        'domain': domain,
        'service': service,
        'service_data': data ?? const {},
      });

      return true;
    } catch (error) {
      debugPrint('ha: call_service $domain.$service failed: $error');

      return false;
    }
  }

  Future<Map<String, dynamic>> fetchLovelace(String? urlPath) async {
    final result = await send({
      'type': 'lovelace/config',
      'url_path': (urlPath == null || urlPath.isEmpty) ? null : urlPath,
      'force': false,
    });

    return (result as Map).cast<String, dynamic>();
  }
}
