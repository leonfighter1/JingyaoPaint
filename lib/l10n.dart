import 'package:flutter/widgets.dart';

import 'device.dart';
import 'drawing/stroke.dart';
import 'settings.dart' show MusicMode;

/// All user-facing text, in Simplified Chinese (default) and English.
class S {
  const S(this.languageCode);

  final String languageCode;

  static S of(BuildContext context) =>
      S(Localizations.localeOf(context).languageCode);

  bool get _zh => languageCode != 'en';
  String _t(String zh, String en) => _zh ? zh : en;

  /// What the system knows the app as (share sheets, file pickers, the
  /// browser tab).
  String get appName => _t('快乐涂鸦', 'JoyPainting');

  /// The title over the canvas: the kid's own board.
  String boardTitle(String kidName) => kidName.isEmpty
      ? _t('我的画板', 'My Drawing Board')
      : _t('$kidName的画板', "$kidName's Drawing Board");

  /// Texts that differ by device ask this.
  Device get _device => Device.current;

  // First start
  String get welcomeTitle => _t('欢迎来画画！', 'Welcome!');
  String get welcomeBody => _t('选一种语言和喜欢的主题，再写下小画家的名字。',
      "Pick a language and a theme you like, then tell us the little artist's name.");
  String get kidNameLabel => _t('小画家的名字', "Little artist's name");
  String get kidNameHint => _t('例如：靖瑶', 'For example: Jingyao');
  String get startDrawing => _t('开始画画', 'Start drawing');

  // Painting names
  String defaultPaintingName(int n) => _t('我的画作 $n', 'My painting $n');
  String get rename => _t('重命名', 'Rename');
  String get renameTitle => _t('给画作起个名字', 'Name this painting');
  String get nameLabel => _t('名字', 'Name');
  String get save => _t('保存', 'Save');
  String renamed(String name) => _t('已改名为“$name”', 'Renamed to "$name"');

  // Kids
  String get kids => _t('小画家', 'Kids');
  String get addKid => _t('添加小画家', 'Add a kid');
  String get changeKidName => _t('改名字', 'Change name');
  String get noKidName => _t('（还没有名字）', '(no name yet)');
  String get usingNow => _t('正在画', 'Drawing now');
  String deleteKidTitle(String name) =>
      _t('删除“$name”和TA的所有画作？', 'Delete $name and all of their paintings?');
  String get deleteKidBody =>
      _t('删除后无法恢复。', "This can't be undone.");
  String switchedTo(String name) =>
      _t('现在是 $name 在画画', 'Now drawing: $name');
  String get resetApp => _t('重置整个应用', 'Reset the whole app');
  String get resetAppBody => _t(
      '会删除所有小画家、画作、上传的音乐和设置，回到第一次打开的样子。无法恢复。',
      "Deletes every kid, painting, added music and setting, back to a fresh start. This can't be undone.");
  String get reset => _t('重置', 'Reset');

  // Grown-up check
  String get parentCheck => _t('请家长来回答', 'Grown-ups only');
  String get parentCheckHint =>
      _t('答对这道题才能继续：', 'Answer this to continue:');
  String get answer => _t('答案', 'Answer');
  String get wrongAnswer =>
      _t('不对哦，换一道题再试试', 'Not quite. Try this one.');

  // Music play order
  String get musicPlayOrder => _t('播放方式', 'Play order');
  String musicModeName(MusicMode mode) => switch (mode) {
        MusicMode.repeatOne => _t('单曲循环', 'Repeat one'),
        MusicMode.sequence => _t('顺序播放', 'In order'),
        MusicMode.shuffle => _t('随机播放', 'Shuffle'),
      };

  // Sending on the web
  String get sendHintWeb => _t(
      '会打开分享菜单，选“邮件”就能把画作当附件发出去。',
      'Opens the share menu. Choose Mail to send the painting as an attachment.');
  String mailSubject(String name) =>
      _t('我的画作：$name', 'My painting: $name');
  String mailBody(String file) => _t(
      '给你看我画的画！附件是“$file”。',
      'Here is my painting! "$file" is attached.');
  String mailFallback(String file) => _t(
      '已下载“$file”，并打开了一封新邮件。把这个文件添加到邮件附件里就可以发送了。',
      'Downloaded "$file" and opened a new email. Attach that file to it and send.');

