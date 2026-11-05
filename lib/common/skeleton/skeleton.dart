import 'package:material_ui/material_ui.dart';

/// Windows 低资源版本保留占位布局，不运行逐帧闪光动画。
class Skeleton extends StatelessWidget {
  final Widget child;

  const Skeleton({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
