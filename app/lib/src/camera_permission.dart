/// camera_permission.dart — telling a refused camera from a broken one.
///
/// These are different problems and need different words. A camera that is
/// unplugged or busy is fixed where it stands; a permission the user
/// declined is fixed in a settings panel they have to be told how to find.
///
/// On macOS the distinction is not cosmetic. The system asks once. After
/// "Don't Allow" every later request returns denied without showing
/// anything, so an app that offers to "try again" is lying to the person
/// reading it. The only honest offer is to open the page where the switch
/// is. Reported by the owner on 2026-11-04, who declined the prompt by
/// mistake and had to find that page unaided.
library;

/// Whether [failure] — a platform error code or message — means the user
/// refused the camera, rather than the camera being absent or busy.
///
/// Deliberately conservative. A false positive sends someone to a setting
/// that is already correct, which teaches them that the app's advice is
/// noise; a false negative only costs the button.
bool isPermissionDenied(String failure) {
  final text = failure.toLowerCase();

  // `initialization_timeout` is excluded on purpose. macOS reports it when
  // the UI isolate is too busy to let the camera start — the bug fixed in
  // 55d06ff — and also when a camera is simply slow to wake. It is not a
  // permission problem, and it is the error a DeadDrop user is most likely
  // to see, so misreading it would make this advice worse than useless.
  if (text.contains('timeout')) return false;

  const markers = [
    'cameraaccessdenied',
    'avfoundationerrordomain',
    'access denied',
    'permission denied',
    'not authorized',
    'not authorised',
    'access was not granted',
    'denied by the user',
  ];
  return markers.any(text.contains);
}

/// Whether this platform has one place a person can be sent to.
///
/// Linux does not. Granting a camera there is file permissions on
/// `/dev/video*`, or a Flatpak portal, or adding the user to a group — and
/// a button that opens nothing is worse than no button at all.
bool canOpenCameraSettings(String platform) =>
    platform == 'macos' || platform == 'windows';

/// Where the camera switch lives, in the words on the person's own screen.
///
/// Written for someone who has never opened these panels. The macOS line
/// says the system will not ask again, because that is the fact that
/// explains why the app cannot simply retry.
String cameraSettingsHint(String platform) {
  switch (platform) {
    case 'macos':
      return 'macOS will not ask again, so the camera has to be switched '
          'on by hand: System Settings → Privacy & Security → Camera, '
          'then turn on DeadDrop.';
    case 'windows':
      return 'The camera has to be switched on by hand: '
          'Settings → Privacy & security → Camera, then allow desktop '
          'apps to use it.';
    case 'linux':
      return 'DeadDrop could not reach the camera. Check that your user '
          'can read the camera device, and that nothing else is using it.';
    default:
      return 'DeadDrop needs permission to use the camera. Grant it in '
          'your system settings and try again.';
  }
}

/// The command that opens the camera privacy page, or null where there is
/// no single page to open.
///
/// Returned as data rather than run here so the decision can be tested
/// without launching anything.
({String executable, List<String> arguments})? cameraSettingsCommand(
  String platform,
) {
  switch (platform) {
    case 'macos':
      return (
        executable: 'open',
        arguments: [
          'x-apple.systempreferences:com.apple.preference.security'
              '?Privacy_Camera',
        ],
      );
    case 'windows':
      return (
        executable: 'cmd',
        arguments: ['/c', 'start', 'ms-settings:privacy-webcam'],
      );
    default:
      return null;
  }
}
