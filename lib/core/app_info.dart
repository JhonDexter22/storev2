/// The app's name and version, where the app itself shows them.
///
/// The version is written out rather than read from the platform, which would
/// mean another plugin for one line of text. A test holds it to `pubspec.yaml`
/// so the two cannot drift apart.
class AppInfo {
  AppInfo._();

  static const name = 'BasePoint';
  static const version = '1.0.0';
}
