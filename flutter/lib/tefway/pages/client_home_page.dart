// Client — the assisted customer's screen.
//
// No way out to another computer, no editable permanent password, no
// unattended-access settings, no installation card. The customer sees the ID
// they read to support, the real availability of the service, and whether a
// session is running right now. Consent itself stays in the approval window
// the core opens, which requires a local click for every new session.
//
// Platform conditions live behind the Central de Diagnósticos in the header;
// the main surface only carries a blocking core error, in the flow it affects.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/tefway/design.dart';
import 'package:flutter_hbb/tefway/diagnostics.dart';
import 'package:flutter_hbb/tefway/notices.dart';
import 'package:flutter_hbb/tefway/strings.dart';
import 'package:flutter_hbb/tefway/widgets.dart';
import 'package:window_manager/window_manager.dart';

class TefwayClientHomePage extends StatefulWidget {
  const TefwayClientHomePage({super.key});

  @override
  State<TefwayClientHomePage> createState() => _TefwayClientHomePageState();
}

class _TefwayClientHomePageState extends State<TefwayClientHomePage> {
  /// Largura da janela do cliente, em pixeis lógicos.
  static const double _windowWidth = 400;
  /// Altura mínima segura da janela do cliente, em pixeis lógicos.
  /// Garante que todo o conteúdo inicial caiba sem scroll vertical.
  static const double _minWindowHeight = 500;
  /// Margem entre a janela e a borda do display mais alto.
  static const _screenMargin = 48.0;
  /// Com a barra de título oculta, o retângulo externo da janela no Windows
  /// excede a área útil do Flutter (moldura e sombra nas laterais e na base).
  static const Size _windowFrame = Size(16.0, 9.0);

  Timer? _timer;
  SvcStatus _svcStatus = SvcStatus.notReady;
  int _connectionCount = 0;
  String _id = '';
  String _version = '';
  String _coreError = '';

