import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/ports/image_store.dart';

/// Everything in the app-private tier, newest first.
final FutureProvider<List<PrivateImage>> privateImagesProvider =
    FutureProvider<List<PrivateImage>>((Ref ref) {
      final ImageStore images = ref.watch(imageStoreProvider);
      return images.privateImages();
    });
