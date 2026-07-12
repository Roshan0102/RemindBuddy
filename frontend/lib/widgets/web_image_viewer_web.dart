// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class WebImageViewer extends StatefulWidget {
  final String imageUrl;
  const WebImageViewer({super.key, required this.imageUrl});

  @override
  State<WebImageViewer> createState() => _WebImageViewerState();
}

class _WebImageViewerState extends State<WebImageViewer> {
  late String _viewId;

  @override
  void initState() {
    super.initState();
    // Unique ID based on imageUrl hash
    _viewId = 'web-image-${widget.imageUrl.hashCode}';
    
    // Register HTML image element with standard image loading behavior
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final img = html.ImageElement()
        ..src = widget.imageUrl
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'contain';
      return img;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}
