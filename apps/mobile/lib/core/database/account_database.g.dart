// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_database.dart';

// ignore_for_file: type=lint
class LocalAccount extends Table
    with TableInfo<LocalAccount, LocalAccountData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LocalAccount(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonMeta = const VerificationMeta(
    'singleton',
  );
  late final GeneratedColumn<int> singleton = GeneratedColumn<int>(
    'singleton',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (singleton = 1)',
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE CHECK (length(user_id) = 36)',
  );
  static const VerificationMeta _environmentMeta = const VerificationMeta(
    'environment',
  );
  late final GeneratedColumn<String> environment = GeneratedColumn<String>(
    'environment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (environment IN (\'dev\', \'staging\', \'prod\'))',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    singleton,
    userId,
    environment,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_account';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalAccountData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton')) {
      context.handle(
        _singletonMeta,
        singleton.isAcceptableOrUnknown(data['singleton']!, _singletonMeta),
      );
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('environment')) {
      context.handle(
        _environmentMeta,
        environment.isAcceptableOrUnknown(
          data['environment']!,
          _environmentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_environmentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  LocalAccountData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalAccountData(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      environment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}environment'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  LocalAccount createAlias(String alias) {
    return LocalAccount(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class LocalAccountData extends DataClass
    implements Insertable<LocalAccountData> {
  final int singleton;
  final String userId;
  final String environment;
  final int createdAt;
  const LocalAccountData({
    required this.singleton,
    required this.userId,
    required this.environment,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    map['user_id'] = Variable<String>(userId);
    map['environment'] = Variable<String>(environment);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  LocalAccountCompanion toCompanion(bool nullToAbsent) {
    return LocalAccountCompanion(
      singleton: Value(singleton),
      userId: Value(userId),
      environment: Value(environment),
      createdAt: Value(createdAt),
    );
  }

  factory LocalAccountData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalAccountData(
      singleton: serializer.fromJson<int>(json['singleton']),
      userId: serializer.fromJson<String>(json['user_id']),
      environment: serializer.fromJson<String>(json['environment']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'user_id': serializer.toJson<String>(userId),
      'environment': serializer.toJson<String>(environment),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  LocalAccountData copyWith({
    int? singleton,
    String? userId,
    String? environment,
    int? createdAt,
  }) => LocalAccountData(
    singleton: singleton ?? this.singleton,
    userId: userId ?? this.userId,
    environment: environment ?? this.environment,
    createdAt: createdAt ?? this.createdAt,
  );
  LocalAccountData copyWithCompanion(LocalAccountCompanion data) {
    return LocalAccountData(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      userId: data.userId.present ? data.userId.value : this.userId,
      environment: data.environment.present
          ? data.environment.value
          : this.environment,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalAccountData(')
          ..write('singleton: $singleton, ')
          ..write('userId: $userId, ')
          ..write('environment: $environment, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(singleton, userId, environment, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAccountData &&
          other.singleton == this.singleton &&
          other.userId == this.userId &&
          other.environment == this.environment &&
          other.createdAt == this.createdAt);
}

class LocalAccountCompanion extends UpdateCompanion<LocalAccountData> {
  final Value<int> singleton;
  final Value<String> userId;
  final Value<String> environment;
  final Value<int> createdAt;
  const LocalAccountCompanion({
    this.singleton = const Value.absent(),
    this.userId = const Value.absent(),
    this.environment = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  LocalAccountCompanion.insert({
    this.singleton = const Value.absent(),
    required String userId,
    required String environment,
    required int createdAt,
  }) : userId = Value(userId),
       environment = Value(environment),
       createdAt = Value(createdAt);
  static Insertable<LocalAccountData> custom({
    Expression<int>? singleton,
    Expression<String>? userId,
    Expression<String>? environment,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (userId != null) 'user_id': userId,
      if (environment != null) 'environment': environment,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  LocalAccountCompanion copyWith({
    Value<int>? singleton,
    Value<String>? userId,
    Value<String>? environment,
    Value<int>? createdAt,
  }) {
    return LocalAccountCompanion(
      singleton: singleton ?? this.singleton,
      userId: userId ?? this.userId,
      environment: environment ?? this.environment,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (environment.present) {
      map['environment'] = Variable<String>(environment.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAccountCompanion(')
          ..write('singleton: $singleton, ')
          ..write('userId: $userId, ')
          ..write('environment: $environment, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class MetadataCopies extends Table
    with TableInfo<MetadataCopies, MetadataCopy> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MetadataCopies(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES local_account(user_id)',
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (entity_type IN (\'SONG\', \'RECORDING\', \'PLAYLIST\', \'PLAYLIST_ITEM\', \'TAG\', \'RECORDING_TAG\', \'RECORDING_CONDITION\', \'RECORDING_FILE_SPEC\', \'RECORDING_ASSET\', \'SONG_CLOUD_SELECTION\', \'PIN_SLOT\', \'USER_ENTITLEMENT\', \'DELETION_LEDGER\'))',
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(entity_id) = 36)',
  );
  static const VerificationMeta _serverRevisionMeta = const VerificationMeta(
    'serverRevision',
  );
  late final GeneratedColumn<int> serverRevision = GeneratedColumn<int>(
    'server_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (server_revision >= 0)',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _serverPayloadMeta = const VerificationMeta(
    'serverPayload',
  );
  late final GeneratedColumn<String> serverPayload = GeneratedColumn<String>(
    'server_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (server_payload IS NULL OR(json_valid(server_payload) AND json_type(server_payload) = \'object\'))',
  );
  static const VerificationMeta _localPayloadMeta = const VerificationMeta(
    'localPayload',
  );
  late final GeneratedColumn<String> localPayload = GeneratedColumn<String>(
    'local_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (local_payload IS NULL OR(json_valid(local_payload) AND json_type(local_payload) = \'object\'))',
  );
  static const VerificationMeta _tombstoneMeta = const VerificationMeta(
    'tombstone',
  );
  late final GeneratedColumn<int> tombstone = GeneratedColumn<int>(
    'tombstone',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (tombstone IN (0, 1))',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    entityType,
    entityId,
    serverRevision,
    serverPayload,
    localPayload,
    tombstone,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'metadata_copies';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetadataCopy> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('server_revision')) {
      context.handle(
        _serverRevisionMeta,
        serverRevision.isAcceptableOrUnknown(
          data['server_revision']!,
          _serverRevisionMeta,
        ),
      );
    }
    if (data.containsKey('server_payload')) {
      context.handle(
        _serverPayloadMeta,
        serverPayload.isAcceptableOrUnknown(
          data['server_payload']!,
          _serverPayloadMeta,
        ),
      );
    }
    if (data.containsKey('local_payload')) {
      context.handle(
        _localPayloadMeta,
        localPayload.isAcceptableOrUnknown(
          data['local_payload']!,
          _localPayloadMeta,
        ),
      );
    }
    if (data.containsKey('tombstone')) {
      context.handle(
        _tombstoneMeta,
        tombstone.isAcceptableOrUnknown(data['tombstone']!, _tombstoneMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entityType, entityId};
  @override
  MetadataCopy map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetadataCopy(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      serverRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_revision'],
      )!,
      serverPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_payload'],
      ),
      localPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_payload'],
      ),
      tombstone: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tombstone'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  MetadataCopies createAlias(String alias) {
    return MetadataCopies(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(entity_type, entity_id)',
    'CHECK((server_revision = 0 AND server_payload IS NULL)OR(server_revision > 0 AND server_payload IS NOT NULL))',
    'CHECK(tombstone = 0 OR server_revision > 0)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class MetadataCopy extends DataClass implements Insertable<MetadataCopy> {
  final String userId;
  final String entityType;
  final String entityId;
  final int serverRevision;
  final String? serverPayload;
  final String? localPayload;
  final int tombstone;
  final int updatedAt;
  const MetadataCopy({
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.serverRevision,
    this.serverPayload,
    this.localPayload,
    required this.tombstone,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['server_revision'] = Variable<int>(serverRevision);
    if (!nullToAbsent || serverPayload != null) {
      map['server_payload'] = Variable<String>(serverPayload);
    }
    if (!nullToAbsent || localPayload != null) {
      map['local_payload'] = Variable<String>(localPayload);
    }
    map['tombstone'] = Variable<int>(tombstone);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  MetadataCopiesCompanion toCompanion(bool nullToAbsent) {
    return MetadataCopiesCompanion(
      userId: Value(userId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      serverRevision: Value(serverRevision),
      serverPayload: serverPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(serverPayload),
      localPayload: localPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(localPayload),
      tombstone: Value(tombstone),
      updatedAt: Value(updatedAt),
    );
  }

  factory MetadataCopy.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetadataCopy(
      userId: serializer.fromJson<String>(json['user_id']),
      entityType: serializer.fromJson<String>(json['entity_type']),
      entityId: serializer.fromJson<String>(json['entity_id']),
      serverRevision: serializer.fromJson<int>(json['server_revision']),
      serverPayload: serializer.fromJson<String?>(json['server_payload']),
      localPayload: serializer.fromJson<String?>(json['local_payload']),
      tombstone: serializer.fromJson<int>(json['tombstone']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'user_id': serializer.toJson<String>(userId),
      'entity_type': serializer.toJson<String>(entityType),
      'entity_id': serializer.toJson<String>(entityId),
      'server_revision': serializer.toJson<int>(serverRevision),
      'server_payload': serializer.toJson<String?>(serverPayload),
      'local_payload': serializer.toJson<String?>(localPayload),
      'tombstone': serializer.toJson<int>(tombstone),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  MetadataCopy copyWith({
    String? userId,
    String? entityType,
    String? entityId,
    int? serverRevision,
    Value<String?> serverPayload = const Value.absent(),
    Value<String?> localPayload = const Value.absent(),
    int? tombstone,
    int? updatedAt,
  }) => MetadataCopy(
    userId: userId ?? this.userId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    serverRevision: serverRevision ?? this.serverRevision,
    serverPayload: serverPayload.present
        ? serverPayload.value
        : this.serverPayload,
    localPayload: localPayload.present ? localPayload.value : this.localPayload,
    tombstone: tombstone ?? this.tombstone,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MetadataCopy copyWithCompanion(MetadataCopiesCompanion data) {
    return MetadataCopy(
      userId: data.userId.present ? data.userId.value : this.userId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      serverRevision: data.serverRevision.present
          ? data.serverRevision.value
          : this.serverRevision,
      serverPayload: data.serverPayload.present
          ? data.serverPayload.value
          : this.serverPayload,
      localPayload: data.localPayload.present
          ? data.localPayload.value
          : this.localPayload,
      tombstone: data.tombstone.present ? data.tombstone.value : this.tombstone,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetadataCopy(')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('serverRevision: $serverRevision, ')
          ..write('serverPayload: $serverPayload, ')
          ..write('localPayload: $localPayload, ')
          ..write('tombstone: $tombstone, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    entityType,
    entityId,
    serverRevision,
    serverPayload,
    localPayload,
    tombstone,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetadataCopy &&
          other.userId == this.userId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.serverRevision == this.serverRevision &&
          other.serverPayload == this.serverPayload &&
          other.localPayload == this.localPayload &&
          other.tombstone == this.tombstone &&
          other.updatedAt == this.updatedAt);
}

class MetadataCopiesCompanion extends UpdateCompanion<MetadataCopy> {
  final Value<String> userId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<int> serverRevision;
  final Value<String?> serverPayload;
  final Value<String?> localPayload;
  final Value<int> tombstone;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const MetadataCopiesCompanion({
    this.userId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.serverRevision = const Value.absent(),
    this.serverPayload = const Value.absent(),
    this.localPayload = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetadataCopiesCompanion.insert({
    required String userId,
    required String entityType,
    required String entityId,
    this.serverRevision = const Value.absent(),
    this.serverPayload = const Value.absent(),
    this.localPayload = const Value.absent(),
    this.tombstone = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       updatedAt = Value(updatedAt);
  static Insertable<MetadataCopy> custom({
    Expression<String>? userId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<int>? serverRevision,
    Expression<String>? serverPayload,
    Expression<String>? localPayload,
    Expression<int>? tombstone,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (serverRevision != null) 'server_revision': serverRevision,
      if (serverPayload != null) 'server_payload': serverPayload,
      if (localPayload != null) 'local_payload': localPayload,
      if (tombstone != null) 'tombstone': tombstone,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetadataCopiesCompanion copyWith({
    Value<String>? userId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<int>? serverRevision,
    Value<String?>? serverPayload,
    Value<String?>? localPayload,
    Value<int>? tombstone,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return MetadataCopiesCompanion(
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      serverRevision: serverRevision ?? this.serverRevision,
      serverPayload: serverPayload ?? this.serverPayload,
      localPayload: localPayload ?? this.localPayload,
      tombstone: tombstone ?? this.tombstone,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (serverRevision.present) {
      map['server_revision'] = Variable<int>(serverRevision.value);
    }
    if (serverPayload.present) {
      map['server_payload'] = Variable<String>(serverPayload.value);
    }
    if (localPayload.present) {
      map['local_payload'] = Variable<String>(localPayload.value);
    }
    if (tombstone.present) {
      map['tombstone'] = Variable<int>(tombstone.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetadataCopiesCompanion(')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('serverRevision: $serverRevision, ')
          ..write('serverPayload: $serverPayload, ')
          ..write('localPayload: $localPayload, ')
          ..write('tombstone: $tombstone, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class LocalMutations extends Table
    with TableInfo<LocalMutations, LocalMutation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LocalMutations(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _opIdMeta = const VerificationMeta('opId');
  late final GeneratedColumn<String> opId = GeneratedColumn<String>(
    'op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(op_id) = 36)',
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES local_account(user_id)',
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (operation IN (\'CREATE\', \'PATCH\', \'TRASH\', \'RESTORE\', \'PURGE\'))',
  );
  static const VerificationMeta _baseRevisionMeta = const VerificationMeta(
    'baseRevision',
  );
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
    'base_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (base_revision >= 0)',
  );
  static const VerificationMeta _basePayloadMeta = const VerificationMeta(
    'basePayload',
  );
  late final GeneratedColumn<String> basePayload = GeneratedColumn<String>(
    'base_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (base_payload IS NULL OR(json_valid(base_payload) AND json_type(base_payload) = \'object\'))',
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(payload) AND json_type(payload) = \'object\')',
  );
  static const VerificationMeta _requestHashMeta = const VerificationMeta(
    'requestHash',
  );
  late final GeneratedColumn<String> requestHash = GeneratedColumn<String>(
    'request_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(request_hash) = 64 AND request_hash NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _queueStateMeta = const VerificationMeta(
    'queueState',
  );
  late final GeneratedColumn<String> queueState = GeneratedColumn<String>(
    'queue_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'PENDING\' CHECK (queue_state IN (\'PENDING\', \'SENDING\', \'RETRY\', \'CONFLICT\', \'ACKED\', \'FAILED\'))',
    defaultValue: const CustomExpression('\'PENDING\''),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (attempt_count >= 0)',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  late final GeneratedColumn<int> nextAttemptAt = GeneratedColumn<int>(
    'next_attempt_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _serverResponseMeta = const VerificationMeta(
    'serverResponse',
  );
  late final GeneratedColumn<String> serverResponse = GeneratedColumn<String>(
    'server_response',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (server_response IS NULL OR(json_valid(server_response) AND json_type(server_response) = \'object\'))',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    opId,
    userId,
    entityType,
    entityId,
    operation,
    baseRevision,
    basePayload,
    payload,
    requestHash,
    queueState,
    attemptCount,
    nextAttemptAt,
    serverResponse,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_mutations';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMutation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('op_id')) {
      context.handle(
        _opIdMeta,
        opId.isAcceptableOrUnknown(data['op_id']!, _opIdMeta),
      );
    } else if (isInserting) {
      context.missing(_opIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('base_revision')) {
      context.handle(
        _baseRevisionMeta,
        baseRevision.isAcceptableOrUnknown(
          data['base_revision']!,
          _baseRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseRevisionMeta);
    }
    if (data.containsKey('base_payload')) {
      context.handle(
        _basePayloadMeta,
        basePayload.isAcceptableOrUnknown(
          data['base_payload']!,
          _basePayloadMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('request_hash')) {
      context.handle(
        _requestHashMeta,
        requestHash.isAcceptableOrUnknown(
          data['request_hash']!,
          _requestHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestHashMeta);
    }
    if (data.containsKey('queue_state')) {
      context.handle(
        _queueStateMeta,
        queueState.isAcceptableOrUnknown(data['queue_state']!, _queueStateMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('server_response')) {
      context.handle(
        _serverResponseMeta,
        serverResponse.isAcceptableOrUnknown(
          data['server_response']!,
          _serverResponseMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {opId};
  @override
  LocalMutation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMutation(
      opId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      )!,
      basePayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_payload'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      requestHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_hash'],
      )!,
      queueState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queue_state'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at'],
      ),
      serverResponse: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_response'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  LocalMutations createAlias(String alias) {
    return LocalMutations(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(entity_type, entity_id)REFERENCES metadata_copies(entity_type, entity_id)',
    'CHECK((base_revision = 0 AND base_payload IS NULL)OR(base_revision > 0 AND base_payload IS NOT NULL))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class LocalMutation extends DataClass implements Insertable<LocalMutation> {
  final String opId;
  final String userId;
  final String entityType;
  final String entityId;
  final String operation;
  final int baseRevision;
  final String? basePayload;
  final String payload;
  final String requestHash;
  final String queueState;
  final int attemptCount;
  final int? nextAttemptAt;
  final String? serverResponse;
  final int createdAt;
  final int updatedAt;
  const LocalMutation({
    required this.opId,
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.baseRevision,
    this.basePayload,
    required this.payload,
    required this.requestHash,
    required this.queueState,
    required this.attemptCount,
    this.nextAttemptAt,
    this.serverResponse,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['op_id'] = Variable<String>(opId);
    map['user_id'] = Variable<String>(userId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['base_revision'] = Variable<int>(baseRevision);
    if (!nullToAbsent || basePayload != null) {
      map['base_payload'] = Variable<String>(basePayload);
    }
    map['payload'] = Variable<String>(payload);
    map['request_hash'] = Variable<String>(requestHash);
    map['queue_state'] = Variable<String>(queueState);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    }
    if (!nullToAbsent || serverResponse != null) {
      map['server_response'] = Variable<String>(serverResponse);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  LocalMutationsCompanion toCompanion(bool nullToAbsent) {
    return LocalMutationsCompanion(
      opId: Value(opId),
      userId: Value(userId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      baseRevision: Value(baseRevision),
      basePayload: basePayload == null && nullToAbsent
          ? const Value.absent()
          : Value(basePayload),
      payload: Value(payload),
      requestHash: Value(requestHash),
      queueState: Value(queueState),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      serverResponse: serverResponse == null && nullToAbsent
          ? const Value.absent()
          : Value(serverResponse),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalMutation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMutation(
      opId: serializer.fromJson<String>(json['op_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      entityType: serializer.fromJson<String>(json['entity_type']),
      entityId: serializer.fromJson<String>(json['entity_id']),
      operation: serializer.fromJson<String>(json['operation']),
      baseRevision: serializer.fromJson<int>(json['base_revision']),
      basePayload: serializer.fromJson<String?>(json['base_payload']),
      payload: serializer.fromJson<String>(json['payload']),
      requestHash: serializer.fromJson<String>(json['request_hash']),
      queueState: serializer.fromJson<String>(json['queue_state']),
      attemptCount: serializer.fromJson<int>(json['attempt_count']),
      nextAttemptAt: serializer.fromJson<int?>(json['next_attempt_at']),
      serverResponse: serializer.fromJson<String?>(json['server_response']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'op_id': serializer.toJson<String>(opId),
      'user_id': serializer.toJson<String>(userId),
      'entity_type': serializer.toJson<String>(entityType),
      'entity_id': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'base_revision': serializer.toJson<int>(baseRevision),
      'base_payload': serializer.toJson<String?>(basePayload),
      'payload': serializer.toJson<String>(payload),
      'request_hash': serializer.toJson<String>(requestHash),
      'queue_state': serializer.toJson<String>(queueState),
      'attempt_count': serializer.toJson<int>(attemptCount),
      'next_attempt_at': serializer.toJson<int?>(nextAttemptAt),
      'server_response': serializer.toJson<String?>(serverResponse),
      'created_at': serializer.toJson<int>(createdAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  LocalMutation copyWith({
    String? opId,
    String? userId,
    String? entityType,
    String? entityId,
    String? operation,
    int? baseRevision,
    Value<String?> basePayload = const Value.absent(),
    String? payload,
    String? requestHash,
    String? queueState,
    int? attemptCount,
    Value<int?> nextAttemptAt = const Value.absent(),
    Value<String?> serverResponse = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => LocalMutation(
    opId: opId ?? this.opId,
    userId: userId ?? this.userId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    baseRevision: baseRevision ?? this.baseRevision,
    basePayload: basePayload.present ? basePayload.value : this.basePayload,
    payload: payload ?? this.payload,
    requestHash: requestHash ?? this.requestHash,
    queueState: queueState ?? this.queueState,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    serverResponse: serverResponse.present
        ? serverResponse.value
        : this.serverResponse,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalMutation copyWithCompanion(LocalMutationsCompanion data) {
    return LocalMutation(
      opId: data.opId.present ? data.opId.value : this.opId,
      userId: data.userId.present ? data.userId.value : this.userId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      basePayload: data.basePayload.present
          ? data.basePayload.value
          : this.basePayload,
      payload: data.payload.present ? data.payload.value : this.payload,
      requestHash: data.requestHash.present
          ? data.requestHash.value
          : this.requestHash,
      queueState: data.queueState.present
          ? data.queueState.value
          : this.queueState,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      serverResponse: data.serverResponse.present
          ? data.serverResponse.value
          : this.serverResponse,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMutation(')
          ..write('opId: $opId, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('basePayload: $basePayload, ')
          ..write('payload: $payload, ')
          ..write('requestHash: $requestHash, ')
          ..write('queueState: $queueState, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('serverResponse: $serverResponse, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    opId,
    userId,
    entityType,
    entityId,
    operation,
    baseRevision,
    basePayload,
    payload,
    requestHash,
    queueState,
    attemptCount,
    nextAttemptAt,
    serverResponse,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMutation &&
          other.opId == this.opId &&
          other.userId == this.userId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.baseRevision == this.baseRevision &&
          other.basePayload == this.basePayload &&
          other.payload == this.payload &&
          other.requestHash == this.requestHash &&
          other.queueState == this.queueState &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.serverResponse == this.serverResponse &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalMutationsCompanion extends UpdateCompanion<LocalMutation> {
  final Value<String> opId;
  final Value<String> userId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<int> baseRevision;
  final Value<String?> basePayload;
  final Value<String> payload;
  final Value<String> requestHash;
  final Value<String> queueState;
  final Value<int> attemptCount;
  final Value<int?> nextAttemptAt;
  final Value<String?> serverResponse;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const LocalMutationsCompanion({
    this.opId = const Value.absent(),
    this.userId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.basePayload = const Value.absent(),
    this.payload = const Value.absent(),
    this.requestHash = const Value.absent(),
    this.queueState = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.serverResponse = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMutationsCompanion.insert({
    required String opId,
    required String userId,
    required String entityType,
    required String entityId,
    required String operation,
    required int baseRevision,
    this.basePayload = const Value.absent(),
    required String payload,
    required String requestHash,
    this.queueState = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.serverResponse = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : opId = Value(opId),
       userId = Value(userId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       baseRevision = Value(baseRevision),
       payload = Value(payload),
       requestHash = Value(requestHash),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalMutation> custom({
    Expression<String>? opId,
    Expression<String>? userId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<int>? baseRevision,
    Expression<String>? basePayload,
    Expression<String>? payload,
    Expression<String>? requestHash,
    Expression<String>? queueState,
    Expression<int>? attemptCount,
    Expression<int>? nextAttemptAt,
    Expression<String>? serverResponse,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (opId != null) 'op_id': opId,
      if (userId != null) 'user_id': userId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (basePayload != null) 'base_payload': basePayload,
      if (payload != null) 'payload': payload,
      if (requestHash != null) 'request_hash': requestHash,
      if (queueState != null) 'queue_state': queueState,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (serverResponse != null) 'server_response': serverResponse,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMutationsCompanion copyWith({
    Value<String>? opId,
    Value<String>? userId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<int>? baseRevision,
    Value<String?>? basePayload,
    Value<String>? payload,
    Value<String>? requestHash,
    Value<String>? queueState,
    Value<int>? attemptCount,
    Value<int?>? nextAttemptAt,
    Value<String?>? serverResponse,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalMutationsCompanion(
      opId: opId ?? this.opId,
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      baseRevision: baseRevision ?? this.baseRevision,
      basePayload: basePayload ?? this.basePayload,
      payload: payload ?? this.payload,
      requestHash: requestHash ?? this.requestHash,
      queueState: queueState ?? this.queueState,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      serverResponse: serverResponse ?? this.serverResponse,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (opId.present) {
      map['op_id'] = Variable<String>(opId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (basePayload.present) {
      map['base_payload'] = Variable<String>(basePayload.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (requestHash.present) {
      map['request_hash'] = Variable<String>(requestHash.value);
    }
    if (queueState.present) {
      map['queue_state'] = Variable<String>(queueState.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (serverResponse.present) {
      map['server_response'] = Variable<String>(serverResponse.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMutationsCompanion(')
          ..write('opId: $opId, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('basePayload: $basePayload, ')
          ..write('payload: $payload, ')
          ..write('requestHash: $requestHash, ')
          ..write('queueState: $queueState, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('serverResponse: $serverResponse, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class LocalRecordingFiles extends Table
    with TableInfo<LocalRecordingFiles, LocalRecordingFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LocalRecordingFiles(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordingIdMeta = const VerificationMeta(
    'recordingId',
  );
  late final GeneratedColumn<String> recordingId = GeneratedColumn<String>(
    'recording_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY CHECK (length(recording_id) = 36)',
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES local_account(user_id)',
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE',
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (sha256 IS NULL OR(length(sha256) = 64 AND sha256 NOT GLOB \'*[^0-9a-f]*\'))',
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (size_bytes IS NULL OR size_bytes BETWEEN 1 AND 6291456)',
  );
  static const VerificationMeta _localStateMeta = const VerificationMeta(
    'localState',
  );
  late final GeneratedColumn<String> localState = GeneratedColumn<String>(
    'local_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (local_state IN (\'CAPTURING\', \'INPUT_PENDING\', \'SAVED\', \'INTERRUPTED\', \'CORRUPT\', \'MISSING\'))',
  );
  static const VerificationMeta _cleanupFenceMeta = const VerificationMeta(
    'cleanupFence',
  );
  late final GeneratedColumn<int> cleanupFence = GeneratedColumn<int>(
    'cleanup_fence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (cleanup_fence >= 0)',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _verifiedAtMeta = const VerificationMeta(
    'verifiedAt',
  );
  late final GeneratedColumn<int> verifiedAt = GeneratedColumn<int>(
    'verified_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    recordingId,
    userId,
    relativePath,
    sha256,
    sizeBytes,
    localState,
    cleanupFence,
    verifiedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_recording_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalRecordingFile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('recording_id')) {
      context.handle(
        _recordingIdMeta,
        recordingId.isAcceptableOrUnknown(
          data['recording_id']!,
          _recordingIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordingIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('local_state')) {
      context.handle(
        _localStateMeta,
        localState.isAcceptableOrUnknown(data['local_state']!, _localStateMeta),
      );
    } else if (isInserting) {
      context.missing(_localStateMeta);
    }
    if (data.containsKey('cleanup_fence')) {
      context.handle(
        _cleanupFenceMeta,
        cleanupFence.isAcceptableOrUnknown(
          data['cleanup_fence']!,
          _cleanupFenceMeta,
        ),
      );
    }
    if (data.containsKey('verified_at')) {
      context.handle(
        _verifiedAtMeta,
        verifiedAt.isAcceptableOrUnknown(data['verified_at']!, _verifiedAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordingId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {userId, recordingId},
  ];
  @override
  LocalRecordingFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRecordingFile(
      recordingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recording_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      ),
      localState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_state'],
      )!,
      cleanupFence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cleanup_fence'],
      )!,
      verifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}verified_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  LocalRecordingFiles createAlias(String alias) {
    return LocalRecordingFiles(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE(user_id, recording_id)',
    'CHECK(relative_path = \'audio/\' || recording_id || \'.m4a\' OR relative_path = \'pending/\' || recording_id || \'.m4a.part\')',
    'CHECK(local_state NOT IN (\'INPUT_PENDING\', \'SAVED\') OR(sha256 IS NOT NULL AND size_bytes IS NOT NULL AND verified_at IS NOT NULL AND relative_path = \'audio/\' || recording_id || \'.m4a\'))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class LocalRecordingFile extends DataClass
    implements Insertable<LocalRecordingFile> {
  final String recordingId;
  final String userId;
  final String relativePath;
  final String? sha256;
  final int? sizeBytes;
  final String localState;
  final int cleanupFence;
  final int? verifiedAt;
  final int updatedAt;
  const LocalRecordingFile({
    required this.recordingId,
    required this.userId,
    required this.relativePath,
    this.sha256,
    this.sizeBytes,
    required this.localState,
    required this.cleanupFence,
    this.verifiedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['recording_id'] = Variable<String>(recordingId);
    map['user_id'] = Variable<String>(userId);
    map['relative_path'] = Variable<String>(relativePath);
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    if (!nullToAbsent || sizeBytes != null) {
      map['size_bytes'] = Variable<int>(sizeBytes);
    }
    map['local_state'] = Variable<String>(localState);
    map['cleanup_fence'] = Variable<int>(cleanupFence);
    if (!nullToAbsent || verifiedAt != null) {
      map['verified_at'] = Variable<int>(verifiedAt);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  LocalRecordingFilesCompanion toCompanion(bool nullToAbsent) {
    return LocalRecordingFilesCompanion(
      recordingId: Value(recordingId),
      userId: Value(userId),
      relativePath: Value(relativePath),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      sizeBytes: sizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeBytes),
      localState: Value(localState),
      cleanupFence: Value(cleanupFence),
      verifiedAt: verifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalRecordingFile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRecordingFile(
      recordingId: serializer.fromJson<String>(json['recording_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      relativePath: serializer.fromJson<String>(json['relative_path']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      sizeBytes: serializer.fromJson<int?>(json['size_bytes']),
      localState: serializer.fromJson<String>(json['local_state']),
      cleanupFence: serializer.fromJson<int>(json['cleanup_fence']),
      verifiedAt: serializer.fromJson<int?>(json['verified_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recording_id': serializer.toJson<String>(recordingId),
      'user_id': serializer.toJson<String>(userId),
      'relative_path': serializer.toJson<String>(relativePath),
      'sha256': serializer.toJson<String?>(sha256),
      'size_bytes': serializer.toJson<int?>(sizeBytes),
      'local_state': serializer.toJson<String>(localState),
      'cleanup_fence': serializer.toJson<int>(cleanupFence),
      'verified_at': serializer.toJson<int?>(verifiedAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  LocalRecordingFile copyWith({
    String? recordingId,
    String? userId,
    String? relativePath,
    Value<String?> sha256 = const Value.absent(),
    Value<int?> sizeBytes = const Value.absent(),
    String? localState,
    int? cleanupFence,
    Value<int?> verifiedAt = const Value.absent(),
    int? updatedAt,
  }) => LocalRecordingFile(
    recordingId: recordingId ?? this.recordingId,
    userId: userId ?? this.userId,
    relativePath: relativePath ?? this.relativePath,
    sha256: sha256.present ? sha256.value : this.sha256,
    sizeBytes: sizeBytes.present ? sizeBytes.value : this.sizeBytes,
    localState: localState ?? this.localState,
    cleanupFence: cleanupFence ?? this.cleanupFence,
    verifiedAt: verifiedAt.present ? verifiedAt.value : this.verifiedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalRecordingFile copyWithCompanion(LocalRecordingFilesCompanion data) {
    return LocalRecordingFile(
      recordingId: data.recordingId.present
          ? data.recordingId.value
          : this.recordingId,
      userId: data.userId.present ? data.userId.value : this.userId,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      localState: data.localState.present
          ? data.localState.value
          : this.localState,
      cleanupFence: data.cleanupFence.present
          ? data.cleanupFence.value
          : this.cleanupFence,
      verifiedAt: data.verifiedAt.present
          ? data.verifiedAt.value
          : this.verifiedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRecordingFile(')
          ..write('recordingId: $recordingId, ')
          ..write('userId: $userId, ')
          ..write('relativePath: $relativePath, ')
          ..write('sha256: $sha256, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('localState: $localState, ')
          ..write('cleanupFence: $cleanupFence, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    recordingId,
    userId,
    relativePath,
    sha256,
    sizeBytes,
    localState,
    cleanupFence,
    verifiedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRecordingFile &&
          other.recordingId == this.recordingId &&
          other.userId == this.userId &&
          other.relativePath == this.relativePath &&
          other.sha256 == this.sha256 &&
          other.sizeBytes == this.sizeBytes &&
          other.localState == this.localState &&
          other.cleanupFence == this.cleanupFence &&
          other.verifiedAt == this.verifiedAt &&
          other.updatedAt == this.updatedAt);
}

class LocalRecordingFilesCompanion extends UpdateCompanion<LocalRecordingFile> {
  final Value<String> recordingId;
  final Value<String> userId;
  final Value<String> relativePath;
  final Value<String?> sha256;
  final Value<int?> sizeBytes;
  final Value<String> localState;
  final Value<int> cleanupFence;
  final Value<int?> verifiedAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const LocalRecordingFilesCompanion({
    this.recordingId = const Value.absent(),
    this.userId = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.localState = const Value.absent(),
    this.cleanupFence = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalRecordingFilesCompanion.insert({
    required String recordingId,
    required String userId,
    required String relativePath,
    this.sha256 = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    required String localState,
    this.cleanupFence = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : recordingId = Value(recordingId),
       userId = Value(userId),
       relativePath = Value(relativePath),
       localState = Value(localState),
       updatedAt = Value(updatedAt);
  static Insertable<LocalRecordingFile> custom({
    Expression<String>? recordingId,
    Expression<String>? userId,
    Expression<String>? relativePath,
    Expression<String>? sha256,
    Expression<int>? sizeBytes,
    Expression<String>? localState,
    Expression<int>? cleanupFence,
    Expression<int>? verifiedAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordingId != null) 'recording_id': recordingId,
      if (userId != null) 'user_id': userId,
      if (relativePath != null) 'relative_path': relativePath,
      if (sha256 != null) 'sha256': sha256,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (localState != null) 'local_state': localState,
      if (cleanupFence != null) 'cleanup_fence': cleanupFence,
      if (verifiedAt != null) 'verified_at': verifiedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalRecordingFilesCompanion copyWith({
    Value<String>? recordingId,
    Value<String>? userId,
    Value<String>? relativePath,
    Value<String?>? sha256,
    Value<int?>? sizeBytes,
    Value<String>? localState,
    Value<int>? cleanupFence,
    Value<int?>? verifiedAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalRecordingFilesCompanion(
      recordingId: recordingId ?? this.recordingId,
      userId: userId ?? this.userId,
      relativePath: relativePath ?? this.relativePath,
      sha256: sha256 ?? this.sha256,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      localState: localState ?? this.localState,
      cleanupFence: cleanupFence ?? this.cleanupFence,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordingId.present) {
      map['recording_id'] = Variable<String>(recordingId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (localState.present) {
      map['local_state'] = Variable<String>(localState.value);
    }
    if (cleanupFence.present) {
      map['cleanup_fence'] = Variable<int>(cleanupFence.value);
    }
    if (verifiedAt.present) {
      map['verified_at'] = Variable<int>(verifiedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalRecordingFilesCompanion(')
          ..write('recordingId: $recordingId, ')
          ..write('userId: $userId, ')
          ..write('relativePath: $relativePath, ')
          ..write('sha256: $sha256, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('localState: $localState, ')
          ..write('cleanupFence: $cleanupFence, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class RecordingJournals extends Table
    with TableInfo<RecordingJournals, RecordingJournal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RecordingJournals(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordingIdMeta = const VerificationMeta(
    'recordingId',
  );
  late final GeneratedColumn<String> recordingId = GeneratedColumn<String>(
    'recording_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE CHECK (length(operation_id) = 36)',
  );
  static const VerificationMeta _pendingPathMeta = const VerificationMeta(
    'pendingPath',
  );
  late final GeneratedColumn<String> pendingPath = GeneratedColumn<String>(
    'pending_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _finalPathMeta = const VerificationMeta(
    'finalPath',
  );
  late final GeneratedColumn<String> finalPath = GeneratedColumn<String>(
    'final_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (phase IN (\'PREPARING\', \'CAPTURING\', \'FINALIZING\', \'VERIFIED\', \'COMMITTED\', \'FAILED\'))',
  );
  static const VerificationMeta _recoveryPayloadMeta = const VerificationMeta(
    'recoveryPayload',
  );
  late final GeneratedColumn<String> recoveryPayload = GeneratedColumn<String>(
    'recovery_payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(recovery_payload) AND json_type(recovery_payload) = \'object\')',
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 1 CHECK (revision > 0)',
    defaultValue: const CustomExpression('1'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    recordingId,
    userId,
    operationId,
    pendingPath,
    finalPath,
    phase,
    recoveryPayload,
    revision,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recording_journals';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecordingJournal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('recording_id')) {
      context.handle(
        _recordingIdMeta,
        recordingId.isAcceptableOrUnknown(
          data['recording_id']!,
          _recordingIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordingIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('pending_path')) {
      context.handle(
        _pendingPathMeta,
        pendingPath.isAcceptableOrUnknown(
          data['pending_path']!,
          _pendingPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pendingPathMeta);
    }
    if (data.containsKey('final_path')) {
      context.handle(
        _finalPathMeta,
        finalPath.isAcceptableOrUnknown(data['final_path']!, _finalPathMeta),
      );
    } else if (isInserting) {
      context.missing(_finalPathMeta);
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    } else if (isInserting) {
      context.missing(_phaseMeta);
    }
    if (data.containsKey('recovery_payload')) {
      context.handle(
        _recoveryPayloadMeta,
        recoveryPayload.isAcceptableOrUnknown(
          data['recovery_payload']!,
          _recoveryPayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recoveryPayloadMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordingId};
  @override
  RecordingJournal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecordingJournal(
      recordingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recording_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      pendingPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pending_path'],
      )!,
      finalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}final_path'],
      )!,
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      )!,
      recoveryPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recovery_payload'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  RecordingJournals createAlias(String alias) {
    return RecordingJournals(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(user_id, recording_id)REFERENCES local_recording_files(user_id, recording_id)',
    'CHECK(pending_path = \'pending/\' || recording_id || \'.m4a.part\')',
    'CHECK(final_path = \'audio/\' || recording_id || \'.m4a\')',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class RecordingJournal extends DataClass
    implements Insertable<RecordingJournal> {
  final String recordingId;
  final String userId;
  final String operationId;
  final String pendingPath;
  final String finalPath;
  final String phase;
  final String recoveryPayload;
  final int revision;
  final int updatedAt;
  const RecordingJournal({
    required this.recordingId,
    required this.userId,
    required this.operationId,
    required this.pendingPath,
    required this.finalPath,
    required this.phase,
    required this.recoveryPayload,
    required this.revision,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['recording_id'] = Variable<String>(recordingId);
    map['user_id'] = Variable<String>(userId);
    map['operation_id'] = Variable<String>(operationId);
    map['pending_path'] = Variable<String>(pendingPath);
    map['final_path'] = Variable<String>(finalPath);
    map['phase'] = Variable<String>(phase);
    map['recovery_payload'] = Variable<String>(recoveryPayload);
    map['revision'] = Variable<int>(revision);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  RecordingJournalsCompanion toCompanion(bool nullToAbsent) {
    return RecordingJournalsCompanion(
      recordingId: Value(recordingId),
      userId: Value(userId),
      operationId: Value(operationId),
      pendingPath: Value(pendingPath),
      finalPath: Value(finalPath),
      phase: Value(phase),
      recoveryPayload: Value(recoveryPayload),
      revision: Value(revision),
      updatedAt: Value(updatedAt),
    );
  }

  factory RecordingJournal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecordingJournal(
      recordingId: serializer.fromJson<String>(json['recording_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      operationId: serializer.fromJson<String>(json['operation_id']),
      pendingPath: serializer.fromJson<String>(json['pending_path']),
      finalPath: serializer.fromJson<String>(json['final_path']),
      phase: serializer.fromJson<String>(json['phase']),
      recoveryPayload: serializer.fromJson<String>(json['recovery_payload']),
      revision: serializer.fromJson<int>(json['revision']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recording_id': serializer.toJson<String>(recordingId),
      'user_id': serializer.toJson<String>(userId),
      'operation_id': serializer.toJson<String>(operationId),
      'pending_path': serializer.toJson<String>(pendingPath),
      'final_path': serializer.toJson<String>(finalPath),
      'phase': serializer.toJson<String>(phase),
      'recovery_payload': serializer.toJson<String>(recoveryPayload),
      'revision': serializer.toJson<int>(revision),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  RecordingJournal copyWith({
    String? recordingId,
    String? userId,
    String? operationId,
    String? pendingPath,
    String? finalPath,
    String? phase,
    String? recoveryPayload,
    int? revision,
    int? updatedAt,
  }) => RecordingJournal(
    recordingId: recordingId ?? this.recordingId,
    userId: userId ?? this.userId,
    operationId: operationId ?? this.operationId,
    pendingPath: pendingPath ?? this.pendingPath,
    finalPath: finalPath ?? this.finalPath,
    phase: phase ?? this.phase,
    recoveryPayload: recoveryPayload ?? this.recoveryPayload,
    revision: revision ?? this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RecordingJournal copyWithCompanion(RecordingJournalsCompanion data) {
    return RecordingJournal(
      recordingId: data.recordingId.present
          ? data.recordingId.value
          : this.recordingId,
      userId: data.userId.present ? data.userId.value : this.userId,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      pendingPath: data.pendingPath.present
          ? data.pendingPath.value
          : this.pendingPath,
      finalPath: data.finalPath.present ? data.finalPath.value : this.finalPath,
      phase: data.phase.present ? data.phase.value : this.phase,
      recoveryPayload: data.recoveryPayload.present
          ? data.recoveryPayload.value
          : this.recoveryPayload,
      revision: data.revision.present ? data.revision.value : this.revision,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecordingJournal(')
          ..write('recordingId: $recordingId, ')
          ..write('userId: $userId, ')
          ..write('operationId: $operationId, ')
          ..write('pendingPath: $pendingPath, ')
          ..write('finalPath: $finalPath, ')
          ..write('phase: $phase, ')
          ..write('recoveryPayload: $recoveryPayload, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    recordingId,
    userId,
    operationId,
    pendingPath,
    finalPath,
    phase,
    recoveryPayload,
    revision,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecordingJournal &&
          other.recordingId == this.recordingId &&
          other.userId == this.userId &&
          other.operationId == this.operationId &&
          other.pendingPath == this.pendingPath &&
          other.finalPath == this.finalPath &&
          other.phase == this.phase &&
          other.recoveryPayload == this.recoveryPayload &&
          other.revision == this.revision &&
          other.updatedAt == this.updatedAt);
}

class RecordingJournalsCompanion extends UpdateCompanion<RecordingJournal> {
  final Value<String> recordingId;
  final Value<String> userId;
  final Value<String> operationId;
  final Value<String> pendingPath;
  final Value<String> finalPath;
  final Value<String> phase;
  final Value<String> recoveryPayload;
  final Value<int> revision;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const RecordingJournalsCompanion({
    this.recordingId = const Value.absent(),
    this.userId = const Value.absent(),
    this.operationId = const Value.absent(),
    this.pendingPath = const Value.absent(),
    this.finalPath = const Value.absent(),
    this.phase = const Value.absent(),
    this.recoveryPayload = const Value.absent(),
    this.revision = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordingJournalsCompanion.insert({
    required String recordingId,
    required String userId,
    required String operationId,
    required String pendingPath,
    required String finalPath,
    required String phase,
    required String recoveryPayload,
    this.revision = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : recordingId = Value(recordingId),
       userId = Value(userId),
       operationId = Value(operationId),
       pendingPath = Value(pendingPath),
       finalPath = Value(finalPath),
       phase = Value(phase),
       recoveryPayload = Value(recoveryPayload),
       updatedAt = Value(updatedAt);
  static Insertable<RecordingJournal> custom({
    Expression<String>? recordingId,
    Expression<String>? userId,
    Expression<String>? operationId,
    Expression<String>? pendingPath,
    Expression<String>? finalPath,
    Expression<String>? phase,
    Expression<String>? recoveryPayload,
    Expression<int>? revision,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordingId != null) 'recording_id': recordingId,
      if (userId != null) 'user_id': userId,
      if (operationId != null) 'operation_id': operationId,
      if (pendingPath != null) 'pending_path': pendingPath,
      if (finalPath != null) 'final_path': finalPath,
      if (phase != null) 'phase': phase,
      if (recoveryPayload != null) 'recovery_payload': recoveryPayload,
      if (revision != null) 'revision': revision,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordingJournalsCompanion copyWith({
    Value<String>? recordingId,
    Value<String>? userId,
    Value<String>? operationId,
    Value<String>? pendingPath,
    Value<String>? finalPath,
    Value<String>? phase,
    Value<String>? recoveryPayload,
    Value<int>? revision,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return RecordingJournalsCompanion(
      recordingId: recordingId ?? this.recordingId,
      userId: userId ?? this.userId,
      operationId: operationId ?? this.operationId,
      pendingPath: pendingPath ?? this.pendingPath,
      finalPath: finalPath ?? this.finalPath,
      phase: phase ?? this.phase,
      recoveryPayload: recoveryPayload ?? this.recoveryPayload,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordingId.present) {
      map['recording_id'] = Variable<String>(recordingId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (pendingPath.present) {
      map['pending_path'] = Variable<String>(pendingPath.value);
    }
    if (finalPath.present) {
      map['final_path'] = Variable<String>(finalPath.value);
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (recoveryPayload.present) {
      map['recovery_payload'] = Variable<String>(recoveryPayload.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordingJournalsCompanion(')
          ..write('recordingId: $recordingId, ')
          ..write('userId: $userId, ')
          ..write('operationId: $operationId, ')
          ..write('pendingPath: $pendingPath, ')
          ..write('finalPath: $finalPath, ')
          ..write('phase: $phase, ')
          ..write('recoveryPayload: $recoveryPayload, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ImportJobs extends Table with TableInfo<ImportJobs, ImportJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ImportJobs(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _importJobIdMeta = const VerificationMeta(
    'importJobId',
  );
  late final GeneratedColumn<String> importJobId = GeneratedColumn<String>(
    'import_job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY CHECK (length(import_job_id) = 36)',
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES local_account(user_id)',
  );
  static const VerificationMeta _sourceUserIdMeta = const VerificationMeta(
    'sourceUserId',
  );
  late final GeneratedColumn<String> sourceUserId = GeneratedColumn<String>(
    'source_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (source_user_id = user_id)',
  );
  static const VerificationMeta _archivePathMeta = const VerificationMeta(
    'archivePath',
  );
  late final GeneratedColumn<String> archivePath = GeneratedColumn<String>(
    'archive_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _manifestHashMeta = const VerificationMeta(
    'manifestHash',
  );
  late final GeneratedColumn<String> manifestHash = GeneratedColumn<String>(
    'manifest_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(manifest_hash) = 64 AND manifest_hash NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'PENDING\' CHECK (status IN (\'PENDING\', \'RUNNING\', \'PAUSED\', \'COMPLETED\', \'FAILED\'))',
    defaultValue: const CustomExpression('\'PENDING\''),
  );
  static const VerificationMeta _totalItemsMeta = const VerificationMeta(
    'totalItems',
  );
  late final GeneratedColumn<int> totalItems = GeneratedColumn<int>(
    'total_items',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (total_items >= 0)',
  );
  static const VerificationMeta _completedItemsMeta = const VerificationMeta(
    'completedItems',
  );
  late final GeneratedColumn<int> completedItems = GeneratedColumn<int>(
    'completed_items',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT 0 CHECK (completed_items BETWEEN 0 AND total_items)',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    importJobId,
    userId,
    sourceUserId,
    archivePath,
    manifestHash,
    status,
    totalItems,
    completedItems,
    errorCode,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('import_job_id')) {
      context.handle(
        _importJobIdMeta,
        importJobId.isAcceptableOrUnknown(
          data['import_job_id']!,
          _importJobIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_importJobIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('source_user_id')) {
      context.handle(
        _sourceUserIdMeta,
        sourceUserId.isAcceptableOrUnknown(
          data['source_user_id']!,
          _sourceUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceUserIdMeta);
    }
    if (data.containsKey('archive_path')) {
      context.handle(
        _archivePathMeta,
        archivePath.isAcceptableOrUnknown(
          data['archive_path']!,
          _archivePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_archivePathMeta);
    }
    if (data.containsKey('manifest_hash')) {
      context.handle(
        _manifestHashMeta,
        manifestHash.isAcceptableOrUnknown(
          data['manifest_hash']!,
          _manifestHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manifestHashMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('total_items')) {
      context.handle(
        _totalItemsMeta,
        totalItems.isAcceptableOrUnknown(data['total_items']!, _totalItemsMeta),
      );
    } else if (isInserting) {
      context.missing(_totalItemsMeta);
    }
    if (data.containsKey('completed_items')) {
      context.handle(
        _completedItemsMeta,
        completedItems.isAcceptableOrUnknown(
          data['completed_items']!,
          _completedItemsMeta,
        ),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {importJobId};
  @override
  ImportJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportJob(
      importJobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_job_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      sourceUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_user_id'],
      )!,
      archivePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}archive_path'],
      )!,
      manifestHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifest_hash'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      totalItems: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_items'],
      )!,
      completedItems: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_items'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  ImportJobs createAlias(String alias) {
    return ImportJobs(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK(archive_path = \'imports/\' || import_job_id || \'.zip\')',
    'CHECK(status <> \'COMPLETED\' OR completed_items = total_items)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ImportJob extends DataClass implements Insertable<ImportJob> {
  final String importJobId;
  final String userId;
  final String sourceUserId;
  final String archivePath;
  final String manifestHash;
  final String status;
  final int totalItems;
  final int completedItems;
  final String? errorCode;
  final int createdAt;
  final int updatedAt;
  const ImportJob({
    required this.importJobId,
    required this.userId,
    required this.sourceUserId,
    required this.archivePath,
    required this.manifestHash,
    required this.status,
    required this.totalItems,
    required this.completedItems,
    this.errorCode,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['import_job_id'] = Variable<String>(importJobId);
    map['user_id'] = Variable<String>(userId);
    map['source_user_id'] = Variable<String>(sourceUserId);
    map['archive_path'] = Variable<String>(archivePath);
    map['manifest_hash'] = Variable<String>(manifestHash);
    map['status'] = Variable<String>(status);
    map['total_items'] = Variable<int>(totalItems);
    map['completed_items'] = Variable<int>(completedItems);
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ImportJobsCompanion toCompanion(bool nullToAbsent) {
    return ImportJobsCompanion(
      importJobId: Value(importJobId),
      userId: Value(userId),
      sourceUserId: Value(sourceUserId),
      archivePath: Value(archivePath),
      manifestHash: Value(manifestHash),
      status: Value(status),
      totalItems: Value(totalItems),
      completedItems: Value(completedItems),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ImportJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportJob(
      importJobId: serializer.fromJson<String>(json['import_job_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      sourceUserId: serializer.fromJson<String>(json['source_user_id']),
      archivePath: serializer.fromJson<String>(json['archive_path']),
      manifestHash: serializer.fromJson<String>(json['manifest_hash']),
      status: serializer.fromJson<String>(json['status']),
      totalItems: serializer.fromJson<int>(json['total_items']),
      completedItems: serializer.fromJson<int>(json['completed_items']),
      errorCode: serializer.fromJson<String?>(json['error_code']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'import_job_id': serializer.toJson<String>(importJobId),
      'user_id': serializer.toJson<String>(userId),
      'source_user_id': serializer.toJson<String>(sourceUserId),
      'archive_path': serializer.toJson<String>(archivePath),
      'manifest_hash': serializer.toJson<String>(manifestHash),
      'status': serializer.toJson<String>(status),
      'total_items': serializer.toJson<int>(totalItems),
      'completed_items': serializer.toJson<int>(completedItems),
      'error_code': serializer.toJson<String?>(errorCode),
      'created_at': serializer.toJson<int>(createdAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  ImportJob copyWith({
    String? importJobId,
    String? userId,
    String? sourceUserId,
    String? archivePath,
    String? manifestHash,
    String? status,
    int? totalItems,
    int? completedItems,
    Value<String?> errorCode = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => ImportJob(
    importJobId: importJobId ?? this.importJobId,
    userId: userId ?? this.userId,
    sourceUserId: sourceUserId ?? this.sourceUserId,
    archivePath: archivePath ?? this.archivePath,
    manifestHash: manifestHash ?? this.manifestHash,
    status: status ?? this.status,
    totalItems: totalItems ?? this.totalItems,
    completedItems: completedItems ?? this.completedItems,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ImportJob copyWithCompanion(ImportJobsCompanion data) {
    return ImportJob(
      importJobId: data.importJobId.present
          ? data.importJobId.value
          : this.importJobId,
      userId: data.userId.present ? data.userId.value : this.userId,
      sourceUserId: data.sourceUserId.present
          ? data.sourceUserId.value
          : this.sourceUserId,
      archivePath: data.archivePath.present
          ? data.archivePath.value
          : this.archivePath,
      manifestHash: data.manifestHash.present
          ? data.manifestHash.value
          : this.manifestHash,
      status: data.status.present ? data.status.value : this.status,
      totalItems: data.totalItems.present
          ? data.totalItems.value
          : this.totalItems,
      completedItems: data.completedItems.present
          ? data.completedItems.value
          : this.completedItems,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportJob(')
          ..write('importJobId: $importJobId, ')
          ..write('userId: $userId, ')
          ..write('sourceUserId: $sourceUserId, ')
          ..write('archivePath: $archivePath, ')
          ..write('manifestHash: $manifestHash, ')
          ..write('status: $status, ')
          ..write('totalItems: $totalItems, ')
          ..write('completedItems: $completedItems, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    importJobId,
    userId,
    sourceUserId,
    archivePath,
    manifestHash,
    status,
    totalItems,
    completedItems,
    errorCode,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportJob &&
          other.importJobId == this.importJobId &&
          other.userId == this.userId &&
          other.sourceUserId == this.sourceUserId &&
          other.archivePath == this.archivePath &&
          other.manifestHash == this.manifestHash &&
          other.status == this.status &&
          other.totalItems == this.totalItems &&
          other.completedItems == this.completedItems &&
          other.errorCode == this.errorCode &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ImportJobsCompanion extends UpdateCompanion<ImportJob> {
  final Value<String> importJobId;
  final Value<String> userId;
  final Value<String> sourceUserId;
  final Value<String> archivePath;
  final Value<String> manifestHash;
  final Value<String> status;
  final Value<int> totalItems;
  final Value<int> completedItems;
  final Value<String?> errorCode;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ImportJobsCompanion({
    this.importJobId = const Value.absent(),
    this.userId = const Value.absent(),
    this.sourceUserId = const Value.absent(),
    this.archivePath = const Value.absent(),
    this.manifestHash = const Value.absent(),
    this.status = const Value.absent(),
    this.totalItems = const Value.absent(),
    this.completedItems = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportJobsCompanion.insert({
    required String importJobId,
    required String userId,
    required String sourceUserId,
    required String archivePath,
    required String manifestHash,
    this.status = const Value.absent(),
    required int totalItems,
    this.completedItems = const Value.absent(),
    this.errorCode = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : importJobId = Value(importJobId),
       userId = Value(userId),
       sourceUserId = Value(sourceUserId),
       archivePath = Value(archivePath),
       manifestHash = Value(manifestHash),
       totalItems = Value(totalItems),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ImportJob> custom({
    Expression<String>? importJobId,
    Expression<String>? userId,
    Expression<String>? sourceUserId,
    Expression<String>? archivePath,
    Expression<String>? manifestHash,
    Expression<String>? status,
    Expression<int>? totalItems,
    Expression<int>? completedItems,
    Expression<String>? errorCode,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (importJobId != null) 'import_job_id': importJobId,
      if (userId != null) 'user_id': userId,
      if (sourceUserId != null) 'source_user_id': sourceUserId,
      if (archivePath != null) 'archive_path': archivePath,
      if (manifestHash != null) 'manifest_hash': manifestHash,
      if (status != null) 'status': status,
      if (totalItems != null) 'total_items': totalItems,
      if (completedItems != null) 'completed_items': completedItems,
      if (errorCode != null) 'error_code': errorCode,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportJobsCompanion copyWith({
    Value<String>? importJobId,
    Value<String>? userId,
    Value<String>? sourceUserId,
    Value<String>? archivePath,
    Value<String>? manifestHash,
    Value<String>? status,
    Value<int>? totalItems,
    Value<int>? completedItems,
    Value<String?>? errorCode,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ImportJobsCompanion(
      importJobId: importJobId ?? this.importJobId,
      userId: userId ?? this.userId,
      sourceUserId: sourceUserId ?? this.sourceUserId,
      archivePath: archivePath ?? this.archivePath,
      manifestHash: manifestHash ?? this.manifestHash,
      status: status ?? this.status,
      totalItems: totalItems ?? this.totalItems,
      completedItems: completedItems ?? this.completedItems,
      errorCode: errorCode ?? this.errorCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (importJobId.present) {
      map['import_job_id'] = Variable<String>(importJobId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (sourceUserId.present) {
      map['source_user_id'] = Variable<String>(sourceUserId.value);
    }
    if (archivePath.present) {
      map['archive_path'] = Variable<String>(archivePath.value);
    }
    if (manifestHash.present) {
      map['manifest_hash'] = Variable<String>(manifestHash.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (totalItems.present) {
      map['total_items'] = Variable<int>(totalItems.value);
    }
    if (completedItems.present) {
      map['completed_items'] = Variable<int>(completedItems.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportJobsCompanion(')
          ..write('importJobId: $importJobId, ')
          ..write('userId: $userId, ')
          ..write('sourceUserId: $sourceUserId, ')
          ..write('archivePath: $archivePath, ')
          ..write('manifestHash: $manifestHash, ')
          ..write('status: $status, ')
          ..write('totalItems: $totalItems, ')
          ..write('completedItems: $completedItems, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ImportItems extends Table with TableInfo<ImportItems, ImportItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ImportItems(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _importJobIdMeta = const VerificationMeta(
    'importJobId',
  );
  late final GeneratedColumn<String> importJobId = GeneratedColumn<String>(
    'import_job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES import_jobs(import_job_id)',
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (ordinal > 0)',
  );
  static const VerificationMeta _resourceIdMeta = const VerificationMeta(
    'resourceId',
  );
  late final GeneratedColumn<String> resourceId = GeneratedColumn<String>(
    'resource_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(resource_id) = 36)',
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'PENDING\' CHECK (status IN (\'PENDING\', \'APPLIED\', \'SKIPPED\', \'CONFLICT\', \'FAILED\'))',
    defaultValue: const CustomExpression('\'PENDING\''),
  );
  static const VerificationMeta _resultPayloadMeta = const VerificationMeta(
    'resultPayload',
  );
  late final GeneratedColumn<String> resultPayload = GeneratedColumn<String>(
    'result_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (result_payload IS NULL OR(json_valid(result_payload) AND json_type(result_payload) = \'object\'))',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    importJobId,
    ordinal,
    resourceId,
    status,
    resultPayload,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('import_job_id')) {
      context.handle(
        _importJobIdMeta,
        importJobId.isAcceptableOrUnknown(
          data['import_job_id']!,
          _importJobIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_importJobIdMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('resource_id')) {
      context.handle(
        _resourceIdMeta,
        resourceId.isAcceptableOrUnknown(data['resource_id']!, _resourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_resourceIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('result_payload')) {
      context.handle(
        _resultPayloadMeta,
        resultPayload.isAcceptableOrUnknown(
          data['result_payload']!,
          _resultPayloadMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {importJobId, ordinal};
  @override
  ImportItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportItem(
      importJobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_job_id'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      resourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      resultPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_payload'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  ImportItems createAlias(String alias) {
    return ImportItems(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(import_job_id, ordinal)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ImportItem extends DataClass implements Insertable<ImportItem> {
  final String importJobId;
  final int ordinal;
  final String resourceId;
  final String status;
  final String? resultPayload;
  final int updatedAt;
  const ImportItem({
    required this.importJobId,
    required this.ordinal,
    required this.resourceId,
    required this.status,
    this.resultPayload,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['import_job_id'] = Variable<String>(importJobId);
    map['ordinal'] = Variable<int>(ordinal);
    map['resource_id'] = Variable<String>(resourceId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || resultPayload != null) {
      map['result_payload'] = Variable<String>(resultPayload);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ImportItemsCompanion toCompanion(bool nullToAbsent) {
    return ImportItemsCompanion(
      importJobId: Value(importJobId),
      ordinal: Value(ordinal),
      resourceId: Value(resourceId),
      status: Value(status),
      resultPayload: resultPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(resultPayload),
      updatedAt: Value(updatedAt),
    );
  }

  factory ImportItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportItem(
      importJobId: serializer.fromJson<String>(json['import_job_id']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      resourceId: serializer.fromJson<String>(json['resource_id']),
      status: serializer.fromJson<String>(json['status']),
      resultPayload: serializer.fromJson<String?>(json['result_payload']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'import_job_id': serializer.toJson<String>(importJobId),
      'ordinal': serializer.toJson<int>(ordinal),
      'resource_id': serializer.toJson<String>(resourceId),
      'status': serializer.toJson<String>(status),
      'result_payload': serializer.toJson<String?>(resultPayload),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  ImportItem copyWith({
    String? importJobId,
    int? ordinal,
    String? resourceId,
    String? status,
    Value<String?> resultPayload = const Value.absent(),
    int? updatedAt,
  }) => ImportItem(
    importJobId: importJobId ?? this.importJobId,
    ordinal: ordinal ?? this.ordinal,
    resourceId: resourceId ?? this.resourceId,
    status: status ?? this.status,
    resultPayload: resultPayload.present
        ? resultPayload.value
        : this.resultPayload,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ImportItem copyWithCompanion(ImportItemsCompanion data) {
    return ImportItem(
      importJobId: data.importJobId.present
          ? data.importJobId.value
          : this.importJobId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      resourceId: data.resourceId.present
          ? data.resourceId.value
          : this.resourceId,
      status: data.status.present ? data.status.value : this.status,
      resultPayload: data.resultPayload.present
          ? data.resultPayload.value
          : this.resultPayload,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportItem(')
          ..write('importJobId: $importJobId, ')
          ..write('ordinal: $ordinal, ')
          ..write('resourceId: $resourceId, ')
          ..write('status: $status, ')
          ..write('resultPayload: $resultPayload, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    importJobId,
    ordinal,
    resourceId,
    status,
    resultPayload,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportItem &&
          other.importJobId == this.importJobId &&
          other.ordinal == this.ordinal &&
          other.resourceId == this.resourceId &&
          other.status == this.status &&
          other.resultPayload == this.resultPayload &&
          other.updatedAt == this.updatedAt);
}

class ImportItemsCompanion extends UpdateCompanion<ImportItem> {
  final Value<String> importJobId;
  final Value<int> ordinal;
  final Value<String> resourceId;
  final Value<String> status;
  final Value<String?> resultPayload;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ImportItemsCompanion({
    this.importJobId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.resourceId = const Value.absent(),
    this.status = const Value.absent(),
    this.resultPayload = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportItemsCompanion.insert({
    required String importJobId,
    required int ordinal,
    required String resourceId,
    this.status = const Value.absent(),
    this.resultPayload = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : importJobId = Value(importJobId),
       ordinal = Value(ordinal),
       resourceId = Value(resourceId),
       updatedAt = Value(updatedAt);
  static Insertable<ImportItem> custom({
    Expression<String>? importJobId,
    Expression<int>? ordinal,
    Expression<String>? resourceId,
    Expression<String>? status,
    Expression<String>? resultPayload,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (importJobId != null) 'import_job_id': importJobId,
      if (ordinal != null) 'ordinal': ordinal,
      if (resourceId != null) 'resource_id': resourceId,
      if (status != null) 'status': status,
      if (resultPayload != null) 'result_payload': resultPayload,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportItemsCompanion copyWith({
    Value<String>? importJobId,
    Value<int>? ordinal,
    Value<String>? resourceId,
    Value<String>? status,
    Value<String?>? resultPayload,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ImportItemsCompanion(
      importJobId: importJobId ?? this.importJobId,
      ordinal: ordinal ?? this.ordinal,
      resourceId: resourceId ?? this.resourceId,
      status: status ?? this.status,
      resultPayload: resultPayload ?? this.resultPayload,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (importJobId.present) {
      map['import_job_id'] = Variable<String>(importJobId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (resourceId.present) {
      map['resource_id'] = Variable<String>(resourceId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (resultPayload.present) {
      map['result_payload'] = Variable<String>(resultPayload.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportItemsCompanion(')
          ..write('importJobId: $importJobId, ')
          ..write('ordinal: $ordinal, ')
          ..write('resourceId: $resourceId, ')
          ..write('status: $status, ')
          ..write('resultPayload: $resultPayload, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class SyncCursors extends Table with TableInfo<SyncCursors, SyncCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SyncCursors(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonMeta = const VerificationMeta(
    'singleton',
  );
  late final GeneratedColumn<int> singleton = GeneratedColumn<int>(
    'singleton',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (singleton = 1)',
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES local_account(user_id)',
  );
  static const VerificationMeta _lastChangeSeqMeta = const VerificationMeta(
    'lastChangeSeq',
  );
  late final GeneratedColumn<int> lastChangeSeq = GeneratedColumn<int>(
    'last_change_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (last_change_seq IS NULL OR last_change_seq >= 0)',
  );
  static const VerificationMeta _baselineCompleteMeta = const VerificationMeta(
    'baselineComplete',
  );
  late final GeneratedColumn<int> baselineComplete = GeneratedColumn<int>(
    'baseline_complete',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT 0 CHECK (baseline_complete IN (0, 1))',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _snapshotResumeMeta = const VerificationMeta(
    'snapshotResume',
  );
  late final GeneratedColumn<String> snapshotResume = GeneratedColumn<String>(
    'snapshot_resume',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (snapshot_resume IS NULL OR(json_valid(snapshot_resume) AND json_type(snapshot_resume) = \'object\'))',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    singleton,
    userId,
    lastChangeSeq,
    baselineComplete,
    snapshotResume,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton')) {
      context.handle(
        _singletonMeta,
        singleton.isAcceptableOrUnknown(data['singleton']!, _singletonMeta),
      );
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('last_change_seq')) {
      context.handle(
        _lastChangeSeqMeta,
        lastChangeSeq.isAcceptableOrUnknown(
          data['last_change_seq']!,
          _lastChangeSeqMeta,
        ),
      );
    }
    if (data.containsKey('baseline_complete')) {
      context.handle(
        _baselineCompleteMeta,
        baselineComplete.isAcceptableOrUnknown(
          data['baseline_complete']!,
          _baselineCompleteMeta,
        ),
      );
    }
    if (data.containsKey('snapshot_resume')) {
      context.handle(
        _snapshotResumeMeta,
        snapshotResume.isAcceptableOrUnknown(
          data['snapshot_resume']!,
          _snapshotResumeMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  SyncCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursor(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lastChangeSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_change_seq'],
      ),
      baselineComplete: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}baseline_complete'],
      )!,
      snapshotResume: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_resume'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  SyncCursors createAlias(String alias) {
    return SyncCursors(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK(baseline_complete = 0 OR last_change_seq IS NOT NULL)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class SyncCursor extends DataClass implements Insertable<SyncCursor> {
  final int singleton;
  final String userId;
  final int? lastChangeSeq;
  final int baselineComplete;
  final String? snapshotResume;
  final int updatedAt;
  const SyncCursor({
    required this.singleton,
    required this.userId,
    this.lastChangeSeq,
    required this.baselineComplete,
    this.snapshotResume,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || lastChangeSeq != null) {
      map['last_change_seq'] = Variable<int>(lastChangeSeq);
    }
    map['baseline_complete'] = Variable<int>(baselineComplete);
    if (!nullToAbsent || snapshotResume != null) {
      map['snapshot_resume'] = Variable<String>(snapshotResume);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(
      singleton: Value(singleton),
      userId: Value(userId),
      lastChangeSeq: lastChangeSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(lastChangeSeq),
      baselineComplete: Value(baselineComplete),
      snapshotResume: snapshotResume == null && nullToAbsent
          ? const Value.absent()
          : Value(snapshotResume),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursor(
      singleton: serializer.fromJson<int>(json['singleton']),
      userId: serializer.fromJson<String>(json['user_id']),
      lastChangeSeq: serializer.fromJson<int?>(json['last_change_seq']),
      baselineComplete: serializer.fromJson<int>(json['baseline_complete']),
      snapshotResume: serializer.fromJson<String?>(json['snapshot_resume']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'user_id': serializer.toJson<String>(userId),
      'last_change_seq': serializer.toJson<int?>(lastChangeSeq),
      'baseline_complete': serializer.toJson<int>(baselineComplete),
      'snapshot_resume': serializer.toJson<String?>(snapshotResume),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  SyncCursor copyWith({
    int? singleton,
    String? userId,
    Value<int?> lastChangeSeq = const Value.absent(),
    int? baselineComplete,
    Value<String?> snapshotResume = const Value.absent(),
    int? updatedAt,
  }) => SyncCursor(
    singleton: singleton ?? this.singleton,
    userId: userId ?? this.userId,
    lastChangeSeq: lastChangeSeq.present
        ? lastChangeSeq.value
        : this.lastChangeSeq,
    baselineComplete: baselineComplete ?? this.baselineComplete,
    snapshotResume: snapshotResume.present
        ? snapshotResume.value
        : this.snapshotResume,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncCursor copyWithCompanion(SyncCursorsCompanion data) {
    return SyncCursor(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      userId: data.userId.present ? data.userId.value : this.userId,
      lastChangeSeq: data.lastChangeSeq.present
          ? data.lastChangeSeq.value
          : this.lastChangeSeq,
      baselineComplete: data.baselineComplete.present
          ? data.baselineComplete.value
          : this.baselineComplete,
      snapshotResume: data.snapshotResume.present
          ? data.snapshotResume.value
          : this.snapshotResume,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursor(')
          ..write('singleton: $singleton, ')
          ..write('userId: $userId, ')
          ..write('lastChangeSeq: $lastChangeSeq, ')
          ..write('baselineComplete: $baselineComplete, ')
          ..write('snapshotResume: $snapshotResume, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    singleton,
    userId,
    lastChangeSeq,
    baselineComplete,
    snapshotResume,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursor &&
          other.singleton == this.singleton &&
          other.userId == this.userId &&
          other.lastChangeSeq == this.lastChangeSeq &&
          other.baselineComplete == this.baselineComplete &&
          other.snapshotResume == this.snapshotResume &&
          other.updatedAt == this.updatedAt);
}

class SyncCursorsCompanion extends UpdateCompanion<SyncCursor> {
  final Value<int> singleton;
  final Value<String> userId;
  final Value<int?> lastChangeSeq;
  final Value<int> baselineComplete;
  final Value<String?> snapshotResume;
  final Value<int> updatedAt;
  const SyncCursorsCompanion({
    this.singleton = const Value.absent(),
    this.userId = const Value.absent(),
    this.lastChangeSeq = const Value.absent(),
    this.baselineComplete = const Value.absent(),
    this.snapshotResume = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    this.singleton = const Value.absent(),
    required String userId,
    this.lastChangeSeq = const Value.absent(),
    this.baselineComplete = const Value.absent(),
    this.snapshotResume = const Value.absent(),
    required int updatedAt,
  }) : userId = Value(userId),
       updatedAt = Value(updatedAt);
  static Insertable<SyncCursor> custom({
    Expression<int>? singleton,
    Expression<String>? userId,
    Expression<int>? lastChangeSeq,
    Expression<int>? baselineComplete,
    Expression<String>? snapshotResume,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (userId != null) 'user_id': userId,
      if (lastChangeSeq != null) 'last_change_seq': lastChangeSeq,
      if (baselineComplete != null) 'baseline_complete': baselineComplete,
      if (snapshotResume != null) 'snapshot_resume': snapshotResume,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SyncCursorsCompanion copyWith({
    Value<int>? singleton,
    Value<String>? userId,
    Value<int?>? lastChangeSeq,
    Value<int>? baselineComplete,
    Value<String?>? snapshotResume,
    Value<int>? updatedAt,
  }) {
    return SyncCursorsCompanion(
      singleton: singleton ?? this.singleton,
      userId: userId ?? this.userId,
      lastChangeSeq: lastChangeSeq ?? this.lastChangeSeq,
      baselineComplete: baselineComplete ?? this.baselineComplete,
      snapshotResume: snapshotResume ?? this.snapshotResume,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lastChangeSeq.present) {
      map['last_change_seq'] = Variable<int>(lastChangeSeq.value);
    }
    if (baselineComplete.present) {
      map['baseline_complete'] = Variable<int>(baselineComplete.value);
    }
    if (snapshotResume.present) {
      map['snapshot_resume'] = Variable<String>(snapshotResume.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('singleton: $singleton, ')
          ..write('userId: $userId, ')
          ..write('lastChangeSeq: $lastChangeSeq, ')
          ..write('baselineComplete: $baselineComplete, ')
          ..write('snapshotResume: $snapshotResume, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class MutationWireRequests extends Table
    with TableInfo<MutationWireRequests, MutationWireRequest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MutationWireRequests(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _opIdMeta = const VerificationMeta('opId');
  late final GeneratedColumn<String> opId = GeneratedColumn<String>(
    'op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _contractVersionMeta = const VerificationMeta(
    'contractVersion',
  );
  late final GeneratedColumn<String> contractVersion = GeneratedColumn<String>(
    'contract_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _httpMethodMeta = const VerificationMeta(
    'httpMethod',
  );
  late final GeneratedColumn<String> httpMethod = GeneratedColumn<String>(
    'http_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (http_method IN (\'POST\', \'PATCH\'))',
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _bodyJsonMeta = const VerificationMeta(
    'bodyJson',
  );
  late final GeneratedColumn<String> bodyJson = GeneratedColumn<String>(
    'body_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(body_json) AND json_type(body_json) = \'object\')',
  );
  static const VerificationMeta _wireHashMeta = const VerificationMeta(
    'wireHash',
  );
  late final GeneratedColumn<String> wireHash = GeneratedColumn<String>(
    'wire_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(wire_hash) = 64 AND wire_hash NOT GLOB \'*[^0-9a-f]*\')',
  );
  @override
  List<GeneratedColumn> get $columns => [
    opId,
    contractVersion,
    httpMethod,
    relativePath,
    bodyJson,
    wireHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mutation_wire_requests';
  @override
  VerificationContext validateIntegrity(
    Insertable<MutationWireRequest> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('op_id')) {
      context.handle(
        _opIdMeta,
        opId.isAcceptableOrUnknown(data['op_id']!, _opIdMeta),
      );
    } else if (isInserting) {
      context.missing(_opIdMeta);
    }
    if (data.containsKey('contract_version')) {
      context.handle(
        _contractVersionMeta,
        contractVersion.isAcceptableOrUnknown(
          data['contract_version']!,
          _contractVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contractVersionMeta);
    }
    if (data.containsKey('http_method')) {
      context.handle(
        _httpMethodMeta,
        httpMethod.isAcceptableOrUnknown(data['http_method']!, _httpMethodMeta),
      );
    } else if (isInserting) {
      context.missing(_httpMethodMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('body_json')) {
      context.handle(
        _bodyJsonMeta,
        bodyJson.isAcceptableOrUnknown(data['body_json']!, _bodyJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyJsonMeta);
    }
    if (data.containsKey('wire_hash')) {
      context.handle(
        _wireHashMeta,
        wireHash.isAcceptableOrUnknown(data['wire_hash']!, _wireHashMeta),
      );
    } else if (isInserting) {
      context.missing(_wireHashMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {opId};
  @override
  MutationWireRequest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MutationWireRequest(
      opId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_id'],
      )!,
      contractVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contract_version'],
      )!,
      httpMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}http_method'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      bodyJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_json'],
      )!,
      wireHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wire_hash'],
      )!,
    );
  }

  @override
  MutationWireRequests createAlias(String alias) {
    return MutationWireRequests(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class MutationWireRequest extends DataClass
    implements Insertable<MutationWireRequest> {
  final String opId;
  final String contractVersion;
  final String httpMethod;
  final String relativePath;
  final String bodyJson;
  final String wireHash;
  const MutationWireRequest({
    required this.opId,
    required this.contractVersion,
    required this.httpMethod,
    required this.relativePath,
    required this.bodyJson,
    required this.wireHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['op_id'] = Variable<String>(opId);
    map['contract_version'] = Variable<String>(contractVersion);
    map['http_method'] = Variable<String>(httpMethod);
    map['relative_path'] = Variable<String>(relativePath);
    map['body_json'] = Variable<String>(bodyJson);
    map['wire_hash'] = Variable<String>(wireHash);
    return map;
  }

  MutationWireRequestsCompanion toCompanion(bool nullToAbsent) {
    return MutationWireRequestsCompanion(
      opId: Value(opId),
      contractVersion: Value(contractVersion),
      httpMethod: Value(httpMethod),
      relativePath: Value(relativePath),
      bodyJson: Value(bodyJson),
      wireHash: Value(wireHash),
    );
  }

  factory MutationWireRequest.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MutationWireRequest(
      opId: serializer.fromJson<String>(json['op_id']),
      contractVersion: serializer.fromJson<String>(json['contract_version']),
      httpMethod: serializer.fromJson<String>(json['http_method']),
      relativePath: serializer.fromJson<String>(json['relative_path']),
      bodyJson: serializer.fromJson<String>(json['body_json']),
      wireHash: serializer.fromJson<String>(json['wire_hash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'op_id': serializer.toJson<String>(opId),
      'contract_version': serializer.toJson<String>(contractVersion),
      'http_method': serializer.toJson<String>(httpMethod),
      'relative_path': serializer.toJson<String>(relativePath),
      'body_json': serializer.toJson<String>(bodyJson),
      'wire_hash': serializer.toJson<String>(wireHash),
    };
  }

  MutationWireRequest copyWith({
    String? opId,
    String? contractVersion,
    String? httpMethod,
    String? relativePath,
    String? bodyJson,
    String? wireHash,
  }) => MutationWireRequest(
    opId: opId ?? this.opId,
    contractVersion: contractVersion ?? this.contractVersion,
    httpMethod: httpMethod ?? this.httpMethod,
    relativePath: relativePath ?? this.relativePath,
    bodyJson: bodyJson ?? this.bodyJson,
    wireHash: wireHash ?? this.wireHash,
  );
  MutationWireRequest copyWithCompanion(MutationWireRequestsCompanion data) {
    return MutationWireRequest(
      opId: data.opId.present ? data.opId.value : this.opId,
      contractVersion: data.contractVersion.present
          ? data.contractVersion.value
          : this.contractVersion,
      httpMethod: data.httpMethod.present
          ? data.httpMethod.value
          : this.httpMethod,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      bodyJson: data.bodyJson.present ? data.bodyJson.value : this.bodyJson,
      wireHash: data.wireHash.present ? data.wireHash.value : this.wireHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MutationWireRequest(')
          ..write('opId: $opId, ')
          ..write('contractVersion: $contractVersion, ')
          ..write('httpMethod: $httpMethod, ')
          ..write('relativePath: $relativePath, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('wireHash: $wireHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    opId,
    contractVersion,
    httpMethod,
    relativePath,
    bodyJson,
    wireHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MutationWireRequest &&
          other.opId == this.opId &&
          other.contractVersion == this.contractVersion &&
          other.httpMethod == this.httpMethod &&
          other.relativePath == this.relativePath &&
          other.bodyJson == this.bodyJson &&
          other.wireHash == this.wireHash);
}

class MutationWireRequestsCompanion
    extends UpdateCompanion<MutationWireRequest> {
  final Value<String> opId;
  final Value<String> contractVersion;
  final Value<String> httpMethod;
  final Value<String> relativePath;
  final Value<String> bodyJson;
  final Value<String> wireHash;
  final Value<int> rowid;
  const MutationWireRequestsCompanion({
    this.opId = const Value.absent(),
    this.contractVersion = const Value.absent(),
    this.httpMethod = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.bodyJson = const Value.absent(),
    this.wireHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MutationWireRequestsCompanion.insert({
    required String opId,
    required String contractVersion,
    required String httpMethod,
    required String relativePath,
    required String bodyJson,
    required String wireHash,
    this.rowid = const Value.absent(),
  }) : opId = Value(opId),
       contractVersion = Value(contractVersion),
       httpMethod = Value(httpMethod),
       relativePath = Value(relativePath),
       bodyJson = Value(bodyJson),
       wireHash = Value(wireHash);
  static Insertable<MutationWireRequest> custom({
    Expression<String>? opId,
    Expression<String>? contractVersion,
    Expression<String>? httpMethod,
    Expression<String>? relativePath,
    Expression<String>? bodyJson,
    Expression<String>? wireHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (opId != null) 'op_id': opId,
      if (contractVersion != null) 'contract_version': contractVersion,
      if (httpMethod != null) 'http_method': httpMethod,
      if (relativePath != null) 'relative_path': relativePath,
      if (bodyJson != null) 'body_json': bodyJson,
      if (wireHash != null) 'wire_hash': wireHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MutationWireRequestsCompanion copyWith({
    Value<String>? opId,
    Value<String>? contractVersion,
    Value<String>? httpMethod,
    Value<String>? relativePath,
    Value<String>? bodyJson,
    Value<String>? wireHash,
    Value<int>? rowid,
  }) {
    return MutationWireRequestsCompanion(
      opId: opId ?? this.opId,
      contractVersion: contractVersion ?? this.contractVersion,
      httpMethod: httpMethod ?? this.httpMethod,
      relativePath: relativePath ?? this.relativePath,
      bodyJson: bodyJson ?? this.bodyJson,
      wireHash: wireHash ?? this.wireHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (opId.present) {
      map['op_id'] = Variable<String>(opId.value);
    }
    if (contractVersion.present) {
      map['contract_version'] = Variable<String>(contractVersion.value);
    }
    if (httpMethod.present) {
      map['http_method'] = Variable<String>(httpMethod.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (bodyJson.present) {
      map['body_json'] = Variable<String>(bodyJson.value);
    }
    if (wireHash.present) {
      map['wire_hash'] = Variable<String>(wireHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MutationWireRequestsCompanion(')
          ..write('opId: $opId, ')
          ..write('contractVersion: $contractVersion, ')
          ..write('httpMethod: $httpMethod, ')
          ..write('relativePath: $relativePath, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('wireHash: $wireHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class MutationRetryControls extends Table
    with TableInfo<MutationRetryControls, MutationRetryControl> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MutationRetryControls(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _opIdMeta = const VerificationMeta('opId');
  late final GeneratedColumn<String> opId = GeneratedColumn<String>(
    'op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _automaticRetriesClaimedMeta =
      const VerificationMeta('automaticRetriesClaimed');
  late final GeneratedColumn<int> automaticRetriesClaimed =
      GeneratedColumn<int>(
        'automatic_retries_claimed',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        $customConstraints: 'CHECK (automatic_retries_claimed IS NULL OR automatic_retries_claimed BETWEEN 0 AND 3)',
      );
  static const VerificationMeta _retryModeMeta = const VerificationMeta(
    'retryMode',
  );
  late final GeneratedColumn<String> retryMode = GeneratedColumn<String>(
    'retry_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (retry_mode IN (\'INITIAL\', \'AUTO\', \'MANUAL_REQUIRED\', \'MANUAL_READY\', \'BLOCKED\'))',
  );
  static const VerificationMeta _lastAttemptKindMeta = const VerificationMeta(
    'lastAttemptKind',
  );
  late final GeneratedColumn<String> lastAttemptKind = GeneratedColumn<String>(
    'last_attempt_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (last_attempt_kind IN (\'INITIAL\', \'AUTO\', \'MANUAL\', \'UNKNOWN\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    opId,
    automaticRetriesClaimed,
    retryMode,
    lastAttemptKind,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mutation_retry_controls';
  @override
  VerificationContext validateIntegrity(
    Insertable<MutationRetryControl> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('op_id')) {
      context.handle(
        _opIdMeta,
        opId.isAcceptableOrUnknown(data['op_id']!, _opIdMeta),
      );
    } else if (isInserting) {
      context.missing(_opIdMeta);
    }
    if (data.containsKey('automatic_retries_claimed')) {
      context.handle(
        _automaticRetriesClaimedMeta,
        automaticRetriesClaimed.isAcceptableOrUnknown(
          data['automatic_retries_claimed']!,
          _automaticRetriesClaimedMeta,
        ),
      );
    }
    if (data.containsKey('retry_mode')) {
      context.handle(
        _retryModeMeta,
        retryMode.isAcceptableOrUnknown(data['retry_mode']!, _retryModeMeta),
      );
    } else if (isInserting) {
      context.missing(_retryModeMeta);
    }
    if (data.containsKey('last_attempt_kind')) {
      context.handle(
        _lastAttemptKindMeta,
        lastAttemptKind.isAcceptableOrUnknown(
          data['last_attempt_kind']!,
          _lastAttemptKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAttemptKindMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {opId};
  @override
  MutationRetryControl map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MutationRetryControl(
      opId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_id'],
      )!,
      automaticRetriesClaimed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}automatic_retries_claimed'],
      ),
      retryMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}retry_mode'],
      )!,
      lastAttemptKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_attempt_kind'],
      )!,
    );
  }

  @override
  MutationRetryControls createAlias(String alias) {
    return MutationRetryControls(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class MutationRetryControl extends DataClass
    implements Insertable<MutationRetryControl> {
  final String opId;
  final int? automaticRetriesClaimed;
  final String retryMode;
  final String lastAttemptKind;
  const MutationRetryControl({
    required this.opId,
    this.automaticRetriesClaimed,
    required this.retryMode,
    required this.lastAttemptKind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['op_id'] = Variable<String>(opId);
    if (!nullToAbsent || automaticRetriesClaimed != null) {
      map['automatic_retries_claimed'] = Variable<int>(automaticRetriesClaimed);
    }
    map['retry_mode'] = Variable<String>(retryMode);
    map['last_attempt_kind'] = Variable<String>(lastAttemptKind);
    return map;
  }

  MutationRetryControlsCompanion toCompanion(bool nullToAbsent) {
    return MutationRetryControlsCompanion(
      opId: Value(opId),
      automaticRetriesClaimed: automaticRetriesClaimed == null && nullToAbsent
          ? const Value.absent()
          : Value(automaticRetriesClaimed),
      retryMode: Value(retryMode),
      lastAttemptKind: Value(lastAttemptKind),
    );
  }

  factory MutationRetryControl.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MutationRetryControl(
      opId: serializer.fromJson<String>(json['op_id']),
      automaticRetriesClaimed: serializer.fromJson<int?>(
        json['automatic_retries_claimed'],
      ),
      retryMode: serializer.fromJson<String>(json['retry_mode']),
      lastAttemptKind: serializer.fromJson<String>(json['last_attempt_kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'op_id': serializer.toJson<String>(opId),
      'automatic_retries_claimed': serializer.toJson<int?>(
        automaticRetriesClaimed,
      ),
      'retry_mode': serializer.toJson<String>(retryMode),
      'last_attempt_kind': serializer.toJson<String>(lastAttemptKind),
    };
  }

  MutationRetryControl copyWith({
    String? opId,
    Value<int?> automaticRetriesClaimed = const Value.absent(),
    String? retryMode,
    String? lastAttemptKind,
  }) => MutationRetryControl(
    opId: opId ?? this.opId,
    automaticRetriesClaimed: automaticRetriesClaimed.present
        ? automaticRetriesClaimed.value
        : this.automaticRetriesClaimed,
    retryMode: retryMode ?? this.retryMode,
    lastAttemptKind: lastAttemptKind ?? this.lastAttemptKind,
  );
  MutationRetryControl copyWithCompanion(MutationRetryControlsCompanion data) {
    return MutationRetryControl(
      opId: data.opId.present ? data.opId.value : this.opId,
      automaticRetriesClaimed: data.automaticRetriesClaimed.present
          ? data.automaticRetriesClaimed.value
          : this.automaticRetriesClaimed,
      retryMode: data.retryMode.present ? data.retryMode.value : this.retryMode,
      lastAttemptKind: data.lastAttemptKind.present
          ? data.lastAttemptKind.value
          : this.lastAttemptKind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MutationRetryControl(')
          ..write('opId: $opId, ')
          ..write('automaticRetriesClaimed: $automaticRetriesClaimed, ')
          ..write('retryMode: $retryMode, ')
          ..write('lastAttemptKind: $lastAttemptKind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(opId, automaticRetriesClaimed, retryMode, lastAttemptKind);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MutationRetryControl &&
          other.opId == this.opId &&
          other.automaticRetriesClaimed == this.automaticRetriesClaimed &&
          other.retryMode == this.retryMode &&
          other.lastAttemptKind == this.lastAttemptKind);
}

class MutationRetryControlsCompanion
    extends UpdateCompanion<MutationRetryControl> {
  final Value<String> opId;
  final Value<int?> automaticRetriesClaimed;
  final Value<String> retryMode;
  final Value<String> lastAttemptKind;
  final Value<int> rowid;
  const MutationRetryControlsCompanion({
    this.opId = const Value.absent(),
    this.automaticRetriesClaimed = const Value.absent(),
    this.retryMode = const Value.absent(),
    this.lastAttemptKind = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MutationRetryControlsCompanion.insert({
    required String opId,
    this.automaticRetriesClaimed = const Value.absent(),
    required String retryMode,
    required String lastAttemptKind,
    this.rowid = const Value.absent(),
  }) : opId = Value(opId),
       retryMode = Value(retryMode),
       lastAttemptKind = Value(lastAttemptKind);
  static Insertable<MutationRetryControl> custom({
    Expression<String>? opId,
    Expression<int>? automaticRetriesClaimed,
    Expression<String>? retryMode,
    Expression<String>? lastAttemptKind,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (opId != null) 'op_id': opId,
      if (automaticRetriesClaimed != null)
        'automatic_retries_claimed': automaticRetriesClaimed,
      if (retryMode != null) 'retry_mode': retryMode,
      if (lastAttemptKind != null) 'last_attempt_kind': lastAttemptKind,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MutationRetryControlsCompanion copyWith({
    Value<String>? opId,
    Value<int?>? automaticRetriesClaimed,
    Value<String>? retryMode,
    Value<String>? lastAttemptKind,
    Value<int>? rowid,
  }) {
    return MutationRetryControlsCompanion(
      opId: opId ?? this.opId,
      automaticRetriesClaimed:
          automaticRetriesClaimed ?? this.automaticRetriesClaimed,
      retryMode: retryMode ?? this.retryMode,
      lastAttemptKind: lastAttemptKind ?? this.lastAttemptKind,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (opId.present) {
      map['op_id'] = Variable<String>(opId.value);
    }
    if (automaticRetriesClaimed.present) {
      map['automatic_retries_claimed'] = Variable<int>(
        automaticRetriesClaimed.value,
      );
    }
    if (retryMode.present) {
      map['retry_mode'] = Variable<String>(retryMode.value);
    }
    if (lastAttemptKind.present) {
      map['last_attempt_kind'] = Variable<String>(lastAttemptKind.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MutationRetryControlsCompanion(')
          ..write('opId: $opId, ')
          ..write('automaticRetriesClaimed: $automaticRetriesClaimed, ')
          ..write('retryMode: $retryMode, ')
          ..write('lastAttemptKind: $lastAttemptKind, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AccountDatabase extends GeneratedDatabase {
  _$AccountDatabase(QueryExecutor e) : super(e);
  $AccountDatabaseManager get managers => $AccountDatabaseManager(this);
  late final LocalAccount localAccount = LocalAccount(this);
  late final MetadataCopies metadataCopies = MetadataCopies(this);
  late final LocalMutations localMutations = LocalMutations(this);
  late final Index mutationQueue = Index(
    'mutation_queue',
    'CREATE INDEX mutation_queue ON local_mutations (queue_state, next_attempt_at, created_at, op_id)',
  );
  late final Index mutationTarget = Index(
    'mutation_target',
    'CREATE INDEX mutation_target ON local_mutations (entity_type, entity_id, created_at)',
  );
  late final LocalRecordingFiles localRecordingFiles = LocalRecordingFiles(
    this,
  );
  late final RecordingJournals recordingJournals = RecordingJournals(this);
  late final ImportJobs importJobs = ImportJobs(this);
  late final ImportItems importItems = ImportItems(this);
  late final SyncCursors syncCursors = SyncCursors(this);
  late final Trigger localAccountNoUpdate = Trigger(
    'CREATE TRIGGER local_account_no_update BEFORE UPDATE ON local_account BEGIN SELECT RAISE (ABORT, \'Local database ownership is immutable\');END',
    'local_account_no_update',
  );
  late final Trigger localAccountNoDelete = Trigger(
    'CREATE TRIGGER local_account_no_delete BEFORE DELETE ON local_account BEGIN SELECT RAISE (ABORT, \'Local database ownership cannot be removed\');END',
    'local_account_no_delete',
  );
  late final Trigger mutationRequestImmutable = Trigger(
    'CREATE TRIGGER mutation_request_immutable BEFORE UPDATE ON local_mutations WHEN NEW.op_id <> OLD.op_id OR NEW.user_id <> OLD.user_id OR NEW.entity_type <> OLD.entity_type OR NEW.entity_id <> OLD.entity_id OR NEW.operation <> OLD.operation OR NEW.base_revision <> OLD.base_revision OR NEW.base_payload IS NOT OLD.base_payload OR NEW.payload <> OLD.payload OR NEW.request_hash <> OLD.request_hash OR NEW.created_at <> OLD.created_at OR NEW.attempt_count < OLD.attempt_count BEGIN SELECT RAISE (ABORT, \'Mutation identity and request must survive retries unchanged\');END',
    'mutation_request_immutable',
  );
  late final Trigger cursorNoRewind = Trigger(
    'CREATE TRIGGER cursor_no_rewind BEFORE UPDATE ON sync_cursors WHEN NEW.user_id <> OLD.user_id OR(OLD.last_change_seq IS NOT NULL AND(NEW.last_change_seq IS NULL OR NEW.last_change_seq < OLD.last_change_seq))BEGIN SELECT RAISE (ABORT, \'Do not discard an acknowledged cursor\');END',
    'cursor_no_rewind',
  );
  late final MutationWireRequests mutationWireRequests = MutationWireRequests(
    this,
  );
  late final Trigger mutationWireRequestImmutable = Trigger(
    'CREATE TRIGGER mutation_wire_request_immutable BEFORE UPDATE ON mutation_wire_requests BEGIN SELECT RAISE (ABORT, \'Frozen HTTP requests must survive retries unchanged\');END',
    'mutation_wire_request_immutable',
  );
  late final MutationRetryControls mutationRetryControls =
      MutationRetryControls(this);
  late final Trigger mutationRetryBudgetMonotonic = Trigger(
    'CREATE TRIGGER mutation_retry_budget_monotonic BEFORE UPDATE ON mutation_retry_controls WHEN NEW.op_id <> OLD.op_id OR(OLD.automatic_retries_claimed IS NULL AND NEW.automatic_retries_claimed IS NOT NULL)OR(OLD.automatic_retries_claimed IS NOT NULL AND NEW.automatic_retries_claimed IS NULL)OR NEW.automatic_retries_claimed < OLD.automatic_retries_claimed OR NEW.automatic_retries_claimed > OLD.automatic_retries_claimed + 1 BEGIN SELECT RAISE (ABORT, \'Automatic retry budget cannot be replenished\');END',
    'mutation_retry_budget_monotonic',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localAccount,
    metadataCopies,
    localMutations,
    mutationQueue,
    mutationTarget,
    localRecordingFiles,
    recordingJournals,
    importJobs,
    importItems,
    syncCursors,
    localAccountNoUpdate,
    localAccountNoDelete,
    mutationRequestImmutable,
    cursorNoRewind,
    mutationWireRequests,
    mutationWireRequestImmutable,
    mutationRetryControls,
    mutationRetryBudgetMonotonic,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_account',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_account',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_mutations',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sync_cursors',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_wire_requests',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_retry_controls',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
  ]);
}

typedef $LocalAccountCreateCompanionBuilder = LocalAccountCompanion Function({
  Value<int> singleton,
  required String userId,
  required String environment,
  required int createdAt,
});
typedef $LocalAccountUpdateCompanionBuilder = LocalAccountCompanion Function({
  Value<int> singleton,
  Value<String> userId,
  Value<String> environment,
  Value<int> createdAt,
});

final class $LocalAccountReferences
    extends BaseReferences<_$AccountDatabase, LocalAccount, LocalAccountData> {
  $LocalAccountReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<MetadataCopies, List<MetadataCopy>>
  _metadataCopiesRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.metadataCopies,
        aliasName: 'local_account__user_id__metadata_copies__user_id',
      );

  $MetadataCopiesProcessedTableManager get metadataCopiesRefs {
    final manager = $MetadataCopiesTableManager($_db, $_db.metadataCopies)
        .filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(_metadataCopiesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<LocalMutations, List<LocalMutation>>
  _localMutationsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.localMutations,
        aliasName: 'local_account__user_id__local_mutations__user_id',
      );

  $LocalMutationsProcessedTableManager get localMutationsRefs {
    final manager = $LocalMutationsTableManager($_db, $_db.localMutations)
        .filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(_localMutationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<LocalRecordingFiles, List<LocalRecordingFile>>
  _localRecordingFilesRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.localRecordingFiles,
        aliasName: 'local_account__user_id__local_recording_files__user_id',
      );

  $LocalRecordingFilesProcessedTableManager get localRecordingFilesRefs {
    final manager =
        $LocalRecordingFilesTableManager($_db, $_db.localRecordingFiles).filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _localRecordingFilesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<ImportJobs, List<ImportJob>> _importJobsRefsTable(
    _$AccountDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.importJobs,
    aliasName: 'local_account__user_id__import_jobs__user_id',
  );

  $ImportJobsProcessedTableManager get importJobsRefs {
    final manager = $ImportJobsTableManager($_db, $_db.importJobs).filter(
      (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_importJobsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<SyncCursors, List<SyncCursor>>
  _syncCursorsRefsTable(_$AccountDatabase db) => MultiTypedResultKey.fromTable(
    db.syncCursors,
    aliasName: 'local_account__user_id__sync_cursors__user_id',
  );

  $SyncCursorsProcessedTableManager get syncCursorsRefs {
    final manager = $SyncCursorsTableManager($_db, $_db.syncCursors).filter(
      (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_syncCursorsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $LocalAccountFilterComposer
    extends Composer<_$AccountDatabase, LocalAccount> {
  $LocalAccountFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> metadataCopiesRefs(
    Expression<bool> Function($MetadataCopiesFilterComposer f) f,
  ) {
    final $MetadataCopiesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.metadataCopies,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MetadataCopiesFilterComposer(
            $db: $db,
            $table: $db.metadataCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> localMutationsRefs(
    Expression<bool> Function($LocalMutationsFilterComposer f) f,
  ) {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localMutations,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalMutationsFilterComposer(
            $db: $db,
            $table: $db.localMutations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> localRecordingFilesRefs(
    Expression<bool> Function($LocalRecordingFilesFilterComposer f) f,
  ) {
    final $LocalRecordingFilesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localRecordingFiles,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalRecordingFilesFilterComposer(
            $db: $db,
            $table: $db.localRecordingFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> importJobsRefs(
    Expression<bool> Function($ImportJobsFilterComposer f) f,
  ) {
    final $ImportJobsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.importJobs,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportJobsFilterComposer(
            $db: $db,
            $table: $db.importJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> syncCursorsRefs(
    Expression<bool> Function($SyncCursorsFilterComposer f) f,
  ) {
    final $SyncCursorsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.syncCursors,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SyncCursorsFilterComposer(
            $db: $db,
            $table: $db.syncCursors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $LocalAccountOrderingComposer
    extends Composer<_$AccountDatabase, LocalAccount> {
  $LocalAccountOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $LocalAccountAnnotationComposer
    extends Composer<_$AccountDatabase, LocalAccount> {
  $LocalAccountAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singleton =>
      $composableBuilder(column: $table.singleton, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> metadataCopiesRefs<T extends Object>(
    Expression<T> Function($MetadataCopiesAnnotationComposer a) f,
  ) {
    final $MetadataCopiesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.metadataCopies,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MetadataCopiesAnnotationComposer(
            $db: $db,
            $table: $db.metadataCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> localMutationsRefs<T extends Object>(
    Expression<T> Function($LocalMutationsAnnotationComposer a) f,
  ) {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localMutations,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalMutationsAnnotationComposer(
            $db: $db,
            $table: $db.localMutations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> localRecordingFilesRefs<T extends Object>(
    Expression<T> Function($LocalRecordingFilesAnnotationComposer a) f,
  ) {
    final $LocalRecordingFilesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localRecordingFiles,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalRecordingFilesAnnotationComposer(
            $db: $db,
            $table: $db.localRecordingFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> importJobsRefs<T extends Object>(
    Expression<T> Function($ImportJobsAnnotationComposer a) f,
  ) {
    final $ImportJobsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.importJobs,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportJobsAnnotationComposer(
            $db: $db,
            $table: $db.importJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> syncCursorsRefs<T extends Object>(
    Expression<T> Function($SyncCursorsAnnotationComposer a) f,
  ) {
    final $SyncCursorsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.syncCursors,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SyncCursorsAnnotationComposer(
            $db: $db,
            $table: $db.syncCursors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $LocalAccountTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          LocalAccount,
          LocalAccountData,
          $LocalAccountFilterComposer,
          $LocalAccountOrderingComposer,
          $LocalAccountAnnotationComposer,
          $LocalAccountCreateCompanionBuilder,
          $LocalAccountUpdateCompanionBuilder,
          (LocalAccountData, $LocalAccountReferences),
          LocalAccountData,
          PrefetchHooks Function({
            bool metadataCopiesRefs,
            bool localMutationsRefs,
            bool localRecordingFilesRefs,
            bool importJobsRefs,
            bool syncCursorsRefs,
          })
        > {
  $LocalAccountTableManager(_$AccountDatabase db, LocalAccount table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LocalAccountFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LocalAccountOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LocalAccountAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> environment = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => LocalAccountCompanion(
                singleton: singleton,
                userId: userId,
                environment: environment,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                required String userId,
                required String environment,
                required int createdAt,
              }) => LocalAccountCompanion.insert(
                singleton: singleton,
                userId: userId,
                environment: environment,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<LocalAccount, LocalAccountData>(table),
                  $LocalAccountReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                metadataCopiesRefs = false,
                localMutationsRefs = false,
                localRecordingFilesRefs = false,
                importJobsRefs = false,
                syncCursorsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (metadataCopiesRefs) db.metadataCopies,
                    if (localMutationsRefs) db.localMutations,
                    if (localRecordingFilesRefs) db.localRecordingFiles,
                    if (importJobsRefs) db.importJobs,
                    if (syncCursorsRefs) db.syncCursors,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (metadataCopiesRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          MetadataCopy
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._metadataCopiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).metadataCopiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (localMutationsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          LocalMutation
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._localMutationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).localMutationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (localRecordingFilesRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          LocalRecordingFile
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._localRecordingFilesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).localRecordingFilesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (importJobsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          ImportJob
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._importJobsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).importJobsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (syncCursorsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          SyncCursor
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._syncCursorsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).syncCursorsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $LocalAccountProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      LocalAccount,
      LocalAccountData,
      $LocalAccountFilterComposer,
      $LocalAccountOrderingComposer,
      $LocalAccountAnnotationComposer,
      $LocalAccountCreateCompanionBuilder,
      $LocalAccountUpdateCompanionBuilder,
      (LocalAccountData, $LocalAccountReferences),
      LocalAccountData,
      PrefetchHooks Function({
        bool metadataCopiesRefs,
        bool localMutationsRefs,
        bool localRecordingFilesRefs,
        bool importJobsRefs,
        bool syncCursorsRefs,
      })
    >;
typedef $MetadataCopiesCreateCompanionBuilder =
    MetadataCopiesCompanion Function({
      required String userId,
      required String entityType,
      required String entityId,
      Value<int> serverRevision,
      Value<String?> serverPayload,
      Value<String?> localPayload,
      Value<int> tombstone,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $MetadataCopiesUpdateCompanionBuilder =
    MetadataCopiesCompanion Function({
      Value<String> userId,
      Value<String> entityType,
      Value<String> entityId,
      Value<int> serverRevision,
      Value<String?> serverPayload,
      Value<String?> localPayload,
      Value<int> tombstone,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $MetadataCopiesReferences
    extends BaseReferences<_$AccountDatabase, MetadataCopies, MetadataCopy> {
  $MetadataCopiesReferences(super.$_db, super.$_table, super.$_typedResult);

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('metadata_copies__user_id__local_account__user_id');

  $LocalAccountProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $LocalAccountTableManager(
      $_db,
      $_db.localAccount,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $MetadataCopiesFilterComposer
    extends Composer<_$AccountDatabase, MetadataCopies> {
  $MetadataCopiesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverRevision => $composableBuilder(
    column: $table.serverRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverPayload => $composableBuilder(
    column: $table.serverPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $LocalAccountFilterComposer get userId {
    final $LocalAccountFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountFilterComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MetadataCopiesOrderingComposer
    extends Composer<_$AccountDatabase, MetadataCopies> {
  $MetadataCopiesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverRevision => $composableBuilder(
    column: $table.serverRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverPayload => $composableBuilder(
    column: $table.serverPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalAccountOrderingComposer get userId {
    final $LocalAccountOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountOrderingComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MetadataCopiesAnnotationComposer
    extends Composer<_$AccountDatabase, MetadataCopies> {
  $MetadataCopiesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<int> get serverRevision => $composableBuilder(
    column: $table.serverRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverPayload => $composableBuilder(
    column: $table.serverPayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tombstone =>
      $composableBuilder(column: $table.tombstone, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $LocalAccountAnnotationComposer get userId {
    final $LocalAccountAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountAnnotationComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MetadataCopiesTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          MetadataCopies,
          MetadataCopy,
          $MetadataCopiesFilterComposer,
          $MetadataCopiesOrderingComposer,
          $MetadataCopiesAnnotationComposer,
          $MetadataCopiesCreateCompanionBuilder,
          $MetadataCopiesUpdateCompanionBuilder,
          (MetadataCopy, $MetadataCopiesReferences),
          MetadataCopy,
          PrefetchHooks Function({bool userId})
        > {
  $MetadataCopiesTableManager(_$AccountDatabase db, MetadataCopies table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MetadataCopiesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MetadataCopiesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MetadataCopiesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<int> serverRevision = const Value.absent(),
                Value<String?> serverPayload = const Value.absent(),
                Value<String?> localPayload = const Value.absent(),
                Value<int> tombstone = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetadataCopiesCompanion(
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                serverRevision: serverRevision,
                serverPayload: serverPayload,
                localPayload: localPayload,
                tombstone: tombstone,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String entityType,
                required String entityId,
                Value<int> serverRevision = const Value.absent(),
                Value<String?> serverPayload = const Value.absent(),
                Value<String?> localPayload = const Value.absent(),
                Value<int> tombstone = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MetadataCopiesCompanion.insert(
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                serverRevision: serverRevision,
                serverPayload: serverPayload,
                localPayload: localPayload,
                tombstone: tombstone,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<MetadataCopies, MetadataCopy>(table),
                  $MetadataCopiesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.userId,
                        referencedTable: $MetadataCopiesReferences._userIdTable(
                          db,
                        ),
                        referencedColumn: $MetadataCopiesReferences
                            ._userIdTable(db)
                            .userId,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $MetadataCopiesProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      MetadataCopies,
      MetadataCopy,
      $MetadataCopiesFilterComposer,
      $MetadataCopiesOrderingComposer,
      $MetadataCopiesAnnotationComposer,
      $MetadataCopiesCreateCompanionBuilder,
      $MetadataCopiesUpdateCompanionBuilder,
      (MetadataCopy, $MetadataCopiesReferences),
      MetadataCopy,
      PrefetchHooks Function({bool userId})
    >;
typedef $LocalMutationsCreateCompanionBuilder =
    LocalMutationsCompanion Function({
      required String opId,
      required String userId,
      required String entityType,
      required String entityId,
      required String operation,
      required int baseRevision,
      Value<String?> basePayload,
      required String payload,
      required String requestHash,
      Value<String> queueState,
      Value<int> attemptCount,
      Value<int?> nextAttemptAt,
      Value<String?> serverResponse,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $LocalMutationsUpdateCompanionBuilder =
    LocalMutationsCompanion Function({
      Value<String> opId,
      Value<String> userId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<int> baseRevision,
      Value<String?> basePayload,
      Value<String> payload,
      Value<String> requestHash,
      Value<String> queueState,
      Value<int> attemptCount,
      Value<int?> nextAttemptAt,
      Value<String?> serverResponse,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $LocalMutationsReferences
    extends BaseReferences<_$AccountDatabase, LocalMutations, LocalMutation> {
  $LocalMutationsReferences(super.$_db, super.$_table, super.$_typedResult);

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('local_mutations__user_id__local_account__user_id');

  $LocalAccountProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $LocalAccountTableManager(
      $_db,
      $_db.localAccount,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<MutationWireRequests, List<MutationWireRequest>>
  _mutationWireRequestsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mutationWireRequests,
        aliasName: 'local_mutations__op_id__mutation_wire_requests__op_id',
      );

  $MutationWireRequestsProcessedTableManager get mutationWireRequestsRefs {
    final manager = $MutationWireRequestsTableManager(
      $_db,
      $_db.mutationWireRequests,
    ).filter((f) => f.opId.opId.sqlEquals($_itemColumn<String>('op_id')!));

    final cache = $_typedResult.readTableOrNull(
      _mutationWireRequestsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<MutationRetryControls, List<MutationRetryControl>>
  _mutationRetryControlsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mutationRetryControls,
        aliasName: 'local_mutations__op_id__mutation_retry_controls__op_id',
      );

  $MutationRetryControlsProcessedTableManager get mutationRetryControlsRefs {
    final manager = $MutationRetryControlsTableManager(
      $_db,
      $_db.mutationRetryControls,
    ).filter((f) => f.opId.opId.sqlEquals($_itemColumn<String>('op_id')!));

    final cache = $_typedResult.readTableOrNull(
      _mutationRetryControlsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $LocalMutationsFilterComposer
    extends Composer<_$AccountDatabase, LocalMutations> {
  $LocalMutationsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get basePayload => $composableBuilder(
    column: $table.basePayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestHash => $composableBuilder(
    column: $table.requestHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queueState => $composableBuilder(
    column: $table.queueState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverResponse => $composableBuilder(
    column: $table.serverResponse,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $LocalAccountFilterComposer get userId {
    final $LocalAccountFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountFilterComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> mutationWireRequestsRefs(
    Expression<bool> Function($MutationWireRequestsFilterComposer f) f,
  ) {
    final $MutationWireRequestsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.mutationWireRequests,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationWireRequestsFilterComposer(
            $db: $db,
            $table: $db.mutationWireRequests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mutationRetryControlsRefs(
    Expression<bool> Function($MutationRetryControlsFilterComposer f) f,
  ) {
    final $MutationRetryControlsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.mutationRetryControls,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationRetryControlsFilterComposer(
            $db: $db,
            $table: $db.mutationRetryControls,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $LocalMutationsOrderingComposer
    extends Composer<_$AccountDatabase, LocalMutations> {
  $LocalMutationsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get basePayload => $composableBuilder(
    column: $table.basePayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestHash => $composableBuilder(
    column: $table.requestHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queueState => $composableBuilder(
    column: $table.queueState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverResponse => $composableBuilder(
    column: $table.serverResponse,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalAccountOrderingComposer get userId {
    final $LocalAccountOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountOrderingComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $LocalMutationsAnnotationComposer
    extends Composer<_$AccountDatabase, LocalMutations> {
  $LocalMutationsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get opId =>
      $composableBuilder(column: $table.opId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get basePayload => $composableBuilder(
    column: $table.basePayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get requestHash => $composableBuilder(
    column: $table.requestHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get queueState => $composableBuilder(
    column: $table.queueState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverResponse => $composableBuilder(
    column: $table.serverResponse,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $LocalAccountAnnotationComposer get userId {
    final $LocalAccountAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountAnnotationComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> mutationWireRequestsRefs<T extends Object>(
    Expression<T> Function($MutationWireRequestsAnnotationComposer a) f,
  ) {
    final $MutationWireRequestsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.mutationWireRequests,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationWireRequestsAnnotationComposer(
            $db: $db,
            $table: $db.mutationWireRequests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mutationRetryControlsRefs<T extends Object>(
    Expression<T> Function($MutationRetryControlsAnnotationComposer a) f,
  ) {
    final $MutationRetryControlsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.mutationRetryControls,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationRetryControlsAnnotationComposer(
            $db: $db,
            $table: $db.mutationRetryControls,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $LocalMutationsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          LocalMutations,
          LocalMutation,
          $LocalMutationsFilterComposer,
          $LocalMutationsOrderingComposer,
          $LocalMutationsAnnotationComposer,
          $LocalMutationsCreateCompanionBuilder,
          $LocalMutationsUpdateCompanionBuilder,
          (LocalMutation, $LocalMutationsReferences),
          LocalMutation,
          PrefetchHooks Function({
            bool userId,
            bool mutationWireRequestsRefs,
            bool mutationRetryControlsRefs,
          })
        > {
  $LocalMutationsTableManager(_$AccountDatabase db, LocalMutations table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LocalMutationsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LocalMutationsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LocalMutationsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> opId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<int> baseRevision = const Value.absent(),
                Value<String?> basePayload = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> requestHash = const Value.absent(),
                Value<String> queueState = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int?> nextAttemptAt = const Value.absent(),
                Value<String?> serverResponse = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMutationsCompanion(
                opId: opId,
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                baseRevision: baseRevision,
                basePayload: basePayload,
                payload: payload,
                requestHash: requestHash,
                queueState: queueState,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                serverResponse: serverResponse,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String opId,
                required String userId,
                required String entityType,
                required String entityId,
                required String operation,
                required int baseRevision,
                Value<String?> basePayload = const Value.absent(),
                required String payload,
                required String requestHash,
                Value<String> queueState = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int?> nextAttemptAt = const Value.absent(),
                Value<String?> serverResponse = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalMutationsCompanion.insert(
                opId: opId,
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                baseRevision: baseRevision,
                basePayload: basePayload,
                payload: payload,
                requestHash: requestHash,
                queueState: queueState,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                serverResponse: serverResponse,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<LocalMutations, LocalMutation>(table),
                  $LocalMutationsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                userId = false,
                mutationWireRequestsRefs = false,
                mutationRetryControlsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mutationWireRequestsRefs) db.mutationWireRequests,
                    if (mutationRetryControlsRefs) db.mutationRetryControls,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (userId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.userId,
                            referencedTable: $LocalMutationsReferences
                                ._userIdTable(db),
                            referencedColumn: $LocalMutationsReferences
                                ._userIdTable(db)
                                .userId,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (mutationWireRequestsRefs)
                        await $_getPrefetchedData<
                          LocalMutation,
                          LocalMutations,
                          MutationWireRequest
                        >(
                          currentTable: table,
                          referencedTable: $LocalMutationsReferences
                              ._mutationWireRequestsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalMutationsReferences(
                                db,
                                table,
                                p0,
                              ).mutationWireRequestsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.opId == item.opId,
                              ),
                          typedResults: items,
                        ),
                      if (mutationRetryControlsRefs)
                        await $_getPrefetchedData<
                          LocalMutation,
                          LocalMutations,
                          MutationRetryControl
                        >(
                          currentTable: table,
                          referencedTable: $LocalMutationsReferences
                              ._mutationRetryControlsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalMutationsReferences(
                                db,
                                table,
                                p0,
                              ).mutationRetryControlsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.opId == item.opId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $LocalMutationsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      LocalMutations,
      LocalMutation,
      $LocalMutationsFilterComposer,
      $LocalMutationsOrderingComposer,
      $LocalMutationsAnnotationComposer,
      $LocalMutationsCreateCompanionBuilder,
      $LocalMutationsUpdateCompanionBuilder,
      (LocalMutation, $LocalMutationsReferences),
      LocalMutation,
      PrefetchHooks Function({
        bool userId,
        bool mutationWireRequestsRefs,
        bool mutationRetryControlsRefs,
      })
    >;
typedef $LocalRecordingFilesCreateCompanionBuilder =
    LocalRecordingFilesCompanion Function({
      required String recordingId,
      required String userId,
      required String relativePath,
      Value<String?> sha256,
      Value<int?> sizeBytes,
      required String localState,
      Value<int> cleanupFence,
      Value<int?> verifiedAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $LocalRecordingFilesUpdateCompanionBuilder =
    LocalRecordingFilesCompanion Function({
      Value<String> recordingId,
      Value<String> userId,
      Value<String> relativePath,
      Value<String?> sha256,
      Value<int?> sizeBytes,
      Value<String> localState,
      Value<int> cleanupFence,
      Value<int?> verifiedAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $LocalRecordingFilesReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          LocalRecordingFiles,
          LocalRecordingFile
        > {
  $LocalRecordingFilesReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('local_recording_files__user_id__local_account__user_id');

  $LocalAccountProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $LocalAccountTableManager(
      $_db,
      $_db.localAccount,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $LocalRecordingFilesFilterComposer
    extends Composer<_$AccountDatabase, LocalRecordingFiles> {
  $LocalRecordingFilesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localState => $composableBuilder(
    column: $table.localState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cleanupFence => $composableBuilder(
    column: $table.cleanupFence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $LocalAccountFilterComposer get userId {
    final $LocalAccountFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountFilterComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $LocalRecordingFilesOrderingComposer
    extends Composer<_$AccountDatabase, LocalRecordingFiles> {
  $LocalRecordingFilesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localState => $composableBuilder(
    column: $table.localState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cleanupFence => $composableBuilder(
    column: $table.cleanupFence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalAccountOrderingComposer get userId {
    final $LocalAccountOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountOrderingComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $LocalRecordingFilesAnnotationComposer
    extends Composer<_$AccountDatabase, LocalRecordingFiles> {
  $LocalRecordingFilesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get localState => $composableBuilder(
    column: $table.localState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cleanupFence => $composableBuilder(
    column: $table.cleanupFence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $LocalAccountAnnotationComposer get userId {
    final $LocalAccountAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountAnnotationComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $LocalRecordingFilesTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          LocalRecordingFiles,
          LocalRecordingFile,
          $LocalRecordingFilesFilterComposer,
          $LocalRecordingFilesOrderingComposer,
          $LocalRecordingFilesAnnotationComposer,
          $LocalRecordingFilesCreateCompanionBuilder,
          $LocalRecordingFilesUpdateCompanionBuilder,
          (LocalRecordingFile, $LocalRecordingFilesReferences),
          LocalRecordingFile,
          PrefetchHooks Function({bool userId})
        > {
  $LocalRecordingFilesTableManager(
    _$AccountDatabase db,
    LocalRecordingFiles table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LocalRecordingFilesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LocalRecordingFilesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LocalRecordingFilesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> recordingId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String> localState = const Value.absent(),
                Value<int> cleanupFence = const Value.absent(),
                Value<int?> verifiedAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalRecordingFilesCompanion(
                recordingId: recordingId,
                userId: userId,
                relativePath: relativePath,
                sha256: sha256,
                sizeBytes: sizeBytes,
                localState: localState,
                cleanupFence: cleanupFence,
                verifiedAt: verifiedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recordingId,
                required String userId,
                required String relativePath,
                Value<String?> sha256 = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                required String localState,
                Value<int> cleanupFence = const Value.absent(),
                Value<int?> verifiedAt = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalRecordingFilesCompanion.insert(
                recordingId: recordingId,
                userId: userId,
                relativePath: relativePath,
                sha256: sha256,
                sizeBytes: sizeBytes,
                localState: localState,
                cleanupFence: cleanupFence,
                verifiedAt: verifiedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<LocalRecordingFiles, LocalRecordingFile>(table),
                  $LocalRecordingFilesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.userId,
                        referencedTable: $LocalRecordingFilesReferences
                            ._userIdTable(db),
                        referencedColumn: $LocalRecordingFilesReferences
                            ._userIdTable(db)
                            .userId,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $LocalRecordingFilesProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      LocalRecordingFiles,
      LocalRecordingFile,
      $LocalRecordingFilesFilterComposer,
      $LocalRecordingFilesOrderingComposer,
      $LocalRecordingFilesAnnotationComposer,
      $LocalRecordingFilesCreateCompanionBuilder,
      $LocalRecordingFilesUpdateCompanionBuilder,
      (LocalRecordingFile, $LocalRecordingFilesReferences),
      LocalRecordingFile,
      PrefetchHooks Function({bool userId})
    >;
typedef $RecordingJournalsCreateCompanionBuilder =
    RecordingJournalsCompanion Function({
      required String recordingId,
      required String userId,
      required String operationId,
      required String pendingPath,
      required String finalPath,
      required String phase,
      required String recoveryPayload,
      Value<int> revision,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $RecordingJournalsUpdateCompanionBuilder =
    RecordingJournalsCompanion Function({
      Value<String> recordingId,
      Value<String> userId,
      Value<String> operationId,
      Value<String> pendingPath,
      Value<String> finalPath,
      Value<String> phase,
      Value<String> recoveryPayload,
      Value<int> revision,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $RecordingJournalsFilterComposer
    extends Composer<_$AccountDatabase, RecordingJournals> {
  $RecordingJournalsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingPath => $composableBuilder(
    column: $table.pendingPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finalPath => $composableBuilder(
    column: $table.finalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recoveryPayload => $composableBuilder(
    column: $table.recoveryPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $RecordingJournalsOrderingComposer
    extends Composer<_$AccountDatabase, RecordingJournals> {
  $RecordingJournalsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingPath => $composableBuilder(
    column: $table.pendingPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finalPath => $composableBuilder(
    column: $table.finalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recoveryPayload => $composableBuilder(
    column: $table.recoveryPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $RecordingJournalsAnnotationComposer
    extends Composer<_$AccountDatabase, RecordingJournals> {
  $RecordingJournalsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pendingPath => $composableBuilder(
    column: $table.pendingPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get finalPath =>
      $composableBuilder(column: $table.finalPath, builder: (column) => column);

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<String> get recoveryPayload => $composableBuilder(
    column: $table.recoveryPayload,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $RecordingJournalsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          RecordingJournals,
          RecordingJournal,
          $RecordingJournalsFilterComposer,
          $RecordingJournalsOrderingComposer,
          $RecordingJournalsAnnotationComposer,
          $RecordingJournalsCreateCompanionBuilder,
          $RecordingJournalsUpdateCompanionBuilder,
          (
            RecordingJournal,
            BaseReferences<
              _$AccountDatabase,
              RecordingJournals,
              RecordingJournal
            >,
          ),
          RecordingJournal,
          PrefetchHooks Function()
        > {
  $RecordingJournalsTableManager(_$AccountDatabase db, RecordingJournals table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $RecordingJournalsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $RecordingJournalsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $RecordingJournalsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> recordingId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<String> pendingPath = const Value.absent(),
                Value<String> finalPath = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<String> recoveryPayload = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordingJournalsCompanion(
                recordingId: recordingId,
                userId: userId,
                operationId: operationId,
                pendingPath: pendingPath,
                finalPath: finalPath,
                phase: phase,
                recoveryPayload: recoveryPayload,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recordingId,
                required String userId,
                required String operationId,
                required String pendingPath,
                required String finalPath,
                required String phase,
                required String recoveryPayload,
                Value<int> revision = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RecordingJournalsCompanion.insert(
                recordingId: recordingId,
                userId: userId,
                operationId: operationId,
                pendingPath: pendingPath,
                finalPath: finalPath,
                phase: phase,
                recoveryPayload: recoveryPayload,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<RecordingJournals, RecordingJournal>(table),
                  BaseReferences<
                    _$AccountDatabase,
                    RecordingJournals,
                    RecordingJournal
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $RecordingJournalsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      RecordingJournals,
      RecordingJournal,
      $RecordingJournalsFilterComposer,
      $RecordingJournalsOrderingComposer,
      $RecordingJournalsAnnotationComposer,
      $RecordingJournalsCreateCompanionBuilder,
      $RecordingJournalsUpdateCompanionBuilder,
      (
        RecordingJournal,
        BaseReferences<_$AccountDatabase, RecordingJournals, RecordingJournal>,
      ),
      RecordingJournal,
      PrefetchHooks Function()
    >;
typedef $ImportJobsCreateCompanionBuilder = ImportJobsCompanion Function({
  required String importJobId,
  required String userId,
  required String sourceUserId,
  required String archivePath,
  required String manifestHash,
  Value<String> status,
  required int totalItems,
  Value<int> completedItems,
  Value<String?> errorCode,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $ImportJobsUpdateCompanionBuilder = ImportJobsCompanion Function({
  Value<String> importJobId,
  Value<String> userId,
  Value<String> sourceUserId,
  Value<String> archivePath,
  Value<String> manifestHash,
  Value<String> status,
  Value<int> totalItems,
  Value<int> completedItems,
  Value<String?> errorCode,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $ImportJobsReferences
    extends BaseReferences<_$AccountDatabase, ImportJobs, ImportJob> {
  $ImportJobsReferences(super.$_db, super.$_table, super.$_typedResult);

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('import_jobs__user_id__local_account__user_id');

  $LocalAccountProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $LocalAccountTableManager(
      $_db,
      $_db.localAccount,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<ImportItems, List<ImportItem>>
  _importItemsRefsTable(_$AccountDatabase db) => MultiTypedResultKey.fromTable(
    db.importItems,
    aliasName: 'import_jobs__import_job_id__import_items__import_job_id',
  );

  $ImportItemsProcessedTableManager get importItemsRefs {
    final manager = $ImportItemsTableManager($_db, $_db.importItems).filter(
      (f) => f.importJobId.importJobId.sqlEquals(
        $_itemColumn<String>('import_job_id')!,
      ),
    );

    final cache = $_typedResult.readTableOrNull(_importItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $ImportJobsFilterComposer
    extends Composer<_$AccountDatabase, ImportJobs> {
  $ImportJobsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get importJobId => $composableBuilder(
    column: $table.importJobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceUserId => $composableBuilder(
    column: $table.sourceUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get archivePath => $composableBuilder(
    column: $table.archivePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestHash => $composableBuilder(
    column: $table.manifestHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalItems => $composableBuilder(
    column: $table.totalItems,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedItems => $composableBuilder(
    column: $table.completedItems,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $LocalAccountFilterComposer get userId {
    final $LocalAccountFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountFilterComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> importItemsRefs(
    Expression<bool> Function($ImportItemsFilterComposer f) f,
  ) {
    final $ImportItemsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importJobId,
      referencedTable: $db.importItems,
      getReferencedColumn: (t) => t.importJobId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportItemsFilterComposer(
            $db: $db,
            $table: $db.importItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $ImportJobsOrderingComposer
    extends Composer<_$AccountDatabase, ImportJobs> {
  $ImportJobsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get importJobId => $composableBuilder(
    column: $table.importJobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceUserId => $composableBuilder(
    column: $table.sourceUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get archivePath => $composableBuilder(
    column: $table.archivePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestHash => $composableBuilder(
    column: $table.manifestHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalItems => $composableBuilder(
    column: $table.totalItems,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedItems => $composableBuilder(
    column: $table.completedItems,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalAccountOrderingComposer get userId {
    final $LocalAccountOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountOrderingComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ImportJobsAnnotationComposer
    extends Composer<_$AccountDatabase, ImportJobs> {
  $ImportJobsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get importJobId => $composableBuilder(
    column: $table.importJobId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceUserId => $composableBuilder(
    column: $table.sourceUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get archivePath => $composableBuilder(
    column: $table.archivePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get manifestHash => $composableBuilder(
    column: $table.manifestHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get totalItems => $composableBuilder(
    column: $table.totalItems,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedItems => $composableBuilder(
    column: $table.completedItems,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $LocalAccountAnnotationComposer get userId {
    final $LocalAccountAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountAnnotationComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> importItemsRefs<T extends Object>(
    Expression<T> Function($ImportItemsAnnotationComposer a) f,
  ) {
    final $ImportItemsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importJobId,
      referencedTable: $db.importItems,
      getReferencedColumn: (t) => t.importJobId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportItemsAnnotationComposer(
            $db: $db,
            $table: $db.importItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $ImportJobsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          ImportJobs,
          ImportJob,
          $ImportJobsFilterComposer,
          $ImportJobsOrderingComposer,
          $ImportJobsAnnotationComposer,
          $ImportJobsCreateCompanionBuilder,
          $ImportJobsUpdateCompanionBuilder,
          (ImportJob, $ImportJobsReferences),
          ImportJob,
          PrefetchHooks Function({bool userId, bool importItemsRefs})
        > {
  $ImportJobsTableManager(_$AccountDatabase db, ImportJobs table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ImportJobsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ImportJobsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ImportJobsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> importJobId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> sourceUserId = const Value.absent(),
                Value<String> archivePath = const Value.absent(),
                Value<String> manifestHash = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> totalItems = const Value.absent(),
                Value<int> completedItems = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportJobsCompanion(
                importJobId: importJobId,
                userId: userId,
                sourceUserId: sourceUserId,
                archivePath: archivePath,
                manifestHash: manifestHash,
                status: status,
                totalItems: totalItems,
                completedItems: completedItems,
                errorCode: errorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String importJobId,
                required String userId,
                required String sourceUserId,
                required String archivePath,
                required String manifestHash,
                Value<String> status = const Value.absent(),
                required int totalItems,
                Value<int> completedItems = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ImportJobsCompanion.insert(
                importJobId: importJobId,
                userId: userId,
                sourceUserId: sourceUserId,
                archivePath: archivePath,
                manifestHash: manifestHash,
                status: status,
                totalItems: totalItems,
                completedItems: completedItems,
                errorCode: errorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<ImportJobs, ImportJob>(table),
                  $ImportJobsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false, importItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (importItemsRefs) db.importItems],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.userId,
                        referencedTable: $ImportJobsReferences._userIdTable(db),
                        referencedColumn: $ImportJobsReferences
                            ._userIdTable(db)
                            .userId,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (importItemsRefs)
                    await $_getPrefetchedData<
                      ImportJob,
                      ImportJobs,
                      ImportItem
                    >(
                      currentTable: table,
                      referencedTable: $ImportJobsReferences
                          ._importItemsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $ImportJobsReferences(db, table, p0).importItemsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.importJobId == item.importJobId,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $ImportJobsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      ImportJobs,
      ImportJob,
      $ImportJobsFilterComposer,
      $ImportJobsOrderingComposer,
      $ImportJobsAnnotationComposer,
      $ImportJobsCreateCompanionBuilder,
      $ImportJobsUpdateCompanionBuilder,
      (ImportJob, $ImportJobsReferences),
      ImportJob,
      PrefetchHooks Function({bool userId, bool importItemsRefs})
    >;
typedef $ImportItemsCreateCompanionBuilder = ImportItemsCompanion Function({
  required String importJobId,
  required int ordinal,
  required String resourceId,
  Value<String> status,
  Value<String?> resultPayload,
  required int updatedAt,
  Value<int> rowid,
});
typedef $ImportItemsUpdateCompanionBuilder = ImportItemsCompanion Function({
  Value<String> importJobId,
  Value<int> ordinal,
  Value<String> resourceId,
  Value<String> status,
  Value<String?> resultPayload,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $ImportItemsReferences
    extends BaseReferences<_$AccountDatabase, ImportItems, ImportItem> {
  $ImportItemsReferences(super.$_db, super.$_table, super.$_typedResult);

  static ImportJobs _importJobIdTable(_$AccountDatabase db) => db.importJobs
      .createAlias('import_items__import_job_id__import_jobs__import_job_id');

  $ImportJobsProcessedTableManager get importJobId {
    final $_column = $_itemColumn<String>('import_job_id')!;

    final manager = $ImportJobsTableManager(
      $_db,
      $_db.importJobs,
    ).filter((f) => f.importJobId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_importJobIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $ImportItemsFilterComposer
    extends Composer<_$AccountDatabase, ImportItems> {
  $ImportItemsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultPayload => $composableBuilder(
    column: $table.resultPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $ImportJobsFilterComposer get importJobId {
    final $ImportJobsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importJobId,
      referencedTable: $db.importJobs,
      getReferencedColumn: (t) => t.importJobId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportJobsFilterComposer(
            $db: $db,
            $table: $db.importJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ImportItemsOrderingComposer
    extends Composer<_$AccountDatabase, ImportItems> {
  $ImportItemsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultPayload => $composableBuilder(
    column: $table.resultPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $ImportJobsOrderingComposer get importJobId {
    final $ImportJobsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importJobId,
      referencedTable: $db.importJobs,
      getReferencedColumn: (t) => t.importJobId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportJobsOrderingComposer(
            $db: $db,
            $table: $db.importJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ImportItemsAnnotationComposer
    extends Composer<_$AccountDatabase, ImportItems> {
  $ImportItemsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get resultPayload => $composableBuilder(
    column: $table.resultPayload,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $ImportJobsAnnotationComposer get importJobId {
    final $ImportJobsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importJobId,
      referencedTable: $db.importJobs,
      getReferencedColumn: (t) => t.importJobId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportJobsAnnotationComposer(
            $db: $db,
            $table: $db.importJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ImportItemsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          ImportItems,
          ImportItem,
          $ImportItemsFilterComposer,
          $ImportItemsOrderingComposer,
          $ImportItemsAnnotationComposer,
          $ImportItemsCreateCompanionBuilder,
          $ImportItemsUpdateCompanionBuilder,
          (ImportItem, $ImportItemsReferences),
          ImportItem,
          PrefetchHooks Function({bool importJobId})
        > {
  $ImportItemsTableManager(_$AccountDatabase db, ImportItems table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ImportItemsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ImportItemsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ImportItemsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> importJobId = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> resourceId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> resultPayload = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportItemsCompanion(
                importJobId: importJobId,
                ordinal: ordinal,
                resourceId: resourceId,
                status: status,
                resultPayload: resultPayload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String importJobId,
                required int ordinal,
                required String resourceId,
                Value<String> status = const Value.absent(),
                Value<String?> resultPayload = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ImportItemsCompanion.insert(
                importJobId: importJobId,
                ordinal: ordinal,
                resourceId: resourceId,
                status: status,
                resultPayload: resultPayload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<ImportItems, ImportItem>(table),
                  $ImportItemsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({importJobId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (importJobId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.importJobId,
                        referencedTable: $ImportItemsReferences
                            ._importJobIdTable(db),
                        referencedColumn: $ImportItemsReferences
                            ._importJobIdTable(db)
                            .importJobId,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $ImportItemsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      ImportItems,
      ImportItem,
      $ImportItemsFilterComposer,
      $ImportItemsOrderingComposer,
      $ImportItemsAnnotationComposer,
      $ImportItemsCreateCompanionBuilder,
      $ImportItemsUpdateCompanionBuilder,
      (ImportItem, $ImportItemsReferences),
      ImportItem,
      PrefetchHooks Function({bool importJobId})
    >;
typedef $SyncCursorsCreateCompanionBuilder = SyncCursorsCompanion Function({
  Value<int> singleton,
  required String userId,
  Value<int?> lastChangeSeq,
  Value<int> baselineComplete,
  Value<String?> snapshotResume,
  required int updatedAt,
});
typedef $SyncCursorsUpdateCompanionBuilder = SyncCursorsCompanion Function({
  Value<int> singleton,
  Value<String> userId,
  Value<int?> lastChangeSeq,
  Value<int> baselineComplete,
  Value<String?> snapshotResume,
  Value<int> updatedAt,
});

final class $SyncCursorsReferences
    extends BaseReferences<_$AccountDatabase, SyncCursors, SyncCursor> {
  $SyncCursorsReferences(super.$_db, super.$_table, super.$_typedResult);

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('sync_cursors__user_id__local_account__user_id');

  $LocalAccountProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $LocalAccountTableManager(
      $_db,
      $_db.localAccount,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $SyncCursorsFilterComposer
    extends Composer<_$AccountDatabase, SyncCursors> {
  $SyncCursorsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastChangeSeq => $composableBuilder(
    column: $table.lastChangeSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baselineComplete => $composableBuilder(
    column: $table.baselineComplete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotResume => $composableBuilder(
    column: $table.snapshotResume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $LocalAccountFilterComposer get userId {
    final $LocalAccountFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountFilterComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SyncCursorsOrderingComposer
    extends Composer<_$AccountDatabase, SyncCursors> {
  $SyncCursorsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastChangeSeq => $composableBuilder(
    column: $table.lastChangeSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baselineComplete => $composableBuilder(
    column: $table.baselineComplete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotResume => $composableBuilder(
    column: $table.snapshotResume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalAccountOrderingComposer get userId {
    final $LocalAccountOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountOrderingComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SyncCursorsAnnotationComposer
    extends Composer<_$AccountDatabase, SyncCursors> {
  $SyncCursorsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singleton =>
      $composableBuilder(column: $table.singleton, builder: (column) => column);

  GeneratedColumn<int> get lastChangeSeq => $composableBuilder(
    column: $table.lastChangeSeq,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baselineComplete => $composableBuilder(
    column: $table.baselineComplete,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snapshotResume => $composableBuilder(
    column: $table.snapshotResume,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $LocalAccountAnnotationComposer get userId {
    final $LocalAccountAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.localAccount,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalAccountAnnotationComposer(
            $db: $db,
            $table: $db.localAccount,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SyncCursorsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          SyncCursors,
          SyncCursor,
          $SyncCursorsFilterComposer,
          $SyncCursorsOrderingComposer,
          $SyncCursorsAnnotationComposer,
          $SyncCursorsCreateCompanionBuilder,
          $SyncCursorsUpdateCompanionBuilder,
          (SyncCursor, $SyncCursorsReferences),
          SyncCursor,
          PrefetchHooks Function({bool userId})
        > {
  $SyncCursorsTableManager(_$AccountDatabase db, SyncCursors table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SyncCursorsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SyncCursorsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SyncCursorsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int?> lastChangeSeq = const Value.absent(),
                Value<int> baselineComplete = const Value.absent(),
                Value<String?> snapshotResume = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => SyncCursorsCompanion(
                singleton: singleton,
                userId: userId,
                lastChangeSeq: lastChangeSeq,
                baselineComplete: baselineComplete,
                snapshotResume: snapshotResume,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                required String userId,
                Value<int?> lastChangeSeq = const Value.absent(),
                Value<int> baselineComplete = const Value.absent(),
                Value<String?> snapshotResume = const Value.absent(),
                required int updatedAt,
              }) => SyncCursorsCompanion.insert(
                singleton: singleton,
                userId: userId,
                lastChangeSeq: lastChangeSeq,
                baselineComplete: baselineComplete,
                snapshotResume: snapshotResume,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<SyncCursors, SyncCursor>(table),
                  $SyncCursorsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.userId,
                        referencedTable: $SyncCursorsReferences._userIdTable(
                          db,
                        ),
                        referencedColumn: $SyncCursorsReferences
                            ._userIdTable(db)
                            .userId,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $SyncCursorsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      SyncCursors,
      SyncCursor,
      $SyncCursorsFilterComposer,
      $SyncCursorsOrderingComposer,
      $SyncCursorsAnnotationComposer,
      $SyncCursorsCreateCompanionBuilder,
      $SyncCursorsUpdateCompanionBuilder,
      (SyncCursor, $SyncCursorsReferences),
      SyncCursor,
      PrefetchHooks Function({bool userId})
    >;
typedef $MutationWireRequestsCreateCompanionBuilder =
    MutationWireRequestsCompanion Function({
      required String opId,
      required String contractVersion,
      required String httpMethod,
      required String relativePath,
      required String bodyJson,
      required String wireHash,
      Value<int> rowid,
    });
typedef $MutationWireRequestsUpdateCompanionBuilder =
    MutationWireRequestsCompanion Function({
      Value<String> opId,
      Value<String> contractVersion,
      Value<String> httpMethod,
      Value<String> relativePath,
      Value<String> bodyJson,
      Value<String> wireHash,
      Value<int> rowid,
    });

final class $MutationWireRequestsReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          MutationWireRequests,
          MutationWireRequest
        > {
  $MutationWireRequestsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static LocalMutations _opIdTable(_$AccountDatabase db) => db.localMutations
      .createAlias('mutation_wire_requests__op_id__local_mutations__op_id');

  $LocalMutationsProcessedTableManager get opId {
    final $_column = $_itemColumn<String>('op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_opIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $MutationWireRequestsFilterComposer
    extends Composer<_$AccountDatabase, MutationWireRequests> {
  $MutationWireRequestsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get contractVersion => $composableBuilder(
    column: $table.contractVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get httpMethod => $composableBuilder(
    column: $table.httpMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wireHash => $composableBuilder(
    column: $table.wireHash,
    builder: (column) => ColumnFilters(column),
  );

  $LocalMutationsFilterComposer get opId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.localMutations,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalMutationsFilterComposer(
            $db: $db,
            $table: $db.localMutations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MutationWireRequestsOrderingComposer
    extends Composer<_$AccountDatabase, MutationWireRequests> {
  $MutationWireRequestsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get contractVersion => $composableBuilder(
    column: $table.contractVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get httpMethod => $composableBuilder(
    column: $table.httpMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wireHash => $composableBuilder(
    column: $table.wireHash,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalMutationsOrderingComposer get opId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.localMutations,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalMutationsOrderingComposer(
            $db: $db,
            $table: $db.localMutations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MutationWireRequestsAnnotationComposer
    extends Composer<_$AccountDatabase, MutationWireRequests> {
  $MutationWireRequestsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get contractVersion => $composableBuilder(
    column: $table.contractVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get httpMethod => $composableBuilder(
    column: $table.httpMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bodyJson =>
      $composableBuilder(column: $table.bodyJson, builder: (column) => column);

  GeneratedColumn<String> get wireHash =>
      $composableBuilder(column: $table.wireHash, builder: (column) => column);

  $LocalMutationsAnnotationComposer get opId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.localMutations,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalMutationsAnnotationComposer(
            $db: $db,
            $table: $db.localMutations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MutationWireRequestsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          MutationWireRequests,
          MutationWireRequest,
          $MutationWireRequestsFilterComposer,
          $MutationWireRequestsOrderingComposer,
          $MutationWireRequestsAnnotationComposer,
          $MutationWireRequestsCreateCompanionBuilder,
          $MutationWireRequestsUpdateCompanionBuilder,
          (MutationWireRequest, $MutationWireRequestsReferences),
          MutationWireRequest,
          PrefetchHooks Function({bool opId})
        > {
  $MutationWireRequestsTableManager(
    _$AccountDatabase db,
    MutationWireRequests table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MutationWireRequestsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MutationWireRequestsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MutationWireRequestsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> opId = const Value.absent(),
                Value<String> contractVersion = const Value.absent(),
                Value<String> httpMethod = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String> bodyJson = const Value.absent(),
                Value<String> wireHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MutationWireRequestsCompanion(
                opId: opId,
                contractVersion: contractVersion,
                httpMethod: httpMethod,
                relativePath: relativePath,
                bodyJson: bodyJson,
                wireHash: wireHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String opId,
                required String contractVersion,
                required String httpMethod,
                required String relativePath,
                required String bodyJson,
                required String wireHash,
                Value<int> rowid = const Value.absent(),
              }) => MutationWireRequestsCompanion.insert(
                opId: opId,
                contractVersion: contractVersion,
                httpMethod: httpMethod,
                relativePath: relativePath,
                bodyJson: bodyJson,
                wireHash: wireHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<MutationWireRequests, MutationWireRequest>(table),
                  $MutationWireRequestsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({opId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (opId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.opId,
                        referencedTable: $MutationWireRequestsReferences
                            ._opIdTable(db),
                        referencedColumn: $MutationWireRequestsReferences
                            ._opIdTable(db)
                            .opId,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $MutationWireRequestsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      MutationWireRequests,
      MutationWireRequest,
      $MutationWireRequestsFilterComposer,
      $MutationWireRequestsOrderingComposer,
      $MutationWireRequestsAnnotationComposer,
      $MutationWireRequestsCreateCompanionBuilder,
      $MutationWireRequestsUpdateCompanionBuilder,
      (MutationWireRequest, $MutationWireRequestsReferences),
      MutationWireRequest,
      PrefetchHooks Function({bool opId})
    >;
typedef $MutationRetryControlsCreateCompanionBuilder =
    MutationRetryControlsCompanion Function({
      required String opId,
      Value<int?> automaticRetriesClaimed,
      required String retryMode,
      required String lastAttemptKind,
      Value<int> rowid,
    });
typedef $MutationRetryControlsUpdateCompanionBuilder =
    MutationRetryControlsCompanion Function({
      Value<String> opId,
      Value<int?> automaticRetriesClaimed,
      Value<String> retryMode,
      Value<String> lastAttemptKind,
      Value<int> rowid,
    });

final class $MutationRetryControlsReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          MutationRetryControls,
          MutationRetryControl
        > {
  $MutationRetryControlsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static LocalMutations _opIdTable(_$AccountDatabase db) => db.localMutations
      .createAlias('mutation_retry_controls__op_id__local_mutations__op_id');

  $LocalMutationsProcessedTableManager get opId {
    final $_column = $_itemColumn<String>('op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_opIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $MutationRetryControlsFilterComposer
    extends Composer<_$AccountDatabase, MutationRetryControls> {
  $MutationRetryControlsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get automaticRetriesClaimed => $composableBuilder(
    column: $table.automaticRetriesClaimed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get retryMode => $composableBuilder(
    column: $table.retryMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastAttemptKind => $composableBuilder(
    column: $table.lastAttemptKind,
    builder: (column) => ColumnFilters(column),
  );

  $LocalMutationsFilterComposer get opId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.localMutations,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalMutationsFilterComposer(
            $db: $db,
            $table: $db.localMutations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MutationRetryControlsOrderingComposer
    extends Composer<_$AccountDatabase, MutationRetryControls> {
  $MutationRetryControlsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get automaticRetriesClaimed => $composableBuilder(
    column: $table.automaticRetriesClaimed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get retryMode => $composableBuilder(
    column: $table.retryMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastAttemptKind => $composableBuilder(
    column: $table.lastAttemptKind,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalMutationsOrderingComposer get opId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.localMutations,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalMutationsOrderingComposer(
            $db: $db,
            $table: $db.localMutations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MutationRetryControlsAnnotationComposer
    extends Composer<_$AccountDatabase, MutationRetryControls> {
  $MutationRetryControlsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get automaticRetriesClaimed => $composableBuilder(
    column: $table.automaticRetriesClaimed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get retryMode =>
      $composableBuilder(column: $table.retryMode, builder: (column) => column);

  GeneratedColumn<String> get lastAttemptKind => $composableBuilder(
    column: $table.lastAttemptKind,
    builder: (column) => column,
  );

  $LocalMutationsAnnotationComposer get opId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.localMutations,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LocalMutationsAnnotationComposer(
            $db: $db,
            $table: $db.localMutations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MutationRetryControlsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          MutationRetryControls,
          MutationRetryControl,
          $MutationRetryControlsFilterComposer,
          $MutationRetryControlsOrderingComposer,
          $MutationRetryControlsAnnotationComposer,
          $MutationRetryControlsCreateCompanionBuilder,
          $MutationRetryControlsUpdateCompanionBuilder,
          (MutationRetryControl, $MutationRetryControlsReferences),
          MutationRetryControl,
          PrefetchHooks Function({bool opId})
        > {
  $MutationRetryControlsTableManager(
    _$AccountDatabase db,
    MutationRetryControls table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MutationRetryControlsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MutationRetryControlsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MutationRetryControlsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> opId = const Value.absent(),
                Value<int?> automaticRetriesClaimed = const Value.absent(),
                Value<String> retryMode = const Value.absent(),
                Value<String> lastAttemptKind = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MutationRetryControlsCompanion(
                opId: opId,
                automaticRetriesClaimed: automaticRetriesClaimed,
                retryMode: retryMode,
                lastAttemptKind: lastAttemptKind,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String opId,
                Value<int?> automaticRetriesClaimed = const Value.absent(),
                required String retryMode,
                required String lastAttemptKind,
                Value<int> rowid = const Value.absent(),
              }) => MutationRetryControlsCompanion.insert(
                opId: opId,
                automaticRetriesClaimed: automaticRetriesClaimed,
                retryMode: retryMode,
                lastAttemptKind: lastAttemptKind,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<MutationRetryControls, MutationRetryControl>(
                    table,
                  ),
                  $MutationRetryControlsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({opId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (opId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.opId,
                        referencedTable: $MutationRetryControlsReferences
                            ._opIdTable(db),
                        referencedColumn: $MutationRetryControlsReferences
                            ._opIdTable(db)
                            .opId,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $MutationRetryControlsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      MutationRetryControls,
      MutationRetryControl,
      $MutationRetryControlsFilterComposer,
      $MutationRetryControlsOrderingComposer,
      $MutationRetryControlsAnnotationComposer,
      $MutationRetryControlsCreateCompanionBuilder,
      $MutationRetryControlsUpdateCompanionBuilder,
      (MutationRetryControl, $MutationRetryControlsReferences),
      MutationRetryControl,
      PrefetchHooks Function({bool opId})
    >;

class $AccountDatabaseManager {
  final _$AccountDatabase _db;
  $AccountDatabaseManager(this._db);
  $LocalAccountTableManager get localAccount =>
      $LocalAccountTableManager(_db, _db.localAccount);
  $MetadataCopiesTableManager get metadataCopies =>
      $MetadataCopiesTableManager(_db, _db.metadataCopies);
  $LocalMutationsTableManager get localMutations =>
      $LocalMutationsTableManager(_db, _db.localMutations);
  $LocalRecordingFilesTableManager get localRecordingFiles =>
      $LocalRecordingFilesTableManager(_db, _db.localRecordingFiles);
  $RecordingJournalsTableManager get recordingJournals =>
      $RecordingJournalsTableManager(_db, _db.recordingJournals);
  $ImportJobsTableManager get importJobs =>
      $ImportJobsTableManager(_db, _db.importJobs);
  $ImportItemsTableManager get importItems =>
      $ImportItemsTableManager(_db, _db.importItems);
  $SyncCursorsTableManager get syncCursors =>
      $SyncCursorsTableManager(_db, _db.syncCursors);
  $MutationWireRequestsTableManager get mutationWireRequests =>
      $MutationWireRequestsTableManager(_db, _db.mutationWireRequests);
  $MutationRetryControlsTableManager get mutationRetryControls =>
      $MutationRetryControlsTableManager(_db, _db.mutationRetryControls);
}