  /// Chave do card de conteúdo, usada apenas para medir a altura quando um
  /// aviso de erro aparece e a janela precisa crescer.
  final GlobalKey _cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _id = gFFI.serverModel.serverId.text;
    _loadVersion();
    _timer = periodic_immediate(const Duration(seconds: 1), _refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _sizeWindow(centerOnScreen: true);
      } catch (e) {
        debugPrint('Tefway: failed to size the client window: $e');
      }
    });
  }

  /// Ajusta a janela nativa ao tamanho mínimo seguro (ou maior, se necessário
  /// para acomodar um aviso de erro). Nunca reduz abaixo da altura mínima, para
  /// evitar scroll vertical no estado normal.
  Future<void> _sizeWindow({
    bool centerOnScreen = false,
    bool growForError = false,
  }) async {
    if (!mounted) return;

    double contentHeight = _minWindowHeight;

    if (growForError && _coreError.isNotEmpty) {
      final renderObject = _cardKey.currentContext?.findRenderObject();
      if (renderObject is RenderBox) {
        final measured = renderObject.size.height +
            2 * TefwaySpacing.md +
            _windowFrame.height;
        if (measured > contentHeight) {
          contentHeight = measured;
        }
      }
    }

    final height = await _fitToScreen(contentHeight);
    final size = Size(_windowWidth + _windowFrame.width,
        height + _windowFrame.height);
    try {
      await windowManager.setSize(size);
      if (centerOnScreen) {
        await windowManager.center();
      }
    } catch (e) {
      debugPrint('Tefway: failed to size the client window: $e');
    }
  }

  /// Limita a altura à área útil do display mais alto, deixando a margem de
  // tela; não altera quando o conteúdo já cabe.
  Future<double> _fitToScreen(double height) async {
    try {
      final displays = jsonDecode(bind.mainGetDisplays()) as List<dynamic>;
      var tallest = 0.0;
      for (final display in displays) {
        final h = (display['h'] as num).toDouble();
        if (h > tallest) tallest = h;
      }
      final available = tallest - _screenMargin;
      if (available > 0 && available < height) {
        return available;
      }
    } catch (e) {
      debugPrint('Tefway: failed to read the display size: $e');
    }
    return height;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await bind.mainGetVersion();
      if (!mounted) return;
      setState(() => _version = version);
    } catch (e) {
      debugPrint('Tefway: failed to read app version: $e');
    }
  }

  Future<void> _refresh() async {
    await gFFI.serverModel.fetchID();
    var status = _svcStatus;
    var count = _connectionCount;
    try {
      final raw =
          jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
      final statusNum = raw['status_num'] as int?;
      if (statusNum == null) {
        status = SvcStatus.notReady;
      } else if (statusNum == 0) {
        status = SvcStatus.connecting;
      } else if (statusNum == 1) {
        status = SvcStatus.ready;
      } else {
        status = SvcStatus.notReady;
      }
      count = (raw['video_conn_count'] as int?) ?? 0;
    } catch (e) {
      status = SvcStatus.notReady;
    }
    final coreError = await bind.mainGetError();
    if (!mounted) return;
    final errorChanged = coreError != _coreError;
    setState(() {
      _svcStatus = status;
      _connectionCount = count;
      _id = gFFI.serverModel.serverId.text;
      _coreError = coreError;
    });
    if (errorChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _sizeWindow(centerOnScreen: false, growForError: true);
        } catch (e) {
          debugPrint('Tefway: failed to resize the client window for the error notice: $e');
        }
      });
    }
  }

  void _copyId() {
    final raw = trimID(_id);
    if (raw.isEmpty) return;
    Clipboard.setData(ClipboardData(text: raw));
    showToast(TefwayStrings.copiedId);
  }

  Widget _availability() {
    if (_connectionCount > 0) {
      return TefwayStatusIndicator(
        status: TefwayStatus.attention,
        label: TefwayStrings.clientSessionActive,
        detail: TefwayStrings.clientSessionDetail(_connectionCount),
      );
    }
    switch (_svcStatus) {
      case SvcStatus.ready:
        return const TefwayStatusIndicator(
          status: TefwayStatus.positive,
          label: TefwayStrings.clientAwaiting,
          detail: TefwayStrings.clientAwaitingDetail,
        );
      case SvcStatus.connecting:
        return const TefwayStatusIndicator(
          status: TefwayStatus.busy,
          label: TefwayStrings.clientConnecting,
          detail: TefwayStrings.clientConnectingDetail,
        );
      case SvcStatus.notReady:
        return const TefwayStatusIndicator(
          status: TefwayStatus.critical,
          label: TefwayStrings.clientServerDown,
          detail: TefwayStrings.clientServerDownDetail,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = tefwayDiagnostics(
      coreError: _coreError,
      onRetryCore: _refresh,
    );
    return TefwayAppShell(
      maxWidth: 420,
      padding: const EdgeInsets.all(TefwaySpacing.md),
      child: Container(
        key: _cardKey,
        child: TefwaySurfaceCard(
          padding: const EdgeInsets.all(TefwaySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TefwayBrandHeader(
                subtitle: TefwayStrings.clientSubtitle,
                trailing: TefwayDiagnosticsButton(diagnostics: diagnostics),
              ),
              const SizedBox(height: TefwaySpacing.md),
              const Divider(height: 1, color: TefwayColors.border),
              const SizedBox(height: TefwaySpacing.lg),
              TefwayDeviceIdCard(
                label: TefwayStrings.clientIdLabel,
                id: formatID(trimID(_id)),
                onCopy: _copyId,
              ),
              const SizedBox(height: TefwaySpacing.lg),
              Container(
                padding: const EdgeInsets.all(TefwaySpacing.md),
                decoration: BoxDecoration(
                  color: TefwayColors.inputFill,
                  borderRadius: TefwayRadius.mdAll,
                  border: Border.all(color: TefwayColors.border, width: 1),
                ),
                child: _availability(),
              ),
              if (_connectionCount > 0) ...[
                const SizedBox(height: TefwaySpacing.sm),
                Text(TefwayStrings.clientSessionsHint,
                    style: TefwayTextStyles.caption),
              ],
              const SizedBox(height: TefwaySpacing.md),
              const Text(
                TefwayStrings.clientGuidance,
                textAlign: TextAlign.center,
                style: TefwayTextStyles.body,
              ),
              const SizedBox(height: TefwaySpacing.xs),
              const Text(
                TefwayStrings.clientNoOutgoing,
                textAlign: TextAlign.center,
                style: TefwayTextStyles.caption,
              ),
              // A blocking failure stays visible where it happens, even though
              // the diagnostics panel also lists it.
              if (_coreError.isNotEmpty) ...[
                const SizedBox(height: TefwaySpacing.md),
                TefwayCoreErrorNotice(message: _coreError, onRetry: _refresh),
              ],
              const SizedBox(height: TefwaySpacing.md),
              TefwaySupportFooter(version: _version),
            ],
          ),
        ),
      ),
    );
  }
}
