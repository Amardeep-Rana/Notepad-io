import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const NotepadApp());
}

const List<String> supportedExtensions = [
  'txt', 'java', 'py', 'c', 'cpp', 'h', 'js', 'dart', 'php', 'html', 'htm', 
  'css', 'rb', 'swift', 'json', 'xml', 'yaml', 'yml', 'ini', 'env', 'csv', 
  'md', 'log', 'rtf', 'bat', 'cmd', 'sh', 'srt', 'ass'
];

class NotepadApp extends StatelessWidget {
  const NotepadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Notepad IO',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF252525),
          elevation: 0,
          titleTextStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class NoteMetadata {
  final File file;
  final DateTime lastModified;
  final bool isLocked;

  NoteMetadata({
    required this.file,
    required this.lastModified,
    required this.isLocked,
  });
}

class SearchTextEditingController extends TextEditingController {
  String query = '';
  int activeIndex = -1;
  List<int> offsets = [];

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (query.isEmpty || offsets.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    final List<InlineSpan> children = [];
    final String text = this.text;
    int lastOffset = 0;

    for (int i = 0; i < offsets.length; i++) {
      final int start = offsets[i];
      if (start < lastOffset) continue;
      if (start > text.length) break;

      if (start > lastOffset) {
        children.add(TextSpan(text: text.substring(lastOffset, start)));
      }

      final int end = (start + query.length).clamp(0, text.length);
      final String matchText = text.substring(start, end);
      final bool isActive = i == activeIndex;
      
      children.add(TextSpan(
        text: matchText,
        style: style?.copyWith(
          backgroundColor: isActive 
            ? Colors.orange.withOpacity(0.8) 
            : Colors.yellow.withOpacity(0.4),
        ),
      ));

      lastOffset = end;
    }

    if (lastOffset < text.length) {
      children.add(TextSpan(text: text.substring(lastOffset)));
    }

    return TextSpan(style: style, children: children);
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NoteMetadata> _notes = [];
  final TextEditingController _fileNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  bool _isSupported(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return supportedExtensions.contains(ext);
  }

  Future<void> _loadFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final prefs = await SharedPreferences.getInstance();
    
    final List<FileSystemEntity> entities = await directory.list().toList();
    
    List<NoteMetadata> tempNotes = [];
    for (var entity in entities) {
      if (entity is File && _isSupported(entity.path)) {
        final stat = await entity.stat();
        final String? pass = prefs.getString('pass_${entity.path}');

        tempNotes.add(NoteMetadata(
          file: entity,
          lastModified: stat.modified,
          isLocked: (pass != null && pass.isNotEmpty),
        ));
      }
    }

    tempNotes.sort((a, b) => b.lastModified.compareTo(a.lastModified));

    setState(() {
      _notes = tempNotes;
    });
  }

  Route _createRoute(File file) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => NotepadEditor(file: file),
      transitionDuration: const Duration(milliseconds: 400),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slideTween = Tween(begin: const Offset(0.1, 0.0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        final fadeTween = Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn));
        final scaleTween = Tween(begin: 0.95, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic));

