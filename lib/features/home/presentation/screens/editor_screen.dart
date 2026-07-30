import 'package:flutter/material.dart';
import '../../data/template_model.dart';
import 'package:motion_box/features/timeline/screens/timeline_editor_screen.dart';

class EditorScreen extends StatelessWidget {
  final TemplateModel? layoutTemplate;
  final DesignTemplate? designTemplate;

  const EditorScreen({
    super.key,
    this.layoutTemplate,
    this.designTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final mediaPath = layoutTemplate?.slots.firstOrNull?.localPath;
    return TimelineEditorScreen(initialVideoPath: mediaPath);
  }
}