  /// Which version this is, for About.
  String get runsOn => switch (_device.kind) {
        DeviceKind.android => _t('Android 版', 'for Android'),
        DeviceKind.apple => _t('iPhone 和 iPad 版', 'for iPhone and iPad'),
        DeviceKind.web => _device.browser == null
            ? _t('网页版', 'web version')
            : _t('网页版 · ${_device.browser}', 'web version · ${_device.browser}'),
        DeviceKind.desktop => _t('电脑版', 'for computers'),
      };

  // Navigation
  String get navCanvas => _t('画板', 'Canvas');
  String get navGallery => _t('我的画作', 'My Paintings');
  String get navSettings => _t('设置', 'Settings');

  // Canvas actions
  String get undo => _t('撤销', 'Undo');
  String get redo => _t('重做', 'Redo');
  String get newPainting => _t('新建画作', 'New painting');
  String get more => _t('更多', 'More');
  String get clear => _t('清空画布', 'Clear canvas');
  String get saveToGallery => switch (_device.kind) {
        DeviceKind.apple => _t('保存到“照片”', 'Save to Photos'),
        DeviceKind.web => downloadImage,
        DeviceKind.desktop => _t('保存到“图片”文件夹', 'Save to Pictures'),
        DeviceKind.android => _t('保存到相册', 'Save to gallery'),
      };
  String get downloadImage => _t('下载图片', 'Download image');
  String get clearTitle => _t('清空画布？', 'Clear canvas?');
  String get clearBody =>
      _t('清空后可以用“撤销”找回。', 'You can bring it back with Undo.');
  String get cancel => _t('取消', 'Cancel');
  String get confirm => _t('确定', 'OK');
  String get delete => _t('删除', 'Delete');
  String get savedToGallery => switch (_device.kind) {
        DeviceKind.apple => _t('已保存到“照片”的“快乐涂鸦”相簿',
            'Saved to Photos (album: JoyPainting)'),
        DeviceKind.desktop => _t('已保存到“图片”文件夹（JoyPainting）',
            'Saved to Pictures (folder: JoyPainting)'),
        _ => _t('已保存到相册（快乐涂鸦）',
            'Saved to gallery (album: JoyPainting)'),
      };
  String downloaded(String file) => _t('已下载 $file', 'Downloaded $file');
  String saveFailed(Object e) => _t('保存失败：$e', 'Save failed: $e');
  String autosaveFailed(Object e) =>
      _t('自动保存失败：$e', 'Autosave failed: $e');
  String get newPaintingStarted => _t('已新建画作', 'Started a new painting');
  String get openFailed => _t('无法打开这幅画', "Couldn't open this painting");

  // Tools
  String get tools => _t('画笔', 'Brushes');
  String get colors => _t('颜料', 'Colors');
  String get brushSize => _t('笔刷大小', 'Brush size');
  String get pickColor => _t('选择颜色', 'Pick a color');
  String get moreColors => _t('更多颜色', 'More colors');
  String get useColor => _t('使用', 'Use');
  String brushName(BrushType b) => switch (b) {
        BrushType.pen => _t('钢笔', 'Pen'),
        BrushType.pencil => _t('铅笔', 'Pencil'),
        BrushType.marker => _t('马克笔', 'Marker'),
        BrushType.highlighter => _t('荧光笔', 'Highlighter'),
        BrushType.spray => _t('喷枪', 'Spray'),
        BrushType.rainbow => _t('彩虹笔', 'Rainbow'),
        BrushType.stamp => _t('印章', 'Stamps'),
        BrushType.text => _t('文字', 'Text'),
        BrushType.move => _t('选择移动', 'Move'),
        BrushType.eraser => _t('橡皮擦', 'Eraser'),
      };
  String stampName(StampShape s) => switch (s) {
        StampShape.heart => _t('爱心', 'Heart'),
        StampShape.star => _t('星星', 'Star'),
        StampShape.flower => _t('小花', 'Flower'),
      };
  // Move tool and eraser hints
  String get moveHint => _t(
      '点一下某一笔选中它；在空白处拖出方框，可以一次选中好几笔。拖动移动，'
          '拖右下角的圆钮放大缩小，拖上方的圆钮旋转。上方的按钮还能复制、改颜色和透明度。',
      'Tap a stroke to select it, or drag a box over empty paper to select '
          'several. Drag to move, drag the bottom-right knob to resize and the '
          'top knob to turn. The bar at the top copies, recolors and fades them.');

