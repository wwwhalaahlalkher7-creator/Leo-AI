import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    await const FlutterRustBridgeNativeAssetsBuilder(
      assetName: 'src/rust/frb_generated.io.dart',
      cratePath: '../../core/bridge',
      buildMode: FlutterRustBridgeBuildMode.release,
      assetRouting: <AssetRouting>[ToAppBundle()],
    ).run(input: input, output: output);
  });
}
