import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/tefway/consent.dart';
import 'package:flutter_hbb/tefway/strings.dart';

const _capabilities = <TefwayCapability>[
  TefwayCapability(
    key: 'keyboard',
    label: TefwayStrings.capKeyboard,
    icon: Icons.keyboard_outlined,
    enabled: true,
  ),
  TefwayCapability(
    key: 'clipboard',
    label: TefwayStrings.capClipboard,
    icon: Icons.content_paste_rounded,
    enabled: true,
  ),
  TefwayCapability(
    key: 'audio',
    label: TefwayStrings.capAudio,
    icon: Icons.volume_up_outlined,
    enabled: true,
  ),
  TefwayCapability(
    key: 'file',
    label: TefwayStrings.capFile,
    icon: Icons.folder_outlined,
    enabled: true,
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(440, 620),
  double textScale = 1.0,
  double devicePixelRatio = 1.0,
  bool identityVerified = false,
  String peerName = 'Técnico Tefway',
  List<TefwayCapability> capabilities = _capabilities,
  VoidCallback? onAllow,
  VoidCallback? onRefuse,
  VoidCallback? onAllowAndElevate,
  String? elevationUnavailableReason,
  void Function(String key, bool enabled)? onToggle,
}) async {
  tester.view.physicalSize = size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TefwayConsentCard(
        peerName: peerName,
        peerId: '123456789',
        identityVerified: identityVerified,
        capabilities: capabilities,
        onToggle: onToggle ?? (_, __) {},
        onAllow: onAllow ?? () {},
        onRefuse: onRefuse ?? () {},
        onAllowAndElevate: onAllowAndElevate,
        elevationUnavailableReason: elevationUnavailableReason,
      ),
    ),
  ));
}

void main() {
  testWidgets('all three actions are present, visible and independent',
      (tester) async {
    var allow = 0;
    var refuse = 0;
    var elevate = 0;
    await _pump(
      tester,
      size: const Size(300, 490),
      onAllow: () => allow++,
      onRefuse: () => refuse++,
      onAllowAndElevate: () => elevate++,
    );

    expect(tester.takeException(), isNull);
    expect(find.text(TefwayStrings.consentRefuse), findsOneWidget);
    expect(find.text(TefwayStrings.consentAllow), findsOneWidget);
    expect(find.text(TefwayStrings.consentAllowElevate), findsOneWidget);

    await tester.tap(find.text(TefwayStrings.consentAllow));
    await tester.pump();
    expect(allow, 1);
    expect(refuse, 0);
    expect(elevate, 0);

    await tester.tap(find.text(TefwayStrings.consentRefuse));
    await tester.pump();
    expect(refuse, 1);

    await tester.tap(find.text(TefwayStrings.consentAllowElevate));
    await tester.pump();
    expect(elevate, 1);
    expect(allow, 1, reason: 'elevated must not be routed through allow');

    for (final label in [
      TefwayStrings.consentRefuse,
      TefwayStrings.consentAllow,
      TefwayStrings.consentAllowElevate,
    ]) {
      final rect = tester.getRect(find.text(label));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(490));
    }
  });

  testWidgets('elevation unavailable stays visible, disabled and explained',
      (tester) async {
    const reason = 'Acesso elevado indisponível nesta instalação.';
    await _pump(tester, elevationUnavailableReason: reason);

    final button = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text(TefwayStrings.consentAllowElevate),
      matching: find.byType(OutlinedButton),
    ));
    expect(button.onPressed, isNull);
    expect(find.text(reason), findsOneWidget);
    expect(find.byTooltip(reason), findsOneWidget);
  });

  testWidgets('elevation available is enabled and not merged with allow',
      (tester) async {
    var allow = 0;
    var elevate = 0;
    await _pump(
      tester,
      onAllow: () => allow++,
      onAllowAndElevate: () => elevate++,
    );

    final button = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text(TefwayStrings.consentAllowElevate),
      matching: find.byType(OutlinedButton),
    ));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text(TefwayStrings.consentAllowElevate));
    await tester.pump();
    expect(elevate, 1);
    expect(allow, 0);
  });

  testWidgets('a declared identity is never presented as verified',
      (tester) async {
    await _pump(tester, identityVerified: false);
    expect(find.text(TefwayStrings.consentIdentityUnverified), findsOneWidget);
    expect(find.text(TefwayStrings.consentIdentityVerified), findsNothing);
    expect(find.text(TefwayStrings.consentIdentityUnverifiedDetail),
        findsOneWidget);
  });

  testWidgets('a core-verified identity is presented as verified',
      (tester) async {
    await _pump(tester, identityVerified: true);
    expect(find.text(TefwayStrings.consentIdentityVerified), findsOneWidget);
    expect(find.text(TefwayStrings.consentIdentityUnverified), findsNothing);
  });

  testWidgets('permission switches call the real core callback',
      (tester) async {
    String? changedKey;
    bool? changedValue;
    await _pump(
      tester,
      size: const Size(440, 620),
      onToggle: (key, enabled) {
        changedKey = key;
        changedValue = enabled;
      },
    );

    final firstSwitch = find.byType(Switch).first;
    await tester.ensureVisible(firstSwitch);
    await tester.tap(firstSwitch);
    await tester.pump();

    expect(changedKey, 'keyboard');
    expect(changedValue, isFalse);
  });

  testWidgets('layout survives the required viewports and text scales',
      (tester) async {
    const sizes = [
      Size(300, 490),
      Size(360, 560),
      Size(440, 620),
      Size(480, 680),
      Size(1280, 720),
      Size(1366, 768),
      Size(1920, 1080),
    ];
    const scales = [1.0, 1.25, 1.5];
    const dprs = [1.0, 1.25, 1.5];

    for (final size in sizes) {
      for (final scale in scales) {
        for (final dpr in dprs) {
          await _pump(
              tester, size: size, textScale: scale, devicePixelRatio: dpr);
          expect(tester.takeException(), isNull,
              reason: 'overflow at $size, text scale $scale, dpr $dpr');
        }
      }
    }
  });

  testWidgets('long names and every permission state do not overflow',
      (tester) async {
    final disabled = _capabilities
        .map((c) => TefwayCapability(
              key: c.key,
              label: c.label,
              icon: c.icon,
              enabled: false,
            ))
        .toList();
    for (final capabilities in [_capabilities, disabled]) {
      await _pump(
        tester,
        size: const Size(300, 490),
        textScale: 1.5,
        peerName:
            'Técnico de Suporte Corporativo com Nome Muito Longo da Equipe de Infraestrutura',
        capabilities: capabilities,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the footer stays reachable with a long permission list',
      (tester) async {
    final many = List.generate(
      14,
      (i) => TefwayCapability(
        key: 'permission_$i',
        label: 'Permissão adicional $i com um rótulo razoavelmente longo',
        icon: Icons.tune_rounded,
        enabled: i.isEven,
      ),
    );
    await _pump(
      tester,
      size: const Size(300, 490),
      capabilities: many,
      onAllowAndElevate: () {},
    );

    expect(tester.takeException(), isNull);
    for (final label in [
      TefwayStrings.consentRefuse,
      TefwayStrings.consentAllow,
      TefwayStrings.consentAllowElevate,
    ]) {
      final rect = tester.getRect(find.text(label));
      expect(rect.bottom, lessThanOrEqualTo(490),
          reason: '$label scrolled out of the fixed footer');
    }
  });
}