  // Move tool selection
  String selectedCount(int n) => _t('已选 $n 个', '$n selected');
  String get duplicate => _t('复制', 'Copy');
  String get makeBigger => _t('放大', 'Bigger');
  String get makeSmaller => _t('缩小', 'Smaller');
  String get turnLeft => _t('向左转', 'Turn left');
  String get turnRight => _t('向右转', 'Turn right');
  String get colorAndOpacity => _t('颜色和透明度', 'Color and opacity');
  String get deleteSelection => _t('删除选中的', 'Delete selected');
  String get rainbowKeepsColors =>
      _t('彩虹笔画的线会保留彩虹色，只改透明度。', 'Rainbow strokes keep their colors; only their opacity changes.');
  String get eraserHint => _t('橡皮擦是圆头的，长按画布可以看到擦除范围。',
      'The eraser has a round tip. Long-press the paper to see its size.');

  // Text tool
  String get textHint => _t('点画布添加文字 · 拖动文字移动 · 点文字修改',
      'Tap to add text · drag text to move · tap text to edit');
  String get addText => _t('添加文字', 'Add text');
  String get editText => _t('编辑文字', 'Edit text');
  String get textPlaceholder => _t('写点什么吧…', 'Type something…');
  String get bold => _t('加粗', 'Bold');
  String get italic => _t('斜体', 'Italic');
  String get underline => _t('下划线', 'Underline');
  String get strikethrough => _t('删除线', 'Strikethrough');
  String get alignLeft => _t('左对齐', 'Align left');
  String get alignCenter => _t('居中', 'Center');
  String get alignRight => _t('右对齐', 'Align right');
  String get bubble => _t('背景气泡', 'Bubble');
  String get fontSize => _t('字号', 'Size');
  String get done => _t('完成', 'Done');
  String get deleteText => _t('删除文字', 'Delete text');

  // Send, print and import
  String get send => _t('发送给别人', 'Send');
  String get print => _t('打印', 'Print');
  String get sendAs => _t('选择发送格式', 'Send as');
  String formatName(String format) => switch (format) {
        'png' => _t('图片（PNG）', 'Image (PNG)'),
        'jpg' => _t('图片（JPG）', 'Image (JPG)'),
        'pdf' => _t('PDF 文档', 'PDF document'),
        _ => _t('画作文件（可继续画）', 'Painting file (editable)'),
      };
  String formatHint(String format) => switch (format) {
        'png' => _t('清晰无损，适合收藏', 'Sharpest quality'),
        'jpg' => _t('文件更小，适合聊天发送', 'Smaller, good for chat apps'),
        'pdf' => _t('适合打印或发邮件', 'Good for printing or email'),
        _ => _t('对方装了快乐涂鸦，打开就能继续画',
            'Opens in JoyPainting to keep drawing'),
      };
  String get importPainting => _t('导入画作文件', 'Import painting file');
  String get imported => _t('已导入画作，可以继续画啦', 'Painting imported. Keep drawing!');
  String get notAPainting =>
      _t('这个文件不是快乐涂鸦的画作', "This file isn't a JoyPainting painting");
  String sendFailed(Object e) => _t('发送失败：$e', 'Sending failed: $e');
  String printFailed(Object e) => _t('打印失败：$e', 'Printing failed: $e');

