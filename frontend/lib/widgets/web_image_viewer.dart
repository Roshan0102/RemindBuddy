import 'package:flutter/material.dart';
import 'web_image_viewer_stub.dart'
    if (dart.library.html) 'web_image_viewer_web.dart';

class WebImageViewerWrapper extends StatelessWidget {
  final String imageUrl;
  const WebImageViewerWrapper({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return WebImageViewer(imageUrl: imageUrl);
  }
}
