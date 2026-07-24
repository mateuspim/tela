// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tela_database.dart';

// ignore_for_file: type=lint
class $SettingEntriesTable extends SettingEntries
    with TableInfo<$SettingEntriesTable, SettingEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'setting_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingEntriesTable createAlias(String alias) {
    return $SettingEntriesTable(attachedDatabase, alias);
  }
}

class SettingEntry extends DataClass implements Insertable<SettingEntry> {
  /// The setting's stable identifier, e.g. `storage.tier.nsfw`.
  final String key;

  /// The stored value, serialised by the adapter that owns the key.
  final String value;
  const SettingEntry({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingEntriesCompanion toCompanion(bool nullToAbsent) {
    return SettingEntriesCompanion(key: Value(key), value: Value(value));
  }

  factory SettingEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingEntry copyWith({String? key, String? value}) =>
      SettingEntry(key: key ?? this.key, value: value ?? this.value);
  SettingEntry copyWithCompanion(SettingEntriesCompanion data) {
    return SettingEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingEntry(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingEntry &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingEntriesCompanion extends UpdateCompanion<SettingEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingEntriesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoriteWallpapersTable extends FavoriteWallpapers
    with TableInfo<$FavoriteWallpapersTable, FavoriteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoriteWallpapersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fullImageUrlMeta = const VerificationMeta(
    'fullImageUrl',
  );
  @override
  late final GeneratedColumn<String> fullImageUrl = GeneratedColumn<String>(
    'full_image_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbSmallUrlMeta = const VerificationMeta(
    'thumbSmallUrl',
  );
  @override
  late final GeneratedColumn<String> thumbSmallUrl = GeneratedColumn<String>(
    'thumb_small_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbLargeUrlMeta = const VerificationMeta(
    'thumbLargeUrl',
  );
  @override
  late final GeneratedColumn<String> thumbLargeUrl = GeneratedColumn<String>(
    'thumb_large_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbOriginalUrlMeta = const VerificationMeta(
    'thumbOriginalUrl',
  );
  @override
  late final GeneratedColumn<String> thumbOriginalUrl = GeneratedColumn<String>(
    'thumb_original_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeBytesMeta = const VerificationMeta(
    'fileSizeBytes',
  );
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
    'file_size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _purityMeta = const VerificationMeta('purity');
  @override
  late final GeneratedColumn<String> purity = GeneratedColumn<String>(
    'purity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorsMeta = const VerificationMeta('colors');
  @override
  late final GeneratedColumn<String> colors = GeneratedColumn<String>(
    'colors',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    source,
    id,
    fullImageUrl,
    thumbSmallUrl,
    thumbLargeUrl,
    thumbOriginalUrl,
    width,
    height,
    fileSizeBytes,
    purity,
    category,
    colors,
    savedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_wallpapers';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('full_image_url')) {
      context.handle(
        _fullImageUrlMeta,
        fullImageUrl.isAcceptableOrUnknown(
          data['full_image_url']!,
          _fullImageUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fullImageUrlMeta);
    }
    if (data.containsKey('thumb_small_url')) {
      context.handle(
        _thumbSmallUrlMeta,
        thumbSmallUrl.isAcceptableOrUnknown(
          data['thumb_small_url']!,
          _thumbSmallUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_thumbSmallUrlMeta);
    }
    if (data.containsKey('thumb_large_url')) {
      context.handle(
        _thumbLargeUrlMeta,
        thumbLargeUrl.isAcceptableOrUnknown(
          data['thumb_large_url']!,
          _thumbLargeUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_thumbLargeUrlMeta);
    }
    if (data.containsKey('thumb_original_url')) {
      context.handle(
        _thumbOriginalUrlMeta,
        thumbOriginalUrl.isAcceptableOrUnknown(
          data['thumb_original_url']!,
          _thumbOriginalUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_thumbOriginalUrlMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
        _fileSizeBytesMeta,
        fileSizeBytes.isAcceptableOrUnknown(
          data['file_size_bytes']!,
          _fileSizeBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fileSizeBytesMeta);
    }
    if (data.containsKey('purity')) {
      context.handle(
        _purityMeta,
        purity.isAcceptableOrUnknown(data['purity']!, _purityMeta),
      );
    } else if (isInserting) {
      context.missing(_purityMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('colors')) {
      context.handle(
        _colorsMeta,
        colors.isAcceptableOrUnknown(data['colors']!, _colorsMeta),
      );
    } else if (isInserting) {
      context.missing(_colorsMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {source, id};
  @override
  FavoriteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteRow(
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fullImageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}full_image_url'],
      )!,
      thumbSmallUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb_small_url'],
      )!,
      thumbLargeUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb_large_url'],
      )!,
      thumbOriginalUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb_original_url'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      fileSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size_bytes'],
      )!,
      purity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purity'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      colors: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}colors'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}saved_at'],
      )!,
    );
  }

  @override
  $FavoriteWallpapersTable createAlias(String alias) {
    return $FavoriteWallpapersTable(attachedDatabase, alias);
  }
}

class FavoriteRow extends DataClass implements Insertable<FavoriteRow> {
  /// `SourceId` value of the site it came from, e.g. `"wallhaven"`.
  ///
  /// Half the primary key, and the reason there is one: an id is unique to its
  /// source, so two sources can issue the same one — Konachan #12345 and
  /// yande.re #12345 are two wallpapers, and a table keyed on the number alone
  /// would let the second silently overwrite the first.
  final String source;

  /// The id that source issued, e.g. `"e7jvjd"`.
  final String id;

  /// Full-resolution source — what apply and download stream from.
  final String fullImageUrl;

  /// The three Wallhaven thumbnail sizes, kept as-is.
  final String thumbSmallUrl;

  /// Preview-sized thumbnail.
  final String thumbLargeUrl;

  /// Ratio-preserving thumbnail — the one the masonry grid draws.
  final String thumbOriginalUrl;

  /// Pixel width of [fullImageUrl].
  final int width;

  /// Pixel height of [fullImageUrl].
  final int height;

  /// Size of [fullImageUrl] in bytes.
  final int fileSizeBytes;

  /// Purity enum name. Routes storage, so its read has a fail-safe parse.
  final String purity;

  /// Category enum name.
  final String category;

  /// Dominant colours, comma-joined in Wallhaven's order.
  final String colors;

  /// When it was favorited. Orders the grid, newest first.
  final DateTime savedAt;
  const FavoriteRow({
    required this.source,
    required this.id,
    required this.fullImageUrl,
    required this.thumbSmallUrl,
    required this.thumbLargeUrl,
    required this.thumbOriginalUrl,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.purity,
    required this.category,
    required this.colors,
    required this.savedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source'] = Variable<String>(source);
    map['id'] = Variable<String>(id);
    map['full_image_url'] = Variable<String>(fullImageUrl);
    map['thumb_small_url'] = Variable<String>(thumbSmallUrl);
    map['thumb_large_url'] = Variable<String>(thumbLargeUrl);
    map['thumb_original_url'] = Variable<String>(thumbOriginalUrl);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    map['purity'] = Variable<String>(purity);
    map['category'] = Variable<String>(category);
    map['colors'] = Variable<String>(colors);
    map['saved_at'] = Variable<DateTime>(savedAt);
    return map;
  }

  FavoriteWallpapersCompanion toCompanion(bool nullToAbsent) {
    return FavoriteWallpapersCompanion(
      source: Value(source),
      id: Value(id),
      fullImageUrl: Value(fullImageUrl),
      thumbSmallUrl: Value(thumbSmallUrl),
      thumbLargeUrl: Value(thumbLargeUrl),
      thumbOriginalUrl: Value(thumbOriginalUrl),
      width: Value(width),
      height: Value(height),
      fileSizeBytes: Value(fileSizeBytes),
      purity: Value(purity),
      category: Value(category),
      colors: Value(colors),
      savedAt: Value(savedAt),
    );
  }

  factory FavoriteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteRow(
      source: serializer.fromJson<String>(json['source']),
      id: serializer.fromJson<String>(json['id']),
      fullImageUrl: serializer.fromJson<String>(json['fullImageUrl']),
      thumbSmallUrl: serializer.fromJson<String>(json['thumbSmallUrl']),
      thumbLargeUrl: serializer.fromJson<String>(json['thumbLargeUrl']),
      thumbOriginalUrl: serializer.fromJson<String>(json['thumbOriginalUrl']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      fileSizeBytes: serializer.fromJson<int>(json['fileSizeBytes']),
      purity: serializer.fromJson<String>(json['purity']),
      category: serializer.fromJson<String>(json['category']),
      colors: serializer.fromJson<String>(json['colors']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source': serializer.toJson<String>(source),
      'id': serializer.toJson<String>(id),
      'fullImageUrl': serializer.toJson<String>(fullImageUrl),
      'thumbSmallUrl': serializer.toJson<String>(thumbSmallUrl),
      'thumbLargeUrl': serializer.toJson<String>(thumbLargeUrl),
      'thumbOriginalUrl': serializer.toJson<String>(thumbOriginalUrl),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'fileSizeBytes': serializer.toJson<int>(fileSizeBytes),
      'purity': serializer.toJson<String>(purity),
      'category': serializer.toJson<String>(category),
      'colors': serializer.toJson<String>(colors),
      'savedAt': serializer.toJson<DateTime>(savedAt),
    };
  }

  FavoriteRow copyWith({
    String? source,
    String? id,
    String? fullImageUrl,
    String? thumbSmallUrl,
    String? thumbLargeUrl,
    String? thumbOriginalUrl,
    int? width,
    int? height,
    int? fileSizeBytes,
    String? purity,
    String? category,
    String? colors,
    DateTime? savedAt,
  }) => FavoriteRow(
    source: source ?? this.source,
    id: id ?? this.id,
    fullImageUrl: fullImageUrl ?? this.fullImageUrl,
    thumbSmallUrl: thumbSmallUrl ?? this.thumbSmallUrl,
    thumbLargeUrl: thumbLargeUrl ?? this.thumbLargeUrl,
    thumbOriginalUrl: thumbOriginalUrl ?? this.thumbOriginalUrl,
    width: width ?? this.width,
    height: height ?? this.height,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    purity: purity ?? this.purity,
    category: category ?? this.category,
    colors: colors ?? this.colors,
    savedAt: savedAt ?? this.savedAt,
  );
  FavoriteRow copyWithCompanion(FavoriteWallpapersCompanion data) {
    return FavoriteRow(
      source: data.source.present ? data.source.value : this.source,
      id: data.id.present ? data.id.value : this.id,
      fullImageUrl: data.fullImageUrl.present
          ? data.fullImageUrl.value
          : this.fullImageUrl,
      thumbSmallUrl: data.thumbSmallUrl.present
          ? data.thumbSmallUrl.value
          : this.thumbSmallUrl,
      thumbLargeUrl: data.thumbLargeUrl.present
          ? data.thumbLargeUrl.value
          : this.thumbLargeUrl,
      thumbOriginalUrl: data.thumbOriginalUrl.present
          ? data.thumbOriginalUrl.value
          : this.thumbOriginalUrl,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      purity: data.purity.present ? data.purity.value : this.purity,
      category: data.category.present ? data.category.value : this.category,
      colors: data.colors.present ? data.colors.value : this.colors,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteRow(')
          ..write('source: $source, ')
          ..write('id: $id, ')
          ..write('fullImageUrl: $fullImageUrl, ')
          ..write('thumbSmallUrl: $thumbSmallUrl, ')
          ..write('thumbLargeUrl: $thumbLargeUrl, ')
          ..write('thumbOriginalUrl: $thumbOriginalUrl, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('purity: $purity, ')
          ..write('category: $category, ')
          ..write('colors: $colors, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    source,
    id,
    fullImageUrl,
    thumbSmallUrl,
    thumbLargeUrl,
    thumbOriginalUrl,
    width,
    height,
    fileSizeBytes,
    purity,
    category,
    colors,
    savedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteRow &&
          other.source == this.source &&
          other.id == this.id &&
          other.fullImageUrl == this.fullImageUrl &&
          other.thumbSmallUrl == this.thumbSmallUrl &&
          other.thumbLargeUrl == this.thumbLargeUrl &&
          other.thumbOriginalUrl == this.thumbOriginalUrl &&
          other.width == this.width &&
          other.height == this.height &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.purity == this.purity &&
          other.category == this.category &&
          other.colors == this.colors &&
          other.savedAt == this.savedAt);
}

class FavoriteWallpapersCompanion extends UpdateCompanion<FavoriteRow> {
  final Value<String> source;
  final Value<String> id;
  final Value<String> fullImageUrl;
  final Value<String> thumbSmallUrl;
  final Value<String> thumbLargeUrl;
  final Value<String> thumbOriginalUrl;
  final Value<int> width;
  final Value<int> height;
  final Value<int> fileSizeBytes;
  final Value<String> purity;
  final Value<String> category;
  final Value<String> colors;
  final Value<DateTime> savedAt;
  final Value<int> rowid;
  const FavoriteWallpapersCompanion({
    this.source = const Value.absent(),
    this.id = const Value.absent(),
    this.fullImageUrl = const Value.absent(),
    this.thumbSmallUrl = const Value.absent(),
    this.thumbLargeUrl = const Value.absent(),
    this.thumbOriginalUrl = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.purity = const Value.absent(),
    this.category = const Value.absent(),
    this.colors = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteWallpapersCompanion.insert({
    required String source,
    required String id,
    required String fullImageUrl,
    required String thumbSmallUrl,
    required String thumbLargeUrl,
    required String thumbOriginalUrl,
    required int width,
    required int height,
    required int fileSizeBytes,
    required String purity,
    required String category,
    required String colors,
    required DateTime savedAt,
    this.rowid = const Value.absent(),
  }) : source = Value(source),
       id = Value(id),
       fullImageUrl = Value(fullImageUrl),
       thumbSmallUrl = Value(thumbSmallUrl),
       thumbLargeUrl = Value(thumbLargeUrl),
       thumbOriginalUrl = Value(thumbOriginalUrl),
       width = Value(width),
       height = Value(height),
       fileSizeBytes = Value(fileSizeBytes),
       purity = Value(purity),
       category = Value(category),
       colors = Value(colors),
       savedAt = Value(savedAt);
  static Insertable<FavoriteRow> custom({
    Expression<String>? source,
    Expression<String>? id,
    Expression<String>? fullImageUrl,
    Expression<String>? thumbSmallUrl,
    Expression<String>? thumbLargeUrl,
    Expression<String>? thumbOriginalUrl,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? fileSizeBytes,
    Expression<String>? purity,
    Expression<String>? category,
    Expression<String>? colors,
    Expression<DateTime>? savedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (source != null) 'source': source,
      if (id != null) 'id': id,
      if (fullImageUrl != null) 'full_image_url': fullImageUrl,
      if (thumbSmallUrl != null) 'thumb_small_url': thumbSmallUrl,
      if (thumbLargeUrl != null) 'thumb_large_url': thumbLargeUrl,
      if (thumbOriginalUrl != null) 'thumb_original_url': thumbOriginalUrl,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (purity != null) 'purity': purity,
      if (category != null) 'category': category,
      if (colors != null) 'colors': colors,
      if (savedAt != null) 'saved_at': savedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteWallpapersCompanion copyWith({
    Value<String>? source,
    Value<String>? id,
    Value<String>? fullImageUrl,
    Value<String>? thumbSmallUrl,
    Value<String>? thumbLargeUrl,
    Value<String>? thumbOriginalUrl,
    Value<int>? width,
    Value<int>? height,
    Value<int>? fileSizeBytes,
    Value<String>? purity,
    Value<String>? category,
    Value<String>? colors,
    Value<DateTime>? savedAt,
    Value<int>? rowid,
  }) {
    return FavoriteWallpapersCompanion(
      source: source ?? this.source,
      id: id ?? this.id,
      fullImageUrl: fullImageUrl ?? this.fullImageUrl,
      thumbSmallUrl: thumbSmallUrl ?? this.thumbSmallUrl,
      thumbLargeUrl: thumbLargeUrl ?? this.thumbLargeUrl,
      thumbOriginalUrl: thumbOriginalUrl ?? this.thumbOriginalUrl,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      purity: purity ?? this.purity,
      category: category ?? this.category,
      colors: colors ?? this.colors,
      savedAt: savedAt ?? this.savedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fullImageUrl.present) {
      map['full_image_url'] = Variable<String>(fullImageUrl.value);
    }
    if (thumbSmallUrl.present) {
      map['thumb_small_url'] = Variable<String>(thumbSmallUrl.value);
    }
    if (thumbLargeUrl.present) {
      map['thumb_large_url'] = Variable<String>(thumbLargeUrl.value);
    }
    if (thumbOriginalUrl.present) {
      map['thumb_original_url'] = Variable<String>(thumbOriginalUrl.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (purity.present) {
      map['purity'] = Variable<String>(purity.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (colors.present) {
      map['colors'] = Variable<String>(colors.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteWallpapersCompanion(')
          ..write('source: $source, ')
          ..write('id: $id, ')
          ..write('fullImageUrl: $fullImageUrl, ')
          ..write('thumbSmallUrl: $thumbSmallUrl, ')
          ..write('thumbLargeUrl: $thumbLargeUrl, ')
          ..write('thumbOriginalUrl: $thumbOriginalUrl, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('purity: $purity, ')
          ..write('category: $category, ')
          ..write('colors: $colors, ')
          ..write('savedAt: $savedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadedWallpapersTable extends DownloadedWallpapers
    with TableInfo<$DownloadedWallpapersTable, DownloadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadedWallpapersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fullImageUrlMeta = const VerificationMeta(
    'fullImageUrl',
  );
  @override
  late final GeneratedColumn<String> fullImageUrl = GeneratedColumn<String>(
    'full_image_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbSmallUrlMeta = const VerificationMeta(
    'thumbSmallUrl',
  );
  @override
  late final GeneratedColumn<String> thumbSmallUrl = GeneratedColumn<String>(
    'thumb_small_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbLargeUrlMeta = const VerificationMeta(
    'thumbLargeUrl',
  );
  @override
  late final GeneratedColumn<String> thumbLargeUrl = GeneratedColumn<String>(
    'thumb_large_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbOriginalUrlMeta = const VerificationMeta(
    'thumbOriginalUrl',
  );
  @override
  late final GeneratedColumn<String> thumbOriginalUrl = GeneratedColumn<String>(
    'thumb_original_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeBytesMeta = const VerificationMeta(
    'fileSizeBytes',
  );
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
    'file_size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _purityMeta = const VerificationMeta('purity');
  @override
  late final GeneratedColumn<String> purity = GeneratedColumn<String>(
    'purity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorsMeta = const VerificationMeta('colors');
  @override
  late final GeneratedColumn<String> colors = GeneratedColumn<String>(
    'colors',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tierMeta = const VerificationMeta('tier');
  @override
  late final GeneratedColumn<String> tier = GeneratedColumn<String>(
    'tier',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _downloadedAtMeta = const VerificationMeta(
    'downloadedAt',
  );
  @override
  late final GeneratedColumn<DateTime> downloadedAt = GeneratedColumn<DateTime>(
    'downloaded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    source,
    id,
    fullImageUrl,
    thumbSmallUrl,
    thumbLargeUrl,
    thumbOriginalUrl,
    width,
    height,
    fileSizeBytes,
    purity,
    category,
    colors,
    tier,
    location,
    downloadedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'downloaded_wallpapers';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('full_image_url')) {
      context.handle(
        _fullImageUrlMeta,
        fullImageUrl.isAcceptableOrUnknown(
          data['full_image_url']!,
          _fullImageUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fullImageUrlMeta);
    }
    if (data.containsKey('thumb_small_url')) {
      context.handle(
        _thumbSmallUrlMeta,
        thumbSmallUrl.isAcceptableOrUnknown(
          data['thumb_small_url']!,
          _thumbSmallUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_thumbSmallUrlMeta);
    }
    if (data.containsKey('thumb_large_url')) {
      context.handle(
        _thumbLargeUrlMeta,
        thumbLargeUrl.isAcceptableOrUnknown(
          data['thumb_large_url']!,
          _thumbLargeUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_thumbLargeUrlMeta);
    }
    if (data.containsKey('thumb_original_url')) {
      context.handle(
        _thumbOriginalUrlMeta,
        thumbOriginalUrl.isAcceptableOrUnknown(
          data['thumb_original_url']!,
          _thumbOriginalUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_thumbOriginalUrlMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
        _fileSizeBytesMeta,
        fileSizeBytes.isAcceptableOrUnknown(
          data['file_size_bytes']!,
          _fileSizeBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fileSizeBytesMeta);
    }
    if (data.containsKey('purity')) {
      context.handle(
        _purityMeta,
        purity.isAcceptableOrUnknown(data['purity']!, _purityMeta),
      );
    } else if (isInserting) {
      context.missing(_purityMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('colors')) {
      context.handle(
        _colorsMeta,
        colors.isAcceptableOrUnknown(data['colors']!, _colorsMeta),
      );
    } else if (isInserting) {
      context.missing(_colorsMeta);
    }
    if (data.containsKey('tier')) {
      context.handle(
        _tierMeta,
        tier.isAcceptableOrUnknown(data['tier']!, _tierMeta),
      );
    } else if (isInserting) {
      context.missing(_tierMeta);
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    } else if (isInserting) {
      context.missing(_locationMeta);
    }
    if (data.containsKey('downloaded_at')) {
      context.handle(
        _downloadedAtMeta,
        downloadedAt.isAcceptableOrUnknown(
          data['downloaded_at']!,
          _downloadedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_downloadedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {source, id};
  @override
  DownloadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadRow(
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fullImageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}full_image_url'],
      )!,
      thumbSmallUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb_small_url'],
      )!,
      thumbLargeUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb_large_url'],
      )!,
      thumbOriginalUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb_original_url'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      fileSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size_bytes'],
      )!,
      purity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purity'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      colors: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}colors'],
      )!,
      tier: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tier'],
      )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      )!,
      downloadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}downloaded_at'],
      )!,
    );
  }

  @override
  $DownloadedWallpapersTable createAlias(String alias) {
    return $DownloadedWallpapersTable(attachedDatabase, alias);
  }
}

class DownloadRow extends DataClass implements Insertable<DownloadRow> {
  /// `SourceId` value of the site it came from, e.g. `"wallhaven"`.
  ///
  /// Half the primary key, and the reason there is one: an id is unique to its
  /// source, so two sources can issue the same one — Konachan #12345 and
  /// yande.re #12345 are two wallpapers, and a table keyed on the number alone
  /// would let the second silently overwrite the first.
  final String source;

  /// The id that source issued, e.g. `"e7jvjd"`.
  final String id;

  /// Full-resolution source — what apply and download stream from.
  final String fullImageUrl;

  /// The three Wallhaven thumbnail sizes, kept as-is.
  final String thumbSmallUrl;

  /// Preview-sized thumbnail.
  final String thumbLargeUrl;

  /// Ratio-preserving thumbnail — the one the masonry grid draws.
  final String thumbOriginalUrl;

  /// Pixel width of [fullImageUrl].
  final int width;

  /// Pixel height of [fullImageUrl].
  final int height;

  /// Size of [fullImageUrl] in bytes.
  final int fileSizeBytes;

  /// Purity enum name. Routes storage, so its read has a fail-safe parse.
  final String purity;

  /// Category enum name.
  final String category;

  /// Dominant colours, comma-joined in Wallhaven's order.
  final String colors;

  /// `StorageTier` name of the destination it actually landed in.
  final String tier;

  /// The file's URI: MediaStore content, a SAF document, or a local file.
  final String location;

  /// When it was downloaded. Orders the history, newest first.
  final DateTime downloadedAt;
  const DownloadRow({
    required this.source,
    required this.id,
    required this.fullImageUrl,
    required this.thumbSmallUrl,
    required this.thumbLargeUrl,
    required this.thumbOriginalUrl,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.purity,
    required this.category,
    required this.colors,
    required this.tier,
    required this.location,
    required this.downloadedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source'] = Variable<String>(source);
    map['id'] = Variable<String>(id);
    map['full_image_url'] = Variable<String>(fullImageUrl);
    map['thumb_small_url'] = Variable<String>(thumbSmallUrl);
    map['thumb_large_url'] = Variable<String>(thumbLargeUrl);
    map['thumb_original_url'] = Variable<String>(thumbOriginalUrl);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    map['purity'] = Variable<String>(purity);
    map['category'] = Variable<String>(category);
    map['colors'] = Variable<String>(colors);
    map['tier'] = Variable<String>(tier);
    map['location'] = Variable<String>(location);
    map['downloaded_at'] = Variable<DateTime>(downloadedAt);
    return map;
  }

  DownloadedWallpapersCompanion toCompanion(bool nullToAbsent) {
    return DownloadedWallpapersCompanion(
      source: Value(source),
      id: Value(id),
      fullImageUrl: Value(fullImageUrl),
      thumbSmallUrl: Value(thumbSmallUrl),
      thumbLargeUrl: Value(thumbLargeUrl),
      thumbOriginalUrl: Value(thumbOriginalUrl),
      width: Value(width),
      height: Value(height),
      fileSizeBytes: Value(fileSizeBytes),
      purity: Value(purity),
      category: Value(category),
      colors: Value(colors),
      tier: Value(tier),
      location: Value(location),
      downloadedAt: Value(downloadedAt),
    );
  }

  factory DownloadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadRow(
      source: serializer.fromJson<String>(json['source']),
      id: serializer.fromJson<String>(json['id']),
      fullImageUrl: serializer.fromJson<String>(json['fullImageUrl']),
      thumbSmallUrl: serializer.fromJson<String>(json['thumbSmallUrl']),
      thumbLargeUrl: serializer.fromJson<String>(json['thumbLargeUrl']),
      thumbOriginalUrl: serializer.fromJson<String>(json['thumbOriginalUrl']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      fileSizeBytes: serializer.fromJson<int>(json['fileSizeBytes']),
      purity: serializer.fromJson<String>(json['purity']),
      category: serializer.fromJson<String>(json['category']),
      colors: serializer.fromJson<String>(json['colors']),
      tier: serializer.fromJson<String>(json['tier']),
      location: serializer.fromJson<String>(json['location']),
      downloadedAt: serializer.fromJson<DateTime>(json['downloadedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source': serializer.toJson<String>(source),
      'id': serializer.toJson<String>(id),
      'fullImageUrl': serializer.toJson<String>(fullImageUrl),
      'thumbSmallUrl': serializer.toJson<String>(thumbSmallUrl),
      'thumbLargeUrl': serializer.toJson<String>(thumbLargeUrl),
      'thumbOriginalUrl': serializer.toJson<String>(thumbOriginalUrl),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'fileSizeBytes': serializer.toJson<int>(fileSizeBytes),
      'purity': serializer.toJson<String>(purity),
      'category': serializer.toJson<String>(category),
      'colors': serializer.toJson<String>(colors),
      'tier': serializer.toJson<String>(tier),
      'location': serializer.toJson<String>(location),
      'downloadedAt': serializer.toJson<DateTime>(downloadedAt),
    };
  }

  DownloadRow copyWith({
    String? source,
    String? id,
    String? fullImageUrl,
    String? thumbSmallUrl,
    String? thumbLargeUrl,
    String? thumbOriginalUrl,
    int? width,
    int? height,
    int? fileSizeBytes,
    String? purity,
    String? category,
    String? colors,
    String? tier,
    String? location,
    DateTime? downloadedAt,
  }) => DownloadRow(
    source: source ?? this.source,
    id: id ?? this.id,
    fullImageUrl: fullImageUrl ?? this.fullImageUrl,
    thumbSmallUrl: thumbSmallUrl ?? this.thumbSmallUrl,
    thumbLargeUrl: thumbLargeUrl ?? this.thumbLargeUrl,
    thumbOriginalUrl: thumbOriginalUrl ?? this.thumbOriginalUrl,
    width: width ?? this.width,
    height: height ?? this.height,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    purity: purity ?? this.purity,
    category: category ?? this.category,
    colors: colors ?? this.colors,
    tier: tier ?? this.tier,
    location: location ?? this.location,
    downloadedAt: downloadedAt ?? this.downloadedAt,
  );
  DownloadRow copyWithCompanion(DownloadedWallpapersCompanion data) {
    return DownloadRow(
      source: data.source.present ? data.source.value : this.source,
      id: data.id.present ? data.id.value : this.id,
      fullImageUrl: data.fullImageUrl.present
          ? data.fullImageUrl.value
          : this.fullImageUrl,
      thumbSmallUrl: data.thumbSmallUrl.present
          ? data.thumbSmallUrl.value
          : this.thumbSmallUrl,
      thumbLargeUrl: data.thumbLargeUrl.present
          ? data.thumbLargeUrl.value
          : this.thumbLargeUrl,
      thumbOriginalUrl: data.thumbOriginalUrl.present
          ? data.thumbOriginalUrl.value
          : this.thumbOriginalUrl,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      purity: data.purity.present ? data.purity.value : this.purity,
      category: data.category.present ? data.category.value : this.category,
      colors: data.colors.present ? data.colors.value : this.colors,
      tier: data.tier.present ? data.tier.value : this.tier,
      location: data.location.present ? data.location.value : this.location,
      downloadedAt: data.downloadedAt.present
          ? data.downloadedAt.value
          : this.downloadedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadRow(')
          ..write('source: $source, ')
          ..write('id: $id, ')
          ..write('fullImageUrl: $fullImageUrl, ')
          ..write('thumbSmallUrl: $thumbSmallUrl, ')
          ..write('thumbLargeUrl: $thumbLargeUrl, ')
          ..write('thumbOriginalUrl: $thumbOriginalUrl, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('purity: $purity, ')
          ..write('category: $category, ')
          ..write('colors: $colors, ')
          ..write('tier: $tier, ')
          ..write('location: $location, ')
          ..write('downloadedAt: $downloadedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    source,
    id,
    fullImageUrl,
    thumbSmallUrl,
    thumbLargeUrl,
    thumbOriginalUrl,
    width,
    height,
    fileSizeBytes,
    purity,
    category,
    colors,
    tier,
    location,
    downloadedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadRow &&
          other.source == this.source &&
          other.id == this.id &&
          other.fullImageUrl == this.fullImageUrl &&
          other.thumbSmallUrl == this.thumbSmallUrl &&
          other.thumbLargeUrl == this.thumbLargeUrl &&
          other.thumbOriginalUrl == this.thumbOriginalUrl &&
          other.width == this.width &&
          other.height == this.height &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.purity == this.purity &&
          other.category == this.category &&
          other.colors == this.colors &&
          other.tier == this.tier &&
          other.location == this.location &&
          other.downloadedAt == this.downloadedAt);
}

class DownloadedWallpapersCompanion extends UpdateCompanion<DownloadRow> {
  final Value<String> source;
  final Value<String> id;
  final Value<String> fullImageUrl;
  final Value<String> thumbSmallUrl;
  final Value<String> thumbLargeUrl;
  final Value<String> thumbOriginalUrl;
  final Value<int> width;
  final Value<int> height;
  final Value<int> fileSizeBytes;
  final Value<String> purity;
  final Value<String> category;
  final Value<String> colors;
  final Value<String> tier;
  final Value<String> location;
  final Value<DateTime> downloadedAt;
  final Value<int> rowid;
  const DownloadedWallpapersCompanion({
    this.source = const Value.absent(),
    this.id = const Value.absent(),
    this.fullImageUrl = const Value.absent(),
    this.thumbSmallUrl = const Value.absent(),
    this.thumbLargeUrl = const Value.absent(),
    this.thumbOriginalUrl = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.purity = const Value.absent(),
    this.category = const Value.absent(),
    this.colors = const Value.absent(),
    this.tier = const Value.absent(),
    this.location = const Value.absent(),
    this.downloadedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadedWallpapersCompanion.insert({
    required String source,
    required String id,
    required String fullImageUrl,
    required String thumbSmallUrl,
    required String thumbLargeUrl,
    required String thumbOriginalUrl,
    required int width,
    required int height,
    required int fileSizeBytes,
    required String purity,
    required String category,
    required String colors,
    required String tier,
    required String location,
    required DateTime downloadedAt,
    this.rowid = const Value.absent(),
  }) : source = Value(source),
       id = Value(id),
       fullImageUrl = Value(fullImageUrl),
       thumbSmallUrl = Value(thumbSmallUrl),
       thumbLargeUrl = Value(thumbLargeUrl),
       thumbOriginalUrl = Value(thumbOriginalUrl),
       width = Value(width),
       height = Value(height),
       fileSizeBytes = Value(fileSizeBytes),
       purity = Value(purity),
       category = Value(category),
       colors = Value(colors),
       tier = Value(tier),
       location = Value(location),
       downloadedAt = Value(downloadedAt);
  static Insertable<DownloadRow> custom({
    Expression<String>? source,
    Expression<String>? id,
    Expression<String>? fullImageUrl,
    Expression<String>? thumbSmallUrl,
    Expression<String>? thumbLargeUrl,
    Expression<String>? thumbOriginalUrl,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? fileSizeBytes,
    Expression<String>? purity,
    Expression<String>? category,
    Expression<String>? colors,
    Expression<String>? tier,
    Expression<String>? location,
    Expression<DateTime>? downloadedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (source != null) 'source': source,
      if (id != null) 'id': id,
      if (fullImageUrl != null) 'full_image_url': fullImageUrl,
      if (thumbSmallUrl != null) 'thumb_small_url': thumbSmallUrl,
      if (thumbLargeUrl != null) 'thumb_large_url': thumbLargeUrl,
      if (thumbOriginalUrl != null) 'thumb_original_url': thumbOriginalUrl,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (purity != null) 'purity': purity,
      if (category != null) 'category': category,
      if (colors != null) 'colors': colors,
      if (tier != null) 'tier': tier,
      if (location != null) 'location': location,
      if (downloadedAt != null) 'downloaded_at': downloadedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadedWallpapersCompanion copyWith({
    Value<String>? source,
    Value<String>? id,
    Value<String>? fullImageUrl,
    Value<String>? thumbSmallUrl,
    Value<String>? thumbLargeUrl,
    Value<String>? thumbOriginalUrl,
    Value<int>? width,
    Value<int>? height,
    Value<int>? fileSizeBytes,
    Value<String>? purity,
    Value<String>? category,
    Value<String>? colors,
    Value<String>? tier,
    Value<String>? location,
    Value<DateTime>? downloadedAt,
    Value<int>? rowid,
  }) {
    return DownloadedWallpapersCompanion(
      source: source ?? this.source,
      id: id ?? this.id,
      fullImageUrl: fullImageUrl ?? this.fullImageUrl,
      thumbSmallUrl: thumbSmallUrl ?? this.thumbSmallUrl,
      thumbLargeUrl: thumbLargeUrl ?? this.thumbLargeUrl,
      thumbOriginalUrl: thumbOriginalUrl ?? this.thumbOriginalUrl,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      purity: purity ?? this.purity,
      category: category ?? this.category,
      colors: colors ?? this.colors,
      tier: tier ?? this.tier,
      location: location ?? this.location,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fullImageUrl.present) {
      map['full_image_url'] = Variable<String>(fullImageUrl.value);
    }
    if (thumbSmallUrl.present) {
      map['thumb_small_url'] = Variable<String>(thumbSmallUrl.value);
    }
    if (thumbLargeUrl.present) {
      map['thumb_large_url'] = Variable<String>(thumbLargeUrl.value);
    }
    if (thumbOriginalUrl.present) {
      map['thumb_original_url'] = Variable<String>(thumbOriginalUrl.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (purity.present) {
      map['purity'] = Variable<String>(purity.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (colors.present) {
      map['colors'] = Variable<String>(colors.value);
    }
    if (tier.present) {
      map['tier'] = Variable<String>(tier.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (downloadedAt.present) {
      map['downloaded_at'] = Variable<DateTime>(downloadedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadedWallpapersCompanion(')
          ..write('source: $source, ')
          ..write('id: $id, ')
          ..write('fullImageUrl: $fullImageUrl, ')
          ..write('thumbSmallUrl: $thumbSmallUrl, ')
          ..write('thumbLargeUrl: $thumbLargeUrl, ')
          ..write('thumbOriginalUrl: $thumbOriginalUrl, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('purity: $purity, ')
          ..write('category: $category, ')
          ..write('colors: $colors, ')
          ..write('tier: $tier, ')
          ..write('location: $location, ')
          ..write('downloadedAt: $downloadedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BlockedTagsTable extends BlockedTags
    with TableInfo<$BlockedTagsTable, BlockedTagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlockedTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blockedAtMeta = const VerificationMeta(
    'blockedAt',
  );
  @override
  late final GeneratedColumn<DateTime> blockedAt = GeneratedColumn<DateTime>(
    'blocked_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, blockedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'blocked_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<BlockedTagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('blocked_at')) {
      context.handle(
        _blockedAtMeta,
        blockedAt.isAcceptableOrUnknown(data['blocked_at']!, _blockedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_blockedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BlockedTagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlockedTagRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      blockedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}blocked_at'],
      )!,
    );
  }

  @override
  $BlockedTagsTable createAlias(String alias) {
    return $BlockedTagsTable(attachedDatabase, alias);
  }
}

class BlockedTagRow extends DataClass implements Insertable<BlockedTagRow> {
  /// Wallhaven's numeric tag id — what the `-id:{n}` operator actually
  /// excludes.
  final int id;

  /// Display name, kept only so the management screen can show what was
  /// blocked without a network call.
  final String name;

  /// When it was blocked. Orders the management screen, newest first.
  final DateTime blockedAt;
  const BlockedTagRow({
    required this.id,
    required this.name,
    required this.blockedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['blocked_at'] = Variable<DateTime>(blockedAt);
    return map;
  }

  BlockedTagsCompanion toCompanion(bool nullToAbsent) {
    return BlockedTagsCompanion(
      id: Value(id),
      name: Value(name),
      blockedAt: Value(blockedAt),
    );
  }

  factory BlockedTagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlockedTagRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      blockedAt: serializer.fromJson<DateTime>(json['blockedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'blockedAt': serializer.toJson<DateTime>(blockedAt),
    };
  }

  BlockedTagRow copyWith({int? id, String? name, DateTime? blockedAt}) =>
      BlockedTagRow(
        id: id ?? this.id,
        name: name ?? this.name,
        blockedAt: blockedAt ?? this.blockedAt,
      );
  BlockedTagRow copyWithCompanion(BlockedTagsCompanion data) {
    return BlockedTagRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      blockedAt: data.blockedAt.present ? data.blockedAt.value : this.blockedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlockedTagRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('blockedAt: $blockedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, blockedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockedTagRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.blockedAt == this.blockedAt);
}

class BlockedTagsCompanion extends UpdateCompanion<BlockedTagRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<DateTime> blockedAt;
  const BlockedTagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.blockedAt = const Value.absent(),
  });
  BlockedTagsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required DateTime blockedAt,
  }) : name = Value(name),
       blockedAt = Value(blockedAt);
  static Insertable<BlockedTagRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<DateTime>? blockedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (blockedAt != null) 'blocked_at': blockedAt,
    });
  }

  BlockedTagsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<DateTime>? blockedAt,
  }) {
    return BlockedTagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      blockedAt: blockedAt ?? this.blockedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (blockedAt.present) {
      map['blocked_at'] = Variable<DateTime>(blockedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlockedTagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('blockedAt: $blockedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$TelaDatabase extends GeneratedDatabase {
  _$TelaDatabase(QueryExecutor e) : super(e);
  $TelaDatabaseManager get managers => $TelaDatabaseManager(this);
  late final $SettingEntriesTable settingEntries = $SettingEntriesTable(this);
  late final $FavoriteWallpapersTable favoriteWallpapers =
      $FavoriteWallpapersTable(this);
  late final $DownloadedWallpapersTable downloadedWallpapers =
      $DownloadedWallpapersTable(this);
  late final $BlockedTagsTable blockedTags = $BlockedTagsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    settingEntries,
    favoriteWallpapers,
    downloadedWallpapers,
    blockedTags,
  ];
}

typedef $$SettingEntriesTableCreateCompanionBuilder =
    SettingEntriesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingEntriesTableUpdateCompanionBuilder =
    SettingEntriesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingEntriesTableFilterComposer
    extends Composer<_$TelaDatabase, $SettingEntriesTable> {
  $$SettingEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingEntriesTableOrderingComposer
    extends Composer<_$TelaDatabase, $SettingEntriesTable> {
  $$SettingEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingEntriesTableAnnotationComposer
    extends Composer<_$TelaDatabase, $SettingEntriesTable> {
  $$SettingEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingEntriesTableTableManager
    extends
        RootTableManager<
          _$TelaDatabase,
          $SettingEntriesTable,
          SettingEntry,
          $$SettingEntriesTableFilterComposer,
          $$SettingEntriesTableOrderingComposer,
          $$SettingEntriesTableAnnotationComposer,
          $$SettingEntriesTableCreateCompanionBuilder,
          $$SettingEntriesTableUpdateCompanionBuilder,
          (
            SettingEntry,
            BaseReferences<_$TelaDatabase, $SettingEntriesTable, SettingEntry>,
          ),
          SettingEntry,
          PrefetchHooks Function()
        > {
  $$SettingEntriesTableTableManager(
    _$TelaDatabase db,
    $SettingEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  SettingEntriesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingEntriesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$TelaDatabase,
      $SettingEntriesTable,
      SettingEntry,
      $$SettingEntriesTableFilterComposer,
      $$SettingEntriesTableOrderingComposer,
      $$SettingEntriesTableAnnotationComposer,
      $$SettingEntriesTableCreateCompanionBuilder,
      $$SettingEntriesTableUpdateCompanionBuilder,
      (
        SettingEntry,
        BaseReferences<_$TelaDatabase, $SettingEntriesTable, SettingEntry>,
      ),
      SettingEntry,
      PrefetchHooks Function()
    >;
typedef $$FavoriteWallpapersTableCreateCompanionBuilder =
    FavoriteWallpapersCompanion Function({
      required String source,
      required String id,
      required String fullImageUrl,
      required String thumbSmallUrl,
      required String thumbLargeUrl,
      required String thumbOriginalUrl,
      required int width,
      required int height,
      required int fileSizeBytes,
      required String purity,
      required String category,
      required String colors,
      required DateTime savedAt,
      Value<int> rowid,
    });
typedef $$FavoriteWallpapersTableUpdateCompanionBuilder =
    FavoriteWallpapersCompanion Function({
      Value<String> source,
      Value<String> id,
      Value<String> fullImageUrl,
      Value<String> thumbSmallUrl,
      Value<String> thumbLargeUrl,
      Value<String> thumbOriginalUrl,
      Value<int> width,
      Value<int> height,
      Value<int> fileSizeBytes,
      Value<String> purity,
      Value<String> category,
      Value<String> colors,
      Value<DateTime> savedAt,
      Value<int> rowid,
    });

class $$FavoriteWallpapersTableFilterComposer
    extends Composer<_$TelaDatabase, $FavoriteWallpapersTable> {
  $$FavoriteWallpapersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fullImageUrl => $composableBuilder(
    column: $table.fullImageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbSmallUrl => $composableBuilder(
    column: $table.thumbSmallUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbLargeUrl => $composableBuilder(
    column: $table.thumbLargeUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbOriginalUrl => $composableBuilder(
    column: $table.thumbOriginalUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purity => $composableBuilder(
    column: $table.purity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colors => $composableBuilder(
    column: $table.colors,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoriteWallpapersTableOrderingComposer
    extends Composer<_$TelaDatabase, $FavoriteWallpapersTable> {
  $$FavoriteWallpapersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fullImageUrl => $composableBuilder(
    column: $table.fullImageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbSmallUrl => $composableBuilder(
    column: $table.thumbSmallUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbLargeUrl => $composableBuilder(
    column: $table.thumbLargeUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbOriginalUrl => $composableBuilder(
    column: $table.thumbOriginalUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purity => $composableBuilder(
    column: $table.purity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colors => $composableBuilder(
    column: $table.colors,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoriteWallpapersTableAnnotationComposer
    extends Composer<_$TelaDatabase, $FavoriteWallpapersTable> {
  $$FavoriteWallpapersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fullImageUrl => $composableBuilder(
    column: $table.fullImageUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbSmallUrl => $composableBuilder(
    column: $table.thumbSmallUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbLargeUrl => $composableBuilder(
    column: $table.thumbLargeUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbOriginalUrl => $composableBuilder(
    column: $table.thumbOriginalUrl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get purity =>
      $composableBuilder(column: $table.purity, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get colors =>
      $composableBuilder(column: $table.colors, builder: (column) => column);

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);
}

class $$FavoriteWallpapersTableTableManager
    extends
        RootTableManager<
          _$TelaDatabase,
          $FavoriteWallpapersTable,
          FavoriteRow,
          $$FavoriteWallpapersTableFilterComposer,
          $$FavoriteWallpapersTableOrderingComposer,
          $$FavoriteWallpapersTableAnnotationComposer,
          $$FavoriteWallpapersTableCreateCompanionBuilder,
          $$FavoriteWallpapersTableUpdateCompanionBuilder,
          (
            FavoriteRow,
            BaseReferences<
              _$TelaDatabase,
              $FavoriteWallpapersTable,
              FavoriteRow
            >,
          ),
          FavoriteRow,
          PrefetchHooks Function()
        > {
  $$FavoriteWallpapersTableTableManager(
    _$TelaDatabase db,
    $FavoriteWallpapersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoriteWallpapersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoriteWallpapersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoriteWallpapersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> source = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> fullImageUrl = const Value.absent(),
                Value<String> thumbSmallUrl = const Value.absent(),
                Value<String> thumbLargeUrl = const Value.absent(),
                Value<String> thumbOriginalUrl = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<int> fileSizeBytes = const Value.absent(),
                Value<String> purity = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> colors = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteWallpapersCompanion(
                source: source,
                id: id,
                fullImageUrl: fullImageUrl,
                thumbSmallUrl: thumbSmallUrl,
                thumbLargeUrl: thumbLargeUrl,
                thumbOriginalUrl: thumbOriginalUrl,
                width: width,
                height: height,
                fileSizeBytes: fileSizeBytes,
                purity: purity,
                category: category,
                colors: colors,
                savedAt: savedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String source,
                required String id,
                required String fullImageUrl,
                required String thumbSmallUrl,
                required String thumbLargeUrl,
                required String thumbOriginalUrl,
                required int width,
                required int height,
                required int fileSizeBytes,
                required String purity,
                required String category,
                required String colors,
                required DateTime savedAt,
                Value<int> rowid = const Value.absent(),
              }) => FavoriteWallpapersCompanion.insert(
                source: source,
                id: id,
                fullImageUrl: fullImageUrl,
                thumbSmallUrl: thumbSmallUrl,
                thumbLargeUrl: thumbLargeUrl,
                thumbOriginalUrl: thumbOriginalUrl,
                width: width,
                height: height,
                fileSizeBytes: fileSizeBytes,
                purity: purity,
                category: category,
                colors: colors,
                savedAt: savedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoriteWallpapersTableProcessedTableManager =
    ProcessedTableManager<
      _$TelaDatabase,
      $FavoriteWallpapersTable,
      FavoriteRow,
      $$FavoriteWallpapersTableFilterComposer,
      $$FavoriteWallpapersTableOrderingComposer,
      $$FavoriteWallpapersTableAnnotationComposer,
      $$FavoriteWallpapersTableCreateCompanionBuilder,
      $$FavoriteWallpapersTableUpdateCompanionBuilder,
      (
        FavoriteRow,
        BaseReferences<_$TelaDatabase, $FavoriteWallpapersTable, FavoriteRow>,
      ),
      FavoriteRow,
      PrefetchHooks Function()
    >;
typedef $$DownloadedWallpapersTableCreateCompanionBuilder =
    DownloadedWallpapersCompanion Function({
      required String source,
      required String id,
      required String fullImageUrl,
      required String thumbSmallUrl,
      required String thumbLargeUrl,
      required String thumbOriginalUrl,
      required int width,
      required int height,
      required int fileSizeBytes,
      required String purity,
      required String category,
      required String colors,
      required String tier,
      required String location,
      required DateTime downloadedAt,
      Value<int> rowid,
    });
typedef $$DownloadedWallpapersTableUpdateCompanionBuilder =
    DownloadedWallpapersCompanion Function({
      Value<String> source,
      Value<String> id,
      Value<String> fullImageUrl,
      Value<String> thumbSmallUrl,
      Value<String> thumbLargeUrl,
      Value<String> thumbOriginalUrl,
      Value<int> width,
      Value<int> height,
      Value<int> fileSizeBytes,
      Value<String> purity,
      Value<String> category,
      Value<String> colors,
      Value<String> tier,
      Value<String> location,
      Value<DateTime> downloadedAt,
      Value<int> rowid,
    });

class $$DownloadedWallpapersTableFilterComposer
    extends Composer<_$TelaDatabase, $DownloadedWallpapersTable> {
  $$DownloadedWallpapersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fullImageUrl => $composableBuilder(
    column: $table.fullImageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbSmallUrl => $composableBuilder(
    column: $table.thumbSmallUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbLargeUrl => $composableBuilder(
    column: $table.thumbLargeUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbOriginalUrl => $composableBuilder(
    column: $table.thumbOriginalUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purity => $composableBuilder(
    column: $table.purity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colors => $composableBuilder(
    column: $table.colors,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tier => $composableBuilder(
    column: $table.tier,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadedWallpapersTableOrderingComposer
    extends Composer<_$TelaDatabase, $DownloadedWallpapersTable> {
  $$DownloadedWallpapersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fullImageUrl => $composableBuilder(
    column: $table.fullImageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbSmallUrl => $composableBuilder(
    column: $table.thumbSmallUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbLargeUrl => $composableBuilder(
    column: $table.thumbLargeUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbOriginalUrl => $composableBuilder(
    column: $table.thumbOriginalUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purity => $composableBuilder(
    column: $table.purity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colors => $composableBuilder(
    column: $table.colors,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tier => $composableBuilder(
    column: $table.tier,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadedWallpapersTableAnnotationComposer
    extends Composer<_$TelaDatabase, $DownloadedWallpapersTable> {
  $$DownloadedWallpapersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fullImageUrl => $composableBuilder(
    column: $table.fullImageUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbSmallUrl => $composableBuilder(
    column: $table.thumbSmallUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbLargeUrl => $composableBuilder(
    column: $table.thumbLargeUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbOriginalUrl => $composableBuilder(
    column: $table.thumbOriginalUrl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get purity =>
      $composableBuilder(column: $table.purity, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get colors =>
      $composableBuilder(column: $table.colors, builder: (column) => column);

  GeneratedColumn<String> get tier =>
      $composableBuilder(column: $table.tier, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => column,
  );
}

class $$DownloadedWallpapersTableTableManager
    extends
        RootTableManager<
          _$TelaDatabase,
          $DownloadedWallpapersTable,
          DownloadRow,
          $$DownloadedWallpapersTableFilterComposer,
          $$DownloadedWallpapersTableOrderingComposer,
          $$DownloadedWallpapersTableAnnotationComposer,
          $$DownloadedWallpapersTableCreateCompanionBuilder,
          $$DownloadedWallpapersTableUpdateCompanionBuilder,
          (
            DownloadRow,
            BaseReferences<
              _$TelaDatabase,
              $DownloadedWallpapersTable,
              DownloadRow
            >,
          ),
          DownloadRow,
          PrefetchHooks Function()
        > {
  $$DownloadedWallpapersTableTableManager(
    _$TelaDatabase db,
    $DownloadedWallpapersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadedWallpapersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadedWallpapersTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DownloadedWallpapersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> source = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> fullImageUrl = const Value.absent(),
                Value<String> thumbSmallUrl = const Value.absent(),
                Value<String> thumbLargeUrl = const Value.absent(),
                Value<String> thumbOriginalUrl = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<int> fileSizeBytes = const Value.absent(),
                Value<String> purity = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> colors = const Value.absent(),
                Value<String> tier = const Value.absent(),
                Value<String> location = const Value.absent(),
                Value<DateTime> downloadedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadedWallpapersCompanion(
                source: source,
                id: id,
                fullImageUrl: fullImageUrl,
                thumbSmallUrl: thumbSmallUrl,
                thumbLargeUrl: thumbLargeUrl,
                thumbOriginalUrl: thumbOriginalUrl,
                width: width,
                height: height,
                fileSizeBytes: fileSizeBytes,
                purity: purity,
                category: category,
                colors: colors,
                tier: tier,
                location: location,
                downloadedAt: downloadedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String source,
                required String id,
                required String fullImageUrl,
                required String thumbSmallUrl,
                required String thumbLargeUrl,
                required String thumbOriginalUrl,
                required int width,
                required int height,
                required int fileSizeBytes,
                required String purity,
                required String category,
                required String colors,
                required String tier,
                required String location,
                required DateTime downloadedAt,
                Value<int> rowid = const Value.absent(),
              }) => DownloadedWallpapersCompanion.insert(
                source: source,
                id: id,
                fullImageUrl: fullImageUrl,
                thumbSmallUrl: thumbSmallUrl,
                thumbLargeUrl: thumbLargeUrl,
                thumbOriginalUrl: thumbOriginalUrl,
                width: width,
                height: height,
                fileSizeBytes: fileSizeBytes,
                purity: purity,
                category: category,
                colors: colors,
                tier: tier,
                location: location,
                downloadedAt: downloadedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadedWallpapersTableProcessedTableManager =
    ProcessedTableManager<
      _$TelaDatabase,
      $DownloadedWallpapersTable,
      DownloadRow,
      $$DownloadedWallpapersTableFilterComposer,
      $$DownloadedWallpapersTableOrderingComposer,
      $$DownloadedWallpapersTableAnnotationComposer,
      $$DownloadedWallpapersTableCreateCompanionBuilder,
      $$DownloadedWallpapersTableUpdateCompanionBuilder,
      (
        DownloadRow,
        BaseReferences<_$TelaDatabase, $DownloadedWallpapersTable, DownloadRow>,
      ),
      DownloadRow,
      PrefetchHooks Function()
    >;
typedef $$BlockedTagsTableCreateCompanionBuilder =
    BlockedTagsCompanion Function({
      Value<int> id,
      required String name,
      required DateTime blockedAt,
    });
typedef $$BlockedTagsTableUpdateCompanionBuilder =
    BlockedTagsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<DateTime> blockedAt,
    });

class $$BlockedTagsTableFilterComposer
    extends Composer<_$TelaDatabase, $BlockedTagsTable> {
  $$BlockedTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get blockedAt => $composableBuilder(
    column: $table.blockedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BlockedTagsTableOrderingComposer
    extends Composer<_$TelaDatabase, $BlockedTagsTable> {
  $$BlockedTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get blockedAt => $composableBuilder(
    column: $table.blockedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BlockedTagsTableAnnotationComposer
    extends Composer<_$TelaDatabase, $BlockedTagsTable> {
  $$BlockedTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get blockedAt =>
      $composableBuilder(column: $table.blockedAt, builder: (column) => column);
}

class $$BlockedTagsTableTableManager
    extends
        RootTableManager<
          _$TelaDatabase,
          $BlockedTagsTable,
          BlockedTagRow,
          $$BlockedTagsTableFilterComposer,
          $$BlockedTagsTableOrderingComposer,
          $$BlockedTagsTableAnnotationComposer,
          $$BlockedTagsTableCreateCompanionBuilder,
          $$BlockedTagsTableUpdateCompanionBuilder,
          (
            BlockedTagRow,
            BaseReferences<_$TelaDatabase, $BlockedTagsTable, BlockedTagRow>,
          ),
          BlockedTagRow,
          PrefetchHooks Function()
        > {
  $$BlockedTagsTableTableManager(_$TelaDatabase db, $BlockedTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlockedTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlockedTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlockedTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> blockedAt = const Value.absent(),
              }) => BlockedTagsCompanion(
                id: id,
                name: name,
                blockedAt: blockedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required DateTime blockedAt,
              }) => BlockedTagsCompanion.insert(
                id: id,
                name: name,
                blockedAt: blockedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BlockedTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$TelaDatabase,
      $BlockedTagsTable,
      BlockedTagRow,
      $$BlockedTagsTableFilterComposer,
      $$BlockedTagsTableOrderingComposer,
      $$BlockedTagsTableAnnotationComposer,
      $$BlockedTagsTableCreateCompanionBuilder,
      $$BlockedTagsTableUpdateCompanionBuilder,
      (
        BlockedTagRow,
        BaseReferences<_$TelaDatabase, $BlockedTagsTable, BlockedTagRow>,
      ),
      BlockedTagRow,
      PrefetchHooks Function()
    >;

class $TelaDatabaseManager {
  final _$TelaDatabase _db;
  $TelaDatabaseManager(this._db);
  $$SettingEntriesTableTableManager get settingEntries =>
      $$SettingEntriesTableTableManager(_db, _db.settingEntries);
  $$FavoriteWallpapersTableTableManager get favoriteWallpapers =>
      $$FavoriteWallpapersTableTableManager(_db, _db.favoriteWallpapers);
  $$DownloadedWallpapersTableTableManager get downloadedWallpapers =>
      $$DownloadedWallpapersTableTableManager(_db, _db.downloadedWallpapers);
  $$BlockedTagsTableTableManager get blockedTags =>
      $$BlockedTagsTableTableManager(_db, _db.blockedTags);
}
