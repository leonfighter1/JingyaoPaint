/// How sending from the browser went.
enum WebSendResult {
  /// The browser's share menu opened (Mail is one of its choices).
  shared,

  /// The share menu was closed without choosing anything.
  cancelled,

  /// The browser can't share files: the file was downloaded and a new
  /// email opened, to attach it to.
  downloadedForEmail,
}