        return FadeTransition(
          opacity: animation.drive(fadeTween),
          child: ScaleTransition(
            scale: animation.drive(scaleTween),
            child: SlideTransition(
              position: animation.drive(slideTween),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Future<T?> _showAnimatedDialog<T>(BuildContext context, Widget child) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => child,
      transitionBuilder: (context, anim1, anim2, child) {
        final curveValue = Curves.easeOutBack.transform(anim1.value);
        return Transform.scale(
          scale: curveValue,
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _finalizeCreateFile() async {
    String name = _fileNameController.text.trim();
    if (name.isEmpty) return;
    
    if (!name.contains('.') || !_isSupported(name)) {
      if (!name.endsWith('.txt')) {
        name += '.txt';
      }
    }

    final directory = await getApplicationDocumentsDirectory();
    File newFile = File(p.join(directory.path, name));
    
    if (await newFile.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File already exists')),
      );
      return;
    }

    await newFile.writeAsString("");
    _fileNameController.clear();
    
    if (!mounted) return;
    Navigator.pop(context); 
    await Navigator.push(context, _createRoute(newFile));
    _loadFiles();
  }

  Future<void> _showCreateDialog() async {
    _fileNameController.clear();
    return _showAnimatedDialog<void>(
      context,
      StatefulBuilder(builder: (context, setState) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Center(
            child: Card(
              elevation: 8,
              color: const Color(0xFF1A1A1A).withOpacity(0.95),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Container(
                width: 280,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('New File Name', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _fileNameController,
                      autofocus: true,
                      style: TextStyle(color: primaryColor),
                      decoration: const InputDecoration(
                        hintText: "example.py, note.txt...",
                        isDense: true,
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.black26,
                      ),
                      onSubmitted: (_) => _finalizeCreateFile(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            ),
                            onPressed: _finalizeCreateFile,
                            child: const Text('Create'),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );

    if (result != null) {
      File file = File(result.files.single.path!);
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = p.basename(file.path);
      final String targetPath = p.join(directory.path, fileName);

      File localFile = await file.copy(targetPath);

      if (!mounted) return;
      await Navigator.push(context, _createRoute(localFile));
      _loadFiles();
    }
  }

  Future<bool> _verifyFileAccess(NoteMetadata note) async {
    if (!note.isLocked) return true;
    
    final prefs = await SharedPreferences.getInstance();
    String? password = prefs.getString('pass_${note.file.path}');
    
    if (password == null || password.isEmpty) return true;

    if (!mounted) return false;
    String? input = await _showPasswordDialog(context, title: "Enter PIN to Proceed");
    
    if (input == password) {
      return true;
    } else if (input != null) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong password')),
      );
    }
    return false;
  }

  Future<void> _handleFileTap(NoteMetadata note) async {
    if (await _verifyFileAccess(note)) {
      if (!mounted) return;
      await Navigator.push(context, _createRoute(note.file));
      _loadFiles();
    }
  }

  Future<String?> _showPasswordDialog(BuildContext context, {required String title}) async {
    String input = "";
    return _showAnimatedDialog<String>(
      context,
      StatefulBuilder(builder: (context, setState) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Center(
            child: Card(
              elevation: 8,
              color: const Color(0xFF1A1A1A).withOpacity(0.95),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Container(
                width: 280,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      autofocus: true,
                      style: TextStyle(color: primaryColor),
                      onChanged: (value) => input = value,
                      decoration: const InputDecoration(
                        hintText: "4-digit PIN",
                        isDense: true,
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.black26,
                        counterText: "",
                      ),
                      onSubmitted: (_) => Navigator.pop(context, input),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            ),
                            onPressed: () => Navigator.pop(context, input),
                            child: const Text('OK'),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _saveToLocal(NoteMetadata note) async {
    if (await _verifyFileAccess(note)) {
      try {
        final String fileName = p.basename(note.file.path);
        final bytes = await note.file.readAsBytes();
        
        // Use saveFile to let the user pick location and handle SAF permissions
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Select where to save the file',
          fileName: fileName,
          bytes: bytes,
        );

        if (outputFile != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File saved successfully')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _showFileOptions(NoteMetadata note) async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(context);
                if (await _verifyFileAccess(note)) {
                  String? newName = await _showRenameDialog(note.file);
                  if (newName != null && newName.trim().isNotEmpty) {
                    if (!newName.contains('.') || !_isSupported(newName)) {
                      final originalExt = p.extension(note.file.path);
                      newName += originalExt.isNotEmpty ? originalExt : '.txt';
                    }
                    
                    final newPath = p.join(note.file.parent.path, newName);

                    final prefs = await SharedPreferences.getInstance();
                    String? currentPass = prefs.getString('pass_${note.file.path}');

                    await note.file.rename(newPath);

                    if (currentPass != null) {
                      await prefs.setString('pass_$newPath', currentPass);
                      await prefs.remove('pass_${note.file.path}');
                    }

                    _loadFiles();
                  }
                }
              },
            ),
            ListTile(
              leading: Icon(note.isLocked ? Icons.lock_open : Icons.lock),
              title: Text(note.isLocked ? 'Remove Password' : 'Set Password'),
              onTap: () async {
                Navigator.pop(context);
                if (note.isLocked) {
                  final prefs = await SharedPreferences.getInstance();
                  String? currentPass = prefs.getString('pass_${note.file.path}');
                  if (!mounted) return;
                  String? verify = await _showPasswordDialog(context, title: "Verify Current PIN");
                  if (verify == currentPass) {
                    await prefs.remove('pass_${note.file.path}');
                    _loadFiles();
                  } else if (verify != null) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification failed')));
                  }
                } else {
                  if (!mounted) return;
                  String? pass = await _showPasswordDialog(context, title: "Set New 4-digit PIN");
                  if (pass != null && pass.length == 4) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('pass_${note.file.path}', pass);
                    _loadFiles();
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Save to Local'),
              onTap: () {
                Navigator.pop(context);
                _saveToLocal(note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                if (await _verifyFileAccess(note)) {
                  bool? confirm = await _showDeleteConfirmDialog(note.file);
                  if (confirm == true) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('pass_${note.file.path}');

                    await note.file.delete();
                    _loadFiles();
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showDeleteConfirmDialog(File file) async {
    String name = p.basename(file.path);
    return _showAnimatedDialog<bool>(
      context,
      Center(
        child: Card(
          elevation: 8,
          color: const Color(0xFF1A1A1A).withOpacity(0.95),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Delete File?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('Are you sure you want to delete "$name"?', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _showRenameDialog(File file) async {
    String name = p.basename(file.path);
    final TextEditingController renameController = TextEditingController(text: name);
    return _showAnimatedDialog<String>(
      context,
      StatefulBuilder(builder: (context, setState) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Center(
            child: Card(
              elevation: 8,
              color: const Color(0xFF1A1A1A).withOpacity(0.95),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Container(
                width: 280,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Rename File', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: renameController,
                      autofocus: true,
                      style: TextStyle(color: primaryColor),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.black26,
                      ),
                      onSubmitted: (_) => Navigator.pop(context, renameController.text),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            ),
                            onPressed: () => Navigator.pop(context, renameController.text),
                            child: const Text('OK'),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', height: 45),
            const SizedBox(width: 12),
            const Text('Notepad IO', style: TextStyle(fontSize: 22)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 28),
            onPressed: _showCreateDialog,
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _notes.length,
              itemBuilder: (context, index) {
                final note = _notes[index];
                String name = p.basename(note.file.path);
                return ListTile(
                  leading: Icon(
                    note.isLocked ? Icons.lock_outline : Icons.description_outlined, 
                    color: note.isLocked ? primaryColor : null
                  ),
                  title: Text(name),
                  subtitle: Text(note.lastModified.toString().split('.')[0]),
                  onTap: () => _handleFileTap(note),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showFileOptions(note),
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Text(
              "Made by @LegendAmardeep",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickFile,
        child: const Icon(Icons.file_open),
      ),
    );
  }
}

class NotepadEditor extends StatefulWidget {
  final File file;
  const NotepadEditor({super.key, required this.file});

  @override
  State<NotepadEditor> createState() => _NotepadEditorState();
}

class _NotepadEditorState extends State<NotepadEditor> {
  late SearchTextEditingController _controller;
  bool _isModified = false;
  double _fontSize = 16.0;
  double _baseFontSize = 16.0;
  bool _showFindReplace = false;
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _editorFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = SearchTextEditingController();
    try {
      _controller.text = widget.file.readAsStringSync();
    } catch (e) {
      _controller.text = "Error reading file: $e";
    }
    _controller.addListener(() {
      if (!_isModified) {
        setState(() => _isModified = true);
      }
    });
  }

  @override
  void dispose() {
    _editorFocusNode.dispose();
    _scrollController.dispose();
    _findController.dispose();    
    _replaceController.dispose(); 
    _controller.dispose();        
    super.dispose();
  }

  Future<void> _saveFile() async {
    await widget.file.writeAsString(_controller.text);
    setState(() => _isModified = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
  }

  void _findText({bool shouldScroll = false}) {
    final String query = _findController.text;
    if (query.isEmpty) {
      setState(() {
        _controller.query = '';
        _controller.offsets = [];
        _controller.activeIndex = -1;
      });
      return;
    }

    final String text = _controller.text;
    final List<int> offsets = [];
    int index = text.indexOf(query);
    while (index != -1) {
      offsets.add(index);
      index = text.indexOf(query, index + query.length);
    }

    setState(() {
      _controller.query = query;
      _controller.offsets = offsets;
      if (offsets.isNotEmpty) {
        if (_controller.activeIndex == -1) _controller.activeIndex = 0;
        if (shouldScroll) _scrollToMatch();
      } else {
        _controller.activeIndex = -1;
      }
    });
  }

  void _scrollToMatch() {
    if (_controller.activeIndex == -1 || _controller.offsets.isEmpty) return;

    final offset = _controller.offsets[_controller.activeIndex];

    final textPainter = TextPainter(
      text: TextSpan(
        text: _controller.text.substring(0, offset),
        style: TextStyle(
          fontFamily: 'Roboto mono',
          fontSize: _fontSize,
          fontWeight: FontWeight.w300,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    final width = MediaQuery.of(context).size.width - 32;
    textPainter.layout(maxWidth: width);

    final yPosition = textPainter.size.height;
    final viewportHeight = MediaQuery.of(context).size.height;
    final currentScroll = _scrollController.offset;

    _controller.selection = TextSelection(
      baseOffset: offset,
      extentOffset: offset + _findController.text.length,
    );

    if (yPosition > currentScroll + 150 && yPosition < currentScroll + viewportHeight - 200) {
      return;
    }

    final targetScroll = (yPosition - (viewportHeight / 2)).clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      targetScroll,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _nextMatch() {
    if (_controller.offsets.isEmpty) return;
    setState(() {
      _controller.activeIndex = (_controller.activeIndex + 1) % _controller.offsets.length;
      _scrollToMatch();
    });
  }

  void _prevMatch() {
    if (_controller.offsets.isEmpty) return;
    setState(() {
      _controller.activeIndex = (_controller.activeIndex - 1 + _controller.offsets.length) % _controller.offsets.length;
      _scrollToMatch();
    });
  }

  void _replaceCurrent() {
    if (_controller.activeIndex == -1 || _replaceController.text.isEmpty) return;

    final String find = _findController.text;
    final String replace = _replaceController.text;
    final String text = _controller.text;
    final int start = _controller.offsets[_controller.activeIndex];

    _controller.text = text.replaceRange(start, start + find.length, replace);
    _findText(shouldScroll: true);
  }

  void _replaceAll() {
    final String find = _findController.text;
    final String replace = _replaceController.text;
    if (find.isEmpty || replace.isEmpty) return;

    _controller.text = _controller.text.replaceAll(find, replace);
    _findText(shouldScroll: true);
  }

  @override
  Widget build(BuildContext context) {
    String fileName = p.basename(widget.file.path);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', height: 35),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_isModified ? "* " : ""}$fileName',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.find_replace),
            onPressed: () => setState(() {
              _showFindReplace = !_showFindReplace;
              if (!_showFindReplace) {
                _controller.query = '';
                _controller.offsets = [];
                _controller.activeIndex = -1;
              }
            }),
          ),
          IconButton(
            icon: Icon(Icons.save,
                color: _isModified ? Colors.white : Colors.grey),
            onPressed: _isModified ? _saveFile : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          GestureDetector(
            onScaleStart: (details) {
              _baseFontSize = _fontSize;
            },
            onScaleUpdate: (details) {
              setState(() {
                _fontSize = (_baseFontSize * details.scale).clamp(10.0, 60.0);
              });
            },
            child: Container(
              color: Colors.white,
              height: double.infinity,
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _controller,
                focusNode: _editorFocusNode,
                scrollController: _scrollController,
                maxLines: null,
                style: TextStyle(
                  fontFamily: 'Roboto mono',
                  fontWeight: FontWeight.w300,
                  fontSize: _fontSize,
                  color: Colors.black,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: animation.drive(Tween(begin: 0.9, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack))),
                    child: child,
                  ),
                );
              },
              child: _showFindReplace
                  ? Card(
                      key: const ValueKey('findReplaceBox'),
                      elevation: 8,
                      color: const Color(0xFF1A1A1A).withOpacity(0.95),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Container(
                        width: 280,
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: _findController,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) {
                                _findText(shouldScroll: true);
                                FocusScope.of(context).unfocus();
                              },
                              textInputAction: TextInputAction.search,
                              autofocus: true,
                              style: TextStyle(color: primaryColor),
                              decoration: const InputDecoration(
                                hintText: "Find",
                                isDense: true,
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.black26,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _replaceController,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => FocusScope.of(context).unfocus(),
                              style: TextStyle(color: primaryColor),
                              decoration: const InputDecoration(
                                hintText: "Replace",
                                isDense: true,
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.black26,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  _controller.offsets.isEmpty 
                                    ? "0/0" 
                                    : "${_controller.activeIndex + 1}/${_controller.offsets.length}",
                                  style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white),
                                  onPressed: _controller.offsets.isNotEmpty ? _prevMatch : null,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                                  onPressed: _controller.offsets.isNotEmpty ? _nextMatch : null,
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: _replaceController.text.isNotEmpty && _controller.activeIndex != -1
                                      ? ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: primaryColor,
                                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: _replaceCurrent,
                                          child: const Text("Replace"),
                                        )
                                      : OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: null,
                                          child: const Text("Replace"),
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: _replaceController.text.isNotEmpty && _controller.offsets.isNotEmpty
                                  ? _replaceAll 
                                  : null,
                                child: const Text("Replace All"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ),
        ],
      ),
    );
  }
}
