import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/tefway/diagnostics_model.dart';
import 'package:flutter_hbb/tefway/strings.dart';

List<TefwayDiagnostic> build({
  bool windows = false,
  bool linux = false,
  bool wayland = false,
  bool loginWayland = false,
  bool selinux = false,
  String coreError = '',
  bool withRetry = false,
}) {
  return buildTefwayDiagnostics(
    windows: windows,
    linux: linux,
    waylandSession: wayland,
    loginWayland: loginWayland,
    selinuxEnforcing: selinux,
    coreError: coreError,
    onRetryCore: withRetry ? () {} : null,
  );
}

void main() {
  test('a healthy machine has no diagnostics', () {
    expect(build(), isEmpty);
    expect(build(windows: false, linux: false), isEmpty);
    expect(worstSeverity(build()), isNull);
  });

  test('Wayland active is reported as information, never as a proven failure',
      () {
    final diagnostics = build(linux: true, wayland: true);
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.id, 'linux-wayland');
    expect(diagnostics.single.severity, TefwayDiagnosticSeverity.info);
    expect(diagnostics.single.blocksSession, isFalse);
  });

  test('SELinux enforcing is reported as a potential condition', () {
    final diagnostics = build(linux: true, selinux: true);
    expect(diagnostics.single.id, 'linux-selinux');
    expect(diagnostics.single.severity, TefwayDiagnosticSeverity.info);
    expect(diagnostics.single.blocksSession, isFalse);
  });

  test('Wayland session and login Wayland never duplicate the condition', () {
    final diagnostics = build(
      linux: true,
      wayland: true,
      loginWayland: true,
      selinux: true,
    );
    expect(diagnostics.map((d) => d.id).toSet().length, diagnostics.length);
    expect(diagnostics.where((d) => d.id.contains('wayland')), hasLength(1));
  });

  test('a real core error is critical, blocking and retryable', () {
    final diagnostics = build(coreError: 'connection closed', withRetry: true);
    expect(diagnostics.single.severity, TefwayDiagnosticSeverity.critical);
    expect(diagnostics.single.blocksSession, isTrue);
    expect(diagnostics.single.actionLabel, TefwayStrings.retry);
    expect(diagnostics.single.onAction, isNotNull);
    expect(worstSeverity(diagnostics), TefwayDiagnosticSeverity.critical);
  });

  test('a core error without a safe action offers no retry button', () {
    final diagnostics = build(coreError: 'connection closed');
    expect(diagnostics.single.actionLabel, isNull);
    expect(diagnostics.single.onAction, isNull);
  });

  test('the count follows the list and critical entries sort first', () {
    final diagnostics = build(
      windows: true,
      linux: true,
      wayland: true,
      selinux: true,
      coreError: 'boom',
      withRetry: true,
    );
    expect(diagnostics, hasLength(4));
    expect(diagnostics.first.severity, TefwayDiagnosticSeverity.critical);
    expect(diagnostics.map((d) => d.id).toSet().length, diagnostics.length);
    expect(worstSeverity(diagnostics), TefwayDiagnosticSeverity.critical);
  });

  test('identical conditions are emitted once', () {
    for (var i = 0; i < 3; i++) {
      final diagnostics = build(windows: true);
      expect(diagnostics, hasLength(1));
    }
  });
}