  String get shapes => _t('形状', 'Shapes');
  String shapeName(ShapeKind? s) => switch (s) {
        null => _t('自由画', 'Freehand'),
        ShapeKind.line => _t('直线', 'Line'),
        ShapeKind.arrow => _t('箭头', 'Arrow'),
        ShapeKind.rectangle => _t('矩形', 'Rectangle'),
        ShapeKind.ellipse => _t('圆形', 'Circle'),
        ShapeKind.triangle => _t('三角形', 'Triangle'),
        ShapeKind.star => _t('星形', 'Star shape'),
        ShapeKind.heart => _t('心形', 'Heart shape'),
      };
  String get fillShape => _t('填充', 'Fill');
  String get eraserRange => _t('橡皮擦范围', 'Eraser area');
  String get opacity => _t('不透明度', 'Opacity');
  // Painting actions (top right)
  String get savePainting => _t('保存画作', 'Save painting');
  String get paintingSaved => _t('已保存到“我的画作”', 'Saved to My Paintings');
  String get deletePainting => _t('删除这幅画', 'Delete this painting');
  String get paintingDeleted =>
      _t('已删除，给你一张新画纸', 'Deleted. Here is a fresh page');

  // ⋮ menu sections
  String get menuShare => _t('分享', 'Share');
  String get menuView => _t('视图', 'View');
  String get menuPaper => _t('画纸', 'Paper');
  String get menuPainting => _t('画作', 'Painting');
  String get menuSound => _t('声音', 'Sound');

  // Background music
  String get backgroundMusic => _t('背景音乐', 'Background music');
  String get playMusic => _t('播放背景音乐', 'Play background music');
  String get playMusicHint => _device.isWeb
      ? _t('画画时播放；切到别的网页时暂停。浏览器要先点一下屏幕才会出声。',
          'Plays while you draw and pauses in another tab. Browsers need one tap on the page before sound plays.')
      : _t('画画时播放，切到后台会自动暂停',
          'Plays while you draw; pauses when the app is in the background');
  String get musicVolume => _t('音量', 'Volume');
  String get musicTrack => _t('选择音乐', 'Music');
  String get uploadMusic => _t('上传本地音乐', 'Add music from this device');
  String musicFormats({required bool apple}) => apple
      ? _t('支持 MP3、M4A/AAC、WAV、AIFF、FLAC 等常见格式',
          'MP3, M4A/AAC, WAV, AIFF, FLAC and other common formats')
      : _t('支持 MP3、M4A/AAC、WAV、OGG/Opus、FLAC、MIDI 等常见格式',
          'MP3, M4A/AAC, WAV, OGG/Opus, FLAC, MIDI and other common formats');
  String get builtInMusic => _t('自带', 'Built-in');
  String get myMusic => _t('我上传的', 'Added by me');
  String trackName(String id) => switch (id) {
        'sunny' => _t('阳光散步', 'Sunny Walk'),
        'twinkle' => _t('小星星摇篮曲', 'Twinkle Lullaby'),
        _ => id,
      };
  String musicAdded(String name) => _t('已添加“$name”', 'Added "$name"');
  String get musicAddFailed =>
      _t('这个文件放不了，换一首试试', "That file can't be played. Try another one");
  String deleteMusicTitle(String name) => _t('删除“$name”？', 'Delete "$name"?');
  String get musicPlayFailed => _t('背景音乐播放失败，已换回自带音乐',
      "Couldn't play the music. Switched back to a built-in track");

  // Print preview
  String get printPreview => _t('打印预览', 'Print preview');
  String get closePrint => _t('关闭', 'Close');
  String get printNow => _t('打印', 'Print');
  String get printHint => switch (_device.kind) {
        DeviceKind.android => _t(
            '点“打印”会打开手机的打印界面。想回来时，按返回键，或从屏幕左边缘向右滑一下。',
            "Print opens the phone's print screen. To come back, press Back or swipe in from the left edge of the screen."),
        DeviceKind.apple => _t(
            '点“打印”会打开打印界面。不想打印了，点左上角的“取消”就能回来。',
            'Print opens the print options. To come back without printing, tap Cancel at the top left.'),
        DeviceKind.web => _t(
            '点“打印”会打开浏览器的打印窗口。不想打印了，点“取消”就能回来。',
            "Print opens the browser's print window. To come back without printing, click Cancel."),
        DeviceKind.desktop => _t(
            '点“打印”会打开电脑的打印窗口。不想打印了，点“取消”就能回来。',
            "Print opens the computer's print window. To come back without printing, click Cancel."),
      };
  String get printSent => _t('已交给打印机', 'Sent to the printer');

