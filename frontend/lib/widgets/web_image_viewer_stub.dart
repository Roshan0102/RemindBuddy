import 'package:flutter/material.dart';

class WebImageViewer extends StatelessWidget {
  final String imageUrl;
  const WebImageViewer({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Web image rendering is only supported on Web platform.',
        style: TextStyle(color: Colors.white),
      ),
    );
  }
}
