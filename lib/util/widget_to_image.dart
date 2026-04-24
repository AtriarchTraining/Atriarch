import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Off-screen widget-to-PNG capture for the share-result-image flow (#18).
///
/// The `screenshot` 2.5.0 package is incompatible with the current Flutter
/// SDK (it calls a removed `ViewConfiguration.size` parameter), so we spin
/// our own pipeline. Renders [widget] into a detached pipeline owner at
/// the given logical [size], then rasterizes via
/// [RenderRepaintBoundary.toImage].
///
/// Not meant for reuse across arbitrary widget trees — it assumes the
/// widget is self-contained (supplies its own Theme / MediaQuery /
/// Directionality) so no outer Inherited widgets leak in.
Future<Uint8List> captureWidgetToPng(
  Widget widget, {
  required Size size,
  double pixelRatio = 1.0,
}) async {
  final repaintBoundary = RenderRepaintBoundary();
  final platformDispatcher = WidgetsBinding.instance.platformDispatcher;
  final view = platformDispatcher.views.first;
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(
      alignment: Alignment.center,
      child: repaintBoundary,
    ),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints:
          BoxConstraints.tight(size) * pixelRatio,
      devicePixelRatio: pixelRatio,
    ),
  );

  final pipelineOwner = PipelineOwner();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();

  final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
    container: repaintBoundary,
    child: widget,
  ).attachToRenderTree(buildOwner);

  buildOwner
    ..buildScope(rootElement)
    ..finalizeTree();

  pipelineOwner
    ..flushLayout()
    ..flushCompositingBits()
    ..flushPaint();

  final ui.Image image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (byteData == null) {
    throw StateError('Widget image produced no byte data');
  }
  return byteData.buffer.asUint8List();
}