  // Tools drawer
  String get toolsButton => _t('画笔 · 颜色', 'Brushes · Colors');
  String get toolsTitle => _t('画笔与颜色', 'Brushes & colors');
  String get openTools => _t('打开画笔和颜色', 'Open brushes and colors');
  String get closeTools => _t('收起画笔和颜色', 'Close brushes and colors');

  // Zoom
  String get zoomIn => _t('放大画布', 'Zoom in');
  String get zoomOut => _t('缩小画布', 'Zoom out');
  String get fitScreen => _t('适应屏幕', 'Fit to screen');
  String get pinchHint => _device.desktopOs
      ? _t('双指捏合可以放大缩小画布，双指拖动可以移动画布；用鼠标时，滚动滚轮也能缩放',
          'Pinch with two fingers to zoom, drag with two fingers to move; with a mouse, scroll the wheel to zoom')
      : _t('双指捏合可以放大缩小画布，双指拖动可以移动画布',
          'Pinch with two fingers to zoom, drag with two fingers to move');
  String percent(double v) => '${(v * 100).round()}%';
  String get mirror => _t('对称绘画', 'Mirror drawing');
  String get paperColor => _t('画纸颜色', 'Paper color');
  List<String> get paperNames => _zh
      ? const ['纯白', '奶油', '樱花', '天空', '薄荷', '薰衣草']
      : const ['White', 'Cream', 'Blossom', 'Sky', 'Mint', 'Lavender'];
  String colorLabel(Color c) {
    final hex = (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '${_t('颜色', 'Color')} #${hex.toUpperCase()}';
  }
  String get canvasLabel => _t('画布，用手指或手写笔画画', 'Canvas. Draw with a finger or stylus.');

  // Gallery
  String get allYears => _t('全部', 'All');
  String year(int y) => _t('$y年', '$y');
  String get emptyGallery =>
      _t('还没有画作，去画一幅吧！', 'No paintings yet. Go draw one!');
  String get emptyYear => _t('这一年没有画作', 'No paintings this year');
  String created(String date) => _t('创建于 $date', 'Created $date');
  String updated(String date) => _t('修改于 $date', 'Edited $date');
  String get editing => _t('正在画', 'Editing');
  String get continuePainting => _t('继续画', 'Continue');
  String get deleteTitle => _t('删除这幅画？', 'Delete this painting?');
  String get deleteBody =>
      _t('删除后无法恢复。', "Deleted paintings can't be recovered.");
  String strokeCount(int n) => _t('$n 笔', n == 1 ? '1 stroke' : '$n strokes');

  // Settings
  String get theme => _t('主题', 'Theme');
  String get font => _t('字体', 'Font');
  String get fontSample => _t('快乐涂鸦 Aa', 'JoyPainting Aa');
  String get licenses => _t('开源许可', 'Open-source licenses');
  String get language => _t('语言', 'Language');
  String get about => _t('关于', 'About');
  String get aboutBody => _device.isWeb
      ? _t(
          '画作会自动保存在这个浏览器里，只有这台设备能看到。清除浏览器的网站数据会把它们删掉，可以用“发送给别人 → 画作文件”备份。',
          "Paintings save automatically in this browser, on this device only. Clearing the browser's website data deletes them; back them up with Send → Painting file.")
      : _t(
          '画作会自动保存在这台设备上，可以在“我的画作”中继续编辑。',
          'Paintings save automatically on this device. Continue any of them from My Paintings.');
  String version(String v) => _t('版本 $v', 'Version $v');
}

/// Formats a date as `2026-10-24 14:30` in both languages.
String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
