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

class RecordingFollowups extends Table
    with TableInfo<RecordingFollowups, RecordingFollowup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RecordingFollowups(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _originalOpIdMeta = const VerificationMeta(
    'originalOpId',
  );
  late final GeneratedColumn<String> originalOpId = GeneratedColumn<String>(
    'original_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _replacementOpIdMeta = const VerificationMeta(
    'replacementOpId',
  );
  late final GeneratedColumn<String> replacementOpId = GeneratedColumn<String>(
    'replacement_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _predecessorOpIdMeta = const VerificationMeta(
    'predecessorOpId',
  );
  late final GeneratedColumn<String> predecessorOpId = GeneratedColumn<String>(
    'predecessor_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES local_mutations(op_id)',
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
  static const VerificationMeta _logicalOrderMeta = const VerificationMeta(
    'logicalOrder',
  );
  late final GeneratedColumn<int> logicalOrder = GeneratedColumn<int>(
    'logical_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (logical_order > 0)',
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
    originalOpId,
    replacementOpId,
    predecessorOpId,
    userId,
    logicalOrder,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recording_followups';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecordingFollowup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('original_op_id')) {
      context.handle(
        _originalOpIdMeta,
        originalOpId.isAcceptableOrUnknown(
          data['original_op_id']!,
          _originalOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalOpIdMeta);
    }
    if (data.containsKey('replacement_op_id')) {
      context.handle(
        _replacementOpIdMeta,
        replacementOpId.isAcceptableOrUnknown(
          data['replacement_op_id']!,
          _replacementOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_replacementOpIdMeta);
    }
    if (data.containsKey('predecessor_op_id')) {
      context.handle(
        _predecessorOpIdMeta,
        predecessorOpId.isAcceptableOrUnknown(
          data['predecessor_op_id']!,
          _predecessorOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_predecessorOpIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('logical_order')) {
      context.handle(
        _logicalOrderMeta,
        logicalOrder.isAcceptableOrUnknown(
          data['logical_order']!,
          _logicalOrderMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_logicalOrderMeta);
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
  Set<GeneratedColumn> get $primaryKey => {originalOpId};
  @override
  RecordingFollowup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecordingFollowup(
      originalOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_op_id'],
      )!,
      replacementOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replacement_op_id'],
      )!,
      predecessorOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}predecessor_op_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      logicalOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logical_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  RecordingFollowups createAlias(String alias) {
    return RecordingFollowups(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const [
    'CHECK(original_op_id <> replacement_op_id)',
    'CHECK(original_op_id <> predecessor_op_id)',
    'CHECK(replacement_op_id <> predecessor_op_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class RecordingFollowup extends DataClass
    implements Insertable<RecordingFollowup> {
  final String originalOpId;
  final String replacementOpId;
  final String predecessorOpId;
  final String userId;
  final int logicalOrder;
  final int createdAt;
  const RecordingFollowup({
    required this.originalOpId,
    required this.replacementOpId,
    required this.predecessorOpId,
    required this.userId,
    required this.logicalOrder,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['original_op_id'] = Variable<String>(originalOpId);
    map['replacement_op_id'] = Variable<String>(replacementOpId);
    map['predecessor_op_id'] = Variable<String>(predecessorOpId);
    map['user_id'] = Variable<String>(userId);
    map['logical_order'] = Variable<int>(logicalOrder);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  RecordingFollowupsCompanion toCompanion(bool nullToAbsent) {
    return RecordingFollowupsCompanion(
      originalOpId: Value(originalOpId),
      replacementOpId: Value(replacementOpId),
      predecessorOpId: Value(predecessorOpId),
      userId: Value(userId),
      logicalOrder: Value(logicalOrder),
      createdAt: Value(createdAt),
    );
  }

  factory RecordingFollowup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecordingFollowup(
      originalOpId: serializer.fromJson<String>(json['original_op_id']),
      replacementOpId: serializer.fromJson<String>(json['replacement_op_id']),
      predecessorOpId: serializer.fromJson<String>(json['predecessor_op_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      logicalOrder: serializer.fromJson<int>(json['logical_order']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'original_op_id': serializer.toJson<String>(originalOpId),
      'replacement_op_id': serializer.toJson<String>(replacementOpId),
      'predecessor_op_id': serializer.toJson<String>(predecessorOpId),
      'user_id': serializer.toJson<String>(userId),
      'logical_order': serializer.toJson<int>(logicalOrder),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  RecordingFollowup copyWith({
    String? originalOpId,
    String? replacementOpId,
    String? predecessorOpId,
    String? userId,
    int? logicalOrder,
    int? createdAt,
  }) => RecordingFollowup(
    originalOpId: originalOpId ?? this.originalOpId,
    replacementOpId: replacementOpId ?? this.replacementOpId,
    predecessorOpId: predecessorOpId ?? this.predecessorOpId,
    userId: userId ?? this.userId,
    logicalOrder: logicalOrder ?? this.logicalOrder,
    createdAt: createdAt ?? this.createdAt,
  );
  RecordingFollowup copyWithCompanion(RecordingFollowupsCompanion data) {
    return RecordingFollowup(
      originalOpId: data.originalOpId.present
          ? data.originalOpId.value
          : this.originalOpId,
      replacementOpId: data.replacementOpId.present
          ? data.replacementOpId.value
          : this.replacementOpId,
      predecessorOpId: data.predecessorOpId.present
          ? data.predecessorOpId.value
          : this.predecessorOpId,
      userId: data.userId.present ? data.userId.value : this.userId,
      logicalOrder: data.logicalOrder.present
          ? data.logicalOrder.value
          : this.logicalOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecordingFollowup(')
          ..write('originalOpId: $originalOpId, ')
          ..write('replacementOpId: $replacementOpId, ')
          ..write('predecessorOpId: $predecessorOpId, ')
          ..write('userId: $userId, ')
          ..write('logicalOrder: $logicalOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    originalOpId,
    replacementOpId,
    predecessorOpId,
    userId,
    logicalOrder,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecordingFollowup &&
          other.originalOpId == this.originalOpId &&
          other.replacementOpId == this.replacementOpId &&
          other.predecessorOpId == this.predecessorOpId &&
          other.userId == this.userId &&
          other.logicalOrder == this.logicalOrder &&
          other.createdAt == this.createdAt);
}

class RecordingFollowupsCompanion extends UpdateCompanion<RecordingFollowup> {
  final Value<String> originalOpId;
  final Value<String> replacementOpId;
  final Value<String> predecessorOpId;
  final Value<String> userId;
  final Value<int> logicalOrder;
  final Value<int> createdAt;
  const RecordingFollowupsCompanion({
    this.originalOpId = const Value.absent(),
    this.replacementOpId = const Value.absent(),
    this.predecessorOpId = const Value.absent(),
    this.userId = const Value.absent(),
    this.logicalOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  RecordingFollowupsCompanion.insert({
    required String originalOpId,
    required String replacementOpId,
    required String predecessorOpId,
    required String userId,
    required int logicalOrder,
    required int createdAt,
  }) : originalOpId = Value(originalOpId),
       replacementOpId = Value(replacementOpId),
       predecessorOpId = Value(predecessorOpId),
       userId = Value(userId),
       logicalOrder = Value(logicalOrder),
       createdAt = Value(createdAt);
  static Insertable<RecordingFollowup> custom({
    Expression<String>? originalOpId,
    Expression<String>? replacementOpId,
    Expression<String>? predecessorOpId,
    Expression<String>? userId,
    Expression<int>? logicalOrder,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (originalOpId != null) 'original_op_id': originalOpId,
      if (replacementOpId != null) 'replacement_op_id': replacementOpId,
      if (predecessorOpId != null) 'predecessor_op_id': predecessorOpId,
      if (userId != null) 'user_id': userId,
      if (logicalOrder != null) 'logical_order': logicalOrder,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  RecordingFollowupsCompanion copyWith({
    Value<String>? originalOpId,
    Value<String>? replacementOpId,
    Value<String>? predecessorOpId,
    Value<String>? userId,
    Value<int>? logicalOrder,
    Value<int>? createdAt,
  }) {
    return RecordingFollowupsCompanion(
      originalOpId: originalOpId ?? this.originalOpId,
      replacementOpId: replacementOpId ?? this.replacementOpId,
      predecessorOpId: predecessorOpId ?? this.predecessorOpId,
      userId: userId ?? this.userId,
      logicalOrder: logicalOrder ?? this.logicalOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (originalOpId.present) {
      map['original_op_id'] = Variable<String>(originalOpId.value);
    }
    if (replacementOpId.present) {
      map['replacement_op_id'] = Variable<String>(replacementOpId.value);
    }
    if (predecessorOpId.present) {
      map['predecessor_op_id'] = Variable<String>(predecessorOpId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (logicalOrder.present) {
      map['logical_order'] = Variable<int>(logicalOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordingFollowupsCompanion(')
          ..write('originalOpId: $originalOpId, ')
          ..write('replacementOpId: $replacementOpId, ')
          ..write('predecessorOpId: $predecessorOpId, ')
          ..write('userId: $userId, ')
          ..write('logicalOrder: $logicalOrder, ')
          ..write('createdAt: $createdAt')
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
    $customConstraints: 'NOT NULL CHECK (http_method IN (\'POST\', \'PATCH\', \'PUT\', \'DELETE\'))',
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

class SongAliases extends Table with TableInfo<SongAliases, SongAliase> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SongAliases(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceSongIdMeta = const VerificationMeta(
    'sourceSongId',
  );
  late final GeneratedColumn<String> sourceSongId = GeneratedColumn<String>(
    'source_song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _canonicalSongIdMeta = const VerificationMeta(
    'canonicalSongId',
  );
  late final GeneratedColumn<String> canonicalSongId = GeneratedColumn<String>(
    'canonical_song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
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
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT \'SONG\' CHECK (entity_type = \'SONG\')',
    defaultValue: const CustomExpression('\'SONG\''),
  );
  static const VerificationMeta _mappingOpIdMeta = const VerificationMeta(
    'mappingOpId',
  );
  late final GeneratedColumn<String> mappingOpId = GeneratedColumn<String>(
    'mapping_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _receiptStatusMeta = const VerificationMeta(
    'receiptStatus',
  );
  late final GeneratedColumn<int> receiptStatus = GeneratedColumn<int>(
    'receipt_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (receipt_status = 200)',
  );
  static const VerificationMeta _receiptBodyMeta = const VerificationMeta(
    'receiptBody',
  );
  late final GeneratedColumn<String> receiptBody = GeneratedColumn<String>(
    'receipt_body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(receipt_body) AND json_type(receipt_body) = \'object\')',
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
    sourceSongId,
    canonicalSongId,
    userId,
    entityType,
    mappingOpId,
    receiptStatus,
    receiptBody,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'song_aliases';
  @override
  VerificationContext validateIntegrity(
    Insertable<SongAliase> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_song_id')) {
      context.handle(
        _sourceSongIdMeta,
        sourceSongId.isAcceptableOrUnknown(
          data['source_song_id']!,
          _sourceSongIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceSongIdMeta);
    }
    if (data.containsKey('canonical_song_id')) {
      context.handle(
        _canonicalSongIdMeta,
        canonicalSongId.isAcceptableOrUnknown(
          data['canonical_song_id']!,
          _canonicalSongIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalSongIdMeta);
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
    }
    if (data.containsKey('mapping_op_id')) {
      context.handle(
        _mappingOpIdMeta,
        mappingOpId.isAcceptableOrUnknown(
          data['mapping_op_id']!,
          _mappingOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mappingOpIdMeta);
    }
    if (data.containsKey('receipt_status')) {
      context.handle(
        _receiptStatusMeta,
        receiptStatus.isAcceptableOrUnknown(
          data['receipt_status']!,
          _receiptStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receiptStatusMeta);
    }
    if (data.containsKey('receipt_body')) {
      context.handle(
        _receiptBodyMeta,
        receiptBody.isAcceptableOrUnknown(
          data['receipt_body']!,
          _receiptBodyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receiptBodyMeta);
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
  Set<GeneratedColumn> get $primaryKey => {sourceSongId};
  @override
  SongAliase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SongAliase(
      sourceSongId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_song_id'],
      )!,
      canonicalSongId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_song_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      mappingOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mapping_op_id'],
      )!,
      receiptStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}receipt_status'],
      )!,
      receiptBody: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_body'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  SongAliases createAlias(String alias) {
    return SongAliases(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(entity_type, source_song_id)REFERENCES metadata_copies(entity_type, entity_id)',
    'FOREIGN KEY(entity_type, canonical_song_id)REFERENCES metadata_copies(entity_type, entity_id)',
    'CHECK(source_song_id <> canonical_song_id)',
    'CHECK(json_type(receipt_body, \'\$.created\') IS \'false\')',
    'CHECK(json_type(receipt_body, \'\$.song\') IS \'object\')',
    'CHECK(json_extract(receipt_body, \'\$.canonical_song_id\') IS canonical_song_id)',
    'CHECK(json_extract(receipt_body, \'\$.song.id\') IS canonical_song_id)',
    'CHECK(json_type(receipt_body, \'\$.song.revision\') IS \'integer\' AND json_extract(receipt_body, \'\$.song.revision\') > 0)',
    'CHECK(json_extract(receipt_body, \'\$.song.lifecycle_state\') IS \'ACTIVE\')',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class SongAliase extends DataClass implements Insertable<SongAliase> {
  final String sourceSongId;
  final String canonicalSongId;
  final String userId;
  final String entityType;
  final String mappingOpId;
  final int receiptStatus;
  final String receiptBody;
  final int createdAt;
  const SongAliase({
    required this.sourceSongId,
    required this.canonicalSongId,
    required this.userId,
    required this.entityType,
    required this.mappingOpId,
    required this.receiptStatus,
    required this.receiptBody,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_song_id'] = Variable<String>(sourceSongId);
    map['canonical_song_id'] = Variable<String>(canonicalSongId);
    map['user_id'] = Variable<String>(userId);
    map['entity_type'] = Variable<String>(entityType);
    map['mapping_op_id'] = Variable<String>(mappingOpId);
    map['receipt_status'] = Variable<int>(receiptStatus);
    map['receipt_body'] = Variable<String>(receiptBody);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  SongAliasesCompanion toCompanion(bool nullToAbsent) {
    return SongAliasesCompanion(
      sourceSongId: Value(sourceSongId),
      canonicalSongId: Value(canonicalSongId),
      userId: Value(userId),
      entityType: Value(entityType),
      mappingOpId: Value(mappingOpId),
      receiptStatus: Value(receiptStatus),
      receiptBody: Value(receiptBody),
      createdAt: Value(createdAt),
    );
  }

  factory SongAliase.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SongAliase(
      sourceSongId: serializer.fromJson<String>(json['source_song_id']),
      canonicalSongId: serializer.fromJson<String>(json['canonical_song_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      entityType: serializer.fromJson<String>(json['entity_type']),
      mappingOpId: serializer.fromJson<String>(json['mapping_op_id']),
      receiptStatus: serializer.fromJson<int>(json['receipt_status']),
      receiptBody: serializer.fromJson<String>(json['receipt_body']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_song_id': serializer.toJson<String>(sourceSongId),
      'canonical_song_id': serializer.toJson<String>(canonicalSongId),
      'user_id': serializer.toJson<String>(userId),
      'entity_type': serializer.toJson<String>(entityType),
      'mapping_op_id': serializer.toJson<String>(mappingOpId),
      'receipt_status': serializer.toJson<int>(receiptStatus),
      'receipt_body': serializer.toJson<String>(receiptBody),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  SongAliase copyWith({
    String? sourceSongId,
    String? canonicalSongId,
    String? userId,
    String? entityType,
    String? mappingOpId,
    int? receiptStatus,
    String? receiptBody,
    int? createdAt,
  }) => SongAliase(
    sourceSongId: sourceSongId ?? this.sourceSongId,
    canonicalSongId: canonicalSongId ?? this.canonicalSongId,
    userId: userId ?? this.userId,
    entityType: entityType ?? this.entityType,
    mappingOpId: mappingOpId ?? this.mappingOpId,
    receiptStatus: receiptStatus ?? this.receiptStatus,
    receiptBody: receiptBody ?? this.receiptBody,
    createdAt: createdAt ?? this.createdAt,
  );
  SongAliase copyWithCompanion(SongAliasesCompanion data) {
    return SongAliase(
      sourceSongId: data.sourceSongId.present
          ? data.sourceSongId.value
          : this.sourceSongId,
      canonicalSongId: data.canonicalSongId.present
          ? data.canonicalSongId.value
          : this.canonicalSongId,
      userId: data.userId.present ? data.userId.value : this.userId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      mappingOpId: data.mappingOpId.present
          ? data.mappingOpId.value
          : this.mappingOpId,
      receiptStatus: data.receiptStatus.present
          ? data.receiptStatus.value
          : this.receiptStatus,
      receiptBody: data.receiptBody.present
          ? data.receiptBody.value
          : this.receiptBody,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SongAliase(')
          ..write('sourceSongId: $sourceSongId, ')
          ..write('canonicalSongId: $canonicalSongId, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('mappingOpId: $mappingOpId, ')
          ..write('receiptStatus: $receiptStatus, ')
          ..write('receiptBody: $receiptBody, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceSongId,
    canonicalSongId,
    userId,
    entityType,
    mappingOpId,
    receiptStatus,
    receiptBody,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SongAliase &&
          other.sourceSongId == this.sourceSongId &&
          other.canonicalSongId == this.canonicalSongId &&
          other.userId == this.userId &&
          other.entityType == this.entityType &&
          other.mappingOpId == this.mappingOpId &&
          other.receiptStatus == this.receiptStatus &&
          other.receiptBody == this.receiptBody &&
          other.createdAt == this.createdAt);
}

class SongAliasesCompanion extends UpdateCompanion<SongAliase> {
  final Value<String> sourceSongId;
  final Value<String> canonicalSongId;
  final Value<String> userId;
  final Value<String> entityType;
  final Value<String> mappingOpId;
  final Value<int> receiptStatus;
  final Value<String> receiptBody;
  final Value<int> createdAt;
  const SongAliasesCompanion({
    this.sourceSongId = const Value.absent(),
    this.canonicalSongId = const Value.absent(),
    this.userId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.mappingOpId = const Value.absent(),
    this.receiptStatus = const Value.absent(),
    this.receiptBody = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SongAliasesCompanion.insert({
    required String sourceSongId,
    required String canonicalSongId,
    required String userId,
    this.entityType = const Value.absent(),
    required String mappingOpId,
    required int receiptStatus,
    required String receiptBody,
    required int createdAt,
  }) : sourceSongId = Value(sourceSongId),
       canonicalSongId = Value(canonicalSongId),
       userId = Value(userId),
       mappingOpId = Value(mappingOpId),
       receiptStatus = Value(receiptStatus),
       receiptBody = Value(receiptBody),
       createdAt = Value(createdAt);
  static Insertable<SongAliase> custom({
    Expression<String>? sourceSongId,
    Expression<String>? canonicalSongId,
    Expression<String>? userId,
    Expression<String>? entityType,
    Expression<String>? mappingOpId,
    Expression<int>? receiptStatus,
    Expression<String>? receiptBody,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (sourceSongId != null) 'source_song_id': sourceSongId,
      if (canonicalSongId != null) 'canonical_song_id': canonicalSongId,
      if (userId != null) 'user_id': userId,
      if (entityType != null) 'entity_type': entityType,
      if (mappingOpId != null) 'mapping_op_id': mappingOpId,
      if (receiptStatus != null) 'receipt_status': receiptStatus,
      if (receiptBody != null) 'receipt_body': receiptBody,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SongAliasesCompanion copyWith({
    Value<String>? sourceSongId,
    Value<String>? canonicalSongId,
    Value<String>? userId,
    Value<String>? entityType,
    Value<String>? mappingOpId,
    Value<int>? receiptStatus,
    Value<String>? receiptBody,
    Value<int>? createdAt,
  }) {
    return SongAliasesCompanion(
      sourceSongId: sourceSongId ?? this.sourceSongId,
      canonicalSongId: canonicalSongId ?? this.canonicalSongId,
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      mappingOpId: mappingOpId ?? this.mappingOpId,
      receiptStatus: receiptStatus ?? this.receiptStatus,
      receiptBody: receiptBody ?? this.receiptBody,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceSongId.present) {
      map['source_song_id'] = Variable<String>(sourceSongId.value);
    }
    if (canonicalSongId.present) {
      map['canonical_song_id'] = Variable<String>(canonicalSongId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (mappingOpId.present) {
      map['mapping_op_id'] = Variable<String>(mappingOpId.value);
    }
    if (receiptStatus.present) {
      map['receipt_status'] = Variable<int>(receiptStatus.value);
    }
    if (receiptBody.present) {
      map['receipt_body'] = Variable<String>(receiptBody.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongAliasesCompanion(')
          ..write('sourceSongId: $sourceSongId, ')
          ..write('canonicalSongId: $canonicalSongId, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('mappingOpId: $mappingOpId, ')
          ..write('receiptStatus: $receiptStatus, ')
          ..write('receiptBody: $receiptBody, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class MutationSupersessions extends Table
    with TableInfo<MutationSupersessions, MutationSupersession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MutationSupersessions(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _originalOpIdMeta = const VerificationMeta(
    'originalOpId',
  );
  late final GeneratedColumn<String> originalOpId = GeneratedColumn<String>(
    'original_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _replacementOpIdMeta = const VerificationMeta(
    'replacementOpId',
  );
  late final GeneratedColumn<String> replacementOpId = GeneratedColumn<String>(
    'replacement_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _mappingSourceIdMeta = const VerificationMeta(
    'mappingSourceId',
  );
  late final GeneratedColumn<String> mappingSourceId = GeneratedColumn<String>(
    'mapping_source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES song_aliases(source_song_id)',
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
  static const VerificationMeta _orderRootOpIdMeta = const VerificationMeta(
    'orderRootOpId',
  );
  late final GeneratedColumn<String> orderRootOpId = GeneratedColumn<String>(
    'order_root_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _logicalOrderMeta = const VerificationMeta(
    'logicalOrder',
  );
  late final GeneratedColumn<int> logicalOrder = GeneratedColumn<int>(
    'logical_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (logical_order > 0)',
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
    originalOpId,
    replacementOpId,
    mappingSourceId,
    userId,
    orderRootOpId,
    logicalOrder,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mutation_supersessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<MutationSupersession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('original_op_id')) {
      context.handle(
        _originalOpIdMeta,
        originalOpId.isAcceptableOrUnknown(
          data['original_op_id']!,
          _originalOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalOpIdMeta);
    }
    if (data.containsKey('replacement_op_id')) {
      context.handle(
        _replacementOpIdMeta,
        replacementOpId.isAcceptableOrUnknown(
          data['replacement_op_id']!,
          _replacementOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_replacementOpIdMeta);
    }
    if (data.containsKey('mapping_source_id')) {
      context.handle(
        _mappingSourceIdMeta,
        mappingSourceId.isAcceptableOrUnknown(
          data['mapping_source_id']!,
          _mappingSourceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mappingSourceIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('order_root_op_id')) {
      context.handle(
        _orderRootOpIdMeta,
        orderRootOpId.isAcceptableOrUnknown(
          data['order_root_op_id']!,
          _orderRootOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_orderRootOpIdMeta);
    }
    if (data.containsKey('logical_order')) {
      context.handle(
        _logicalOrderMeta,
        logicalOrder.isAcceptableOrUnknown(
          data['logical_order']!,
          _logicalOrderMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_logicalOrderMeta);
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
  Set<GeneratedColumn> get $primaryKey => {originalOpId};
  @override
  MutationSupersession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MutationSupersession(
      originalOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_op_id'],
      )!,
      replacementOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replacement_op_id'],
      )!,
      mappingSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mapping_source_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      orderRootOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_root_op_id'],
      )!,
      logicalOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logical_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  MutationSupersessions createAlias(String alias) {
    return MutationSupersessions(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const [
    'CHECK(original_op_id <> replacement_op_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class MutationSupersession extends DataClass
    implements Insertable<MutationSupersession> {
  final String originalOpId;
  final String replacementOpId;
  final String mappingSourceId;
  final String userId;
  final String orderRootOpId;
  final int logicalOrder;
  final int createdAt;
  const MutationSupersession({
    required this.originalOpId,
    required this.replacementOpId,
    required this.mappingSourceId,
    required this.userId,
    required this.orderRootOpId,
    required this.logicalOrder,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['original_op_id'] = Variable<String>(originalOpId);
    map['replacement_op_id'] = Variable<String>(replacementOpId);
    map['mapping_source_id'] = Variable<String>(mappingSourceId);
    map['user_id'] = Variable<String>(userId);
    map['order_root_op_id'] = Variable<String>(orderRootOpId);
    map['logical_order'] = Variable<int>(logicalOrder);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  MutationSupersessionsCompanion toCompanion(bool nullToAbsent) {
    return MutationSupersessionsCompanion(
      originalOpId: Value(originalOpId),
      replacementOpId: Value(replacementOpId),
      mappingSourceId: Value(mappingSourceId),
      userId: Value(userId),
      orderRootOpId: Value(orderRootOpId),
      logicalOrder: Value(logicalOrder),
      createdAt: Value(createdAt),
    );
  }

  factory MutationSupersession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MutationSupersession(
      originalOpId: serializer.fromJson<String>(json['original_op_id']),
      replacementOpId: serializer.fromJson<String>(json['replacement_op_id']),
      mappingSourceId: serializer.fromJson<String>(json['mapping_source_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      orderRootOpId: serializer.fromJson<String>(json['order_root_op_id']),
      logicalOrder: serializer.fromJson<int>(json['logical_order']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'original_op_id': serializer.toJson<String>(originalOpId),
      'replacement_op_id': serializer.toJson<String>(replacementOpId),
      'mapping_source_id': serializer.toJson<String>(mappingSourceId),
      'user_id': serializer.toJson<String>(userId),
      'order_root_op_id': serializer.toJson<String>(orderRootOpId),
      'logical_order': serializer.toJson<int>(logicalOrder),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  MutationSupersession copyWith({
    String? originalOpId,
    String? replacementOpId,
    String? mappingSourceId,
    String? userId,
    String? orderRootOpId,
    int? logicalOrder,
    int? createdAt,
  }) => MutationSupersession(
    originalOpId: originalOpId ?? this.originalOpId,
    replacementOpId: replacementOpId ?? this.replacementOpId,
    mappingSourceId: mappingSourceId ?? this.mappingSourceId,
    userId: userId ?? this.userId,
    orderRootOpId: orderRootOpId ?? this.orderRootOpId,
    logicalOrder: logicalOrder ?? this.logicalOrder,
    createdAt: createdAt ?? this.createdAt,
  );
  MutationSupersession copyWithCompanion(MutationSupersessionsCompanion data) {
    return MutationSupersession(
      originalOpId: data.originalOpId.present
          ? data.originalOpId.value
          : this.originalOpId,
      replacementOpId: data.replacementOpId.present
          ? data.replacementOpId.value
          : this.replacementOpId,
      mappingSourceId: data.mappingSourceId.present
          ? data.mappingSourceId.value
          : this.mappingSourceId,
      userId: data.userId.present ? data.userId.value : this.userId,
      orderRootOpId: data.orderRootOpId.present
          ? data.orderRootOpId.value
          : this.orderRootOpId,
      logicalOrder: data.logicalOrder.present
          ? data.logicalOrder.value
          : this.logicalOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MutationSupersession(')
          ..write('originalOpId: $originalOpId, ')
          ..write('replacementOpId: $replacementOpId, ')
          ..write('mappingSourceId: $mappingSourceId, ')
          ..write('userId: $userId, ')
          ..write('orderRootOpId: $orderRootOpId, ')
          ..write('logicalOrder: $logicalOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    originalOpId,
    replacementOpId,
    mappingSourceId,
    userId,
    orderRootOpId,
    logicalOrder,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MutationSupersession &&
          other.originalOpId == this.originalOpId &&
          other.replacementOpId == this.replacementOpId &&
          other.mappingSourceId == this.mappingSourceId &&
          other.userId == this.userId &&
          other.orderRootOpId == this.orderRootOpId &&
          other.logicalOrder == this.logicalOrder &&
          other.createdAt == this.createdAt);
}

class MutationSupersessionsCompanion
    extends UpdateCompanion<MutationSupersession> {
  final Value<String> originalOpId;
  final Value<String> replacementOpId;
  final Value<String> mappingSourceId;
  final Value<String> userId;
  final Value<String> orderRootOpId;
  final Value<int> logicalOrder;
  final Value<int> createdAt;
  const MutationSupersessionsCompanion({
    this.originalOpId = const Value.absent(),
    this.replacementOpId = const Value.absent(),
    this.mappingSourceId = const Value.absent(),
    this.userId = const Value.absent(),
    this.orderRootOpId = const Value.absent(),
    this.logicalOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MutationSupersessionsCompanion.insert({
    required String originalOpId,
    required String replacementOpId,
    required String mappingSourceId,
    required String userId,
    required String orderRootOpId,
    required int logicalOrder,
    required int createdAt,
  }) : originalOpId = Value(originalOpId),
       replacementOpId = Value(replacementOpId),
       mappingSourceId = Value(mappingSourceId),
       userId = Value(userId),
       orderRootOpId = Value(orderRootOpId),
       logicalOrder = Value(logicalOrder),
       createdAt = Value(createdAt);
  static Insertable<MutationSupersession> custom({
    Expression<String>? originalOpId,
    Expression<String>? replacementOpId,
    Expression<String>? mappingSourceId,
    Expression<String>? userId,
    Expression<String>? orderRootOpId,
    Expression<int>? logicalOrder,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (originalOpId != null) 'original_op_id': originalOpId,
      if (replacementOpId != null) 'replacement_op_id': replacementOpId,
      if (mappingSourceId != null) 'mapping_source_id': mappingSourceId,
      if (userId != null) 'user_id': userId,
      if (orderRootOpId != null) 'order_root_op_id': orderRootOpId,
      if (logicalOrder != null) 'logical_order': logicalOrder,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MutationSupersessionsCompanion copyWith({
    Value<String>? originalOpId,
    Value<String>? replacementOpId,
    Value<String>? mappingSourceId,
    Value<String>? userId,
    Value<String>? orderRootOpId,
    Value<int>? logicalOrder,
    Value<int>? createdAt,
  }) {
    return MutationSupersessionsCompanion(
      originalOpId: originalOpId ?? this.originalOpId,
      replacementOpId: replacementOpId ?? this.replacementOpId,
      mappingSourceId: mappingSourceId ?? this.mappingSourceId,
      userId: userId ?? this.userId,
      orderRootOpId: orderRootOpId ?? this.orderRootOpId,
      logicalOrder: logicalOrder ?? this.logicalOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (originalOpId.present) {
      map['original_op_id'] = Variable<String>(originalOpId.value);
    }
    if (replacementOpId.present) {
      map['replacement_op_id'] = Variable<String>(replacementOpId.value);
    }
    if (mappingSourceId.present) {
      map['mapping_source_id'] = Variable<String>(mappingSourceId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (orderRootOpId.present) {
      map['order_root_op_id'] = Variable<String>(orderRootOpId.value);
    }
    if (logicalOrder.present) {
      map['logical_order'] = Variable<int>(logicalOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MutationSupersessionsCompanion(')
          ..write('originalOpId: $originalOpId, ')
          ..write('replacementOpId: $replacementOpId, ')
          ..write('mappingSourceId: $mappingSourceId, ')
          ..write('userId: $userId, ')
          ..write('orderRootOpId: $orderRootOpId, ')
          ..write('logicalOrder: $logicalOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class CanonicalEditIntents extends Table
    with TableInfo<CanonicalEditIntents, CanonicalEditIntent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  CanonicalEditIntents(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _intentIdMeta = const VerificationMeta(
    'intentId',
  );
  late final GeneratedColumn<String> intentId = GeneratedColumn<String>(
    'intent_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(intent_id) = 36)',
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
  static const VerificationMeta _mappingSourceIdMeta = const VerificationMeta(
    'mappingSourceId',
  );
  late final GeneratedColumn<String> mappingSourceId = GeneratedColumn<String>(
    'mapping_source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES song_aliases(source_song_id)',
  );
  static const VerificationMeta _intentKeyMeta = const VerificationMeta(
    'intentKey',
  );
  late final GeneratedColumn<String> intentKey = GeneratedColumn<String>(
    'intent_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (kind IN (\'SONG_VALUES\', \'SONG_MUTATION\', \'REFERENCE_RELINK\'))',
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
  static const VerificationMeta _originOpIdMeta = const VerificationMeta(
    'originOpId',
  );
  late final GeneratedColumn<String> originOpId = GeneratedColumn<String>(
    'origin_op_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _evidenceJsonMeta = const VerificationMeta(
    'evidenceJson',
  );
  late final GeneratedColumn<String> evidenceJson = GeneratedColumn<String>(
    'evidence_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(evidence_json) AND json_type(evidence_json) = \'object\')',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'OPEN\' CHECK (state IN (\'OPEN\', \'QUEUED\', \'RESOLVED\'))',
    defaultValue: const CustomExpression('\'OPEN\''),
  );
  static const VerificationMeta _resolutionJsonMeta = const VerificationMeta(
    'resolutionJson',
  );
  late final GeneratedColumn<String> resolutionJson = GeneratedColumn<String>(
    'resolution_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (resolution_json IS NULL OR(json_valid(resolution_json) AND json_type(resolution_json) = \'object\'))',
  );
  static const VerificationMeta _resolutionOpIdMeta = const VerificationMeta(
    'resolutionOpId',
  );
  late final GeneratedColumn<String> resolutionOpId = GeneratedColumn<String>(
    'resolution_op_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  late final GeneratedColumn<int> resolvedAt = GeneratedColumn<int>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
  @override
  List<GeneratedColumn> get $columns => [
    intentId,
    userId,
    mappingSourceId,
    intentKey,
    kind,
    entityType,
    entityId,
    originOpId,
    evidenceJson,
    state,
    resolutionJson,
    resolutionOpId,
    resolvedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'canonical_edit_intents';
  @override
  VerificationContext validateIntegrity(
    Insertable<CanonicalEditIntent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('intent_id')) {
      context.handle(
        _intentIdMeta,
        intentId.isAcceptableOrUnknown(data['intent_id']!, _intentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_intentIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('mapping_source_id')) {
      context.handle(
        _mappingSourceIdMeta,
        mappingSourceId.isAcceptableOrUnknown(
          data['mapping_source_id']!,
          _mappingSourceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mappingSourceIdMeta);
    }
    if (data.containsKey('intent_key')) {
      context.handle(
        _intentKeyMeta,
        intentKey.isAcceptableOrUnknown(data['intent_key']!, _intentKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_intentKeyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
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
    if (data.containsKey('origin_op_id')) {
      context.handle(
        _originOpIdMeta,
        originOpId.isAcceptableOrUnknown(
          data['origin_op_id']!,
          _originOpIdMeta,
        ),
      );
    }
    if (data.containsKey('evidence_json')) {
      context.handle(
        _evidenceJsonMeta,
        evidenceJson.isAcceptableOrUnknown(
          data['evidence_json']!,
          _evidenceJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_evidenceJsonMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('resolution_json')) {
      context.handle(
        _resolutionJsonMeta,
        resolutionJson.isAcceptableOrUnknown(
          data['resolution_json']!,
          _resolutionJsonMeta,
        ),
      );
    }
    if (data.containsKey('resolution_op_id')) {
      context.handle(
        _resolutionOpIdMeta,
        resolutionOpId.isAcceptableOrUnknown(
          data['resolution_op_id']!,
          _resolutionOpIdMeta,
        ),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {intentId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {mappingSourceId, intentKey},
  ];
  @override
  CanonicalEditIntent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CanonicalEditIntent(
      intentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intent_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      mappingSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mapping_source_id'],
      )!,
      intentKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intent_key'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      originOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_op_id'],
      ),
      evidenceJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_json'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      resolutionJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution_json'],
      ),
      resolutionOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution_op_id'],
      ),
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolved_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  CanonicalEditIntents createAlias(String alias) {
    return CanonicalEditIntents(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(entity_type, entity_id)REFERENCES metadata_copies(entity_type, entity_id)',
    'UNIQUE(mapping_source_id, intent_key)',
    'CHECK((state = \'OPEN\' AND resolution_json IS NULL AND resolution_op_id IS NULL AND resolved_at IS NULL)OR(state = \'QUEUED\' AND resolution_json IS NOT NULL AND resolution_op_id IS NOT NULL AND resolved_at IS NULL)OR(state = \'RESOLVED\' AND resolution_json IS NOT NULL AND resolved_at IS NOT NULL))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class CanonicalEditIntent extends DataClass
    implements Insertable<CanonicalEditIntent> {
  final String intentId;
  final String userId;
  final String mappingSourceId;
  final String intentKey;
  final String kind;
  final String entityType;
  final String entityId;
  final String? originOpId;
  final String evidenceJson;
  final String state;
  final String? resolutionJson;
  final String? resolutionOpId;
  final int? resolvedAt;
  final int createdAt;
  const CanonicalEditIntent({
    required this.intentId,
    required this.userId,
    required this.mappingSourceId,
    required this.intentKey,
    required this.kind,
    required this.entityType,
    required this.entityId,
    this.originOpId,
    required this.evidenceJson,
    required this.state,
    this.resolutionJson,
    this.resolutionOpId,
    this.resolvedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['intent_id'] = Variable<String>(intentId);
    map['user_id'] = Variable<String>(userId);
    map['mapping_source_id'] = Variable<String>(mappingSourceId);
    map['intent_key'] = Variable<String>(intentKey);
    map['kind'] = Variable<String>(kind);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    if (!nullToAbsent || originOpId != null) {
      map['origin_op_id'] = Variable<String>(originOpId);
    }
    map['evidence_json'] = Variable<String>(evidenceJson);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || resolutionJson != null) {
      map['resolution_json'] = Variable<String>(resolutionJson);
    }
    if (!nullToAbsent || resolutionOpId != null) {
      map['resolution_op_id'] = Variable<String>(resolutionOpId);
    }
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<int>(resolvedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  CanonicalEditIntentsCompanion toCompanion(bool nullToAbsent) {
    return CanonicalEditIntentsCompanion(
      intentId: Value(intentId),
      userId: Value(userId),
      mappingSourceId: Value(mappingSourceId),
      intentKey: Value(intentKey),
      kind: Value(kind),
      entityType: Value(entityType),
      entityId: Value(entityId),
      originOpId: originOpId == null && nullToAbsent
          ? const Value.absent()
          : Value(originOpId),
      evidenceJson: Value(evidenceJson),
      state: Value(state),
      resolutionJson: resolutionJson == null && nullToAbsent
          ? const Value.absent()
          : Value(resolutionJson),
      resolutionOpId: resolutionOpId == null && nullToAbsent
          ? const Value.absent()
          : Value(resolutionOpId),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      createdAt: Value(createdAt),
    );
  }

  factory CanonicalEditIntent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CanonicalEditIntent(
      intentId: serializer.fromJson<String>(json['intent_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      mappingSourceId: serializer.fromJson<String>(json['mapping_source_id']),
      intentKey: serializer.fromJson<String>(json['intent_key']),
      kind: serializer.fromJson<String>(json['kind']),
      entityType: serializer.fromJson<String>(json['entity_type']),
      entityId: serializer.fromJson<String>(json['entity_id']),
      originOpId: serializer.fromJson<String?>(json['origin_op_id']),
      evidenceJson: serializer.fromJson<String>(json['evidence_json']),
      state: serializer.fromJson<String>(json['state']),
      resolutionJson: serializer.fromJson<String?>(json['resolution_json']),
      resolutionOpId: serializer.fromJson<String?>(json['resolution_op_id']),
      resolvedAt: serializer.fromJson<int?>(json['resolved_at']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'intent_id': serializer.toJson<String>(intentId),
      'user_id': serializer.toJson<String>(userId),
      'mapping_source_id': serializer.toJson<String>(mappingSourceId),
      'intent_key': serializer.toJson<String>(intentKey),
      'kind': serializer.toJson<String>(kind),
      'entity_type': serializer.toJson<String>(entityType),
      'entity_id': serializer.toJson<String>(entityId),
      'origin_op_id': serializer.toJson<String?>(originOpId),
      'evidence_json': serializer.toJson<String>(evidenceJson),
      'state': serializer.toJson<String>(state),
      'resolution_json': serializer.toJson<String?>(resolutionJson),
      'resolution_op_id': serializer.toJson<String?>(resolutionOpId),
      'resolved_at': serializer.toJson<int?>(resolvedAt),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  CanonicalEditIntent copyWith({
    String? intentId,
    String? userId,
    String? mappingSourceId,
    String? intentKey,
    String? kind,
    String? entityType,
    String? entityId,
    Value<String?> originOpId = const Value.absent(),
    String? evidenceJson,
    String? state,
    Value<String?> resolutionJson = const Value.absent(),
    Value<String?> resolutionOpId = const Value.absent(),
    Value<int?> resolvedAt = const Value.absent(),
    int? createdAt,
  }) => CanonicalEditIntent(
    intentId: intentId ?? this.intentId,
    userId: userId ?? this.userId,
    mappingSourceId: mappingSourceId ?? this.mappingSourceId,
    intentKey: intentKey ?? this.intentKey,
    kind: kind ?? this.kind,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    originOpId: originOpId.present ? originOpId.value : this.originOpId,
    evidenceJson: evidenceJson ?? this.evidenceJson,
    state: state ?? this.state,
    resolutionJson: resolutionJson.present
        ? resolutionJson.value
        : this.resolutionJson,
    resolutionOpId: resolutionOpId.present
        ? resolutionOpId.value
        : this.resolutionOpId,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  CanonicalEditIntent copyWithCompanion(CanonicalEditIntentsCompanion data) {
    return CanonicalEditIntent(
      intentId: data.intentId.present ? data.intentId.value : this.intentId,
      userId: data.userId.present ? data.userId.value : this.userId,
      mappingSourceId: data.mappingSourceId.present
          ? data.mappingSourceId.value
          : this.mappingSourceId,
      intentKey: data.intentKey.present ? data.intentKey.value : this.intentKey,
      kind: data.kind.present ? data.kind.value : this.kind,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      originOpId: data.originOpId.present
          ? data.originOpId.value
          : this.originOpId,
      evidenceJson: data.evidenceJson.present
          ? data.evidenceJson.value
          : this.evidenceJson,
      state: data.state.present ? data.state.value : this.state,
      resolutionJson: data.resolutionJson.present
          ? data.resolutionJson.value
          : this.resolutionJson,
      resolutionOpId: data.resolutionOpId.present
          ? data.resolutionOpId.value
          : this.resolutionOpId,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CanonicalEditIntent(')
          ..write('intentId: $intentId, ')
          ..write('userId: $userId, ')
          ..write('mappingSourceId: $mappingSourceId, ')
          ..write('intentKey: $intentKey, ')
          ..write('kind: $kind, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('originOpId: $originOpId, ')
          ..write('evidenceJson: $evidenceJson, ')
          ..write('state: $state, ')
          ..write('resolutionJson: $resolutionJson, ')
          ..write('resolutionOpId: $resolutionOpId, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    intentId,
    userId,
    mappingSourceId,
    intentKey,
    kind,
    entityType,
    entityId,
    originOpId,
    evidenceJson,
    state,
    resolutionJson,
    resolutionOpId,
    resolvedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CanonicalEditIntent &&
          other.intentId == this.intentId &&
          other.userId == this.userId &&
          other.mappingSourceId == this.mappingSourceId &&
          other.intentKey == this.intentKey &&
          other.kind == this.kind &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.originOpId == this.originOpId &&
          other.evidenceJson == this.evidenceJson &&
          other.state == this.state &&
          other.resolutionJson == this.resolutionJson &&
          other.resolutionOpId == this.resolutionOpId &&
          other.resolvedAt == this.resolvedAt &&
          other.createdAt == this.createdAt);
}

class CanonicalEditIntentsCompanion
    extends UpdateCompanion<CanonicalEditIntent> {
  final Value<String> intentId;
  final Value<String> userId;
  final Value<String> mappingSourceId;
  final Value<String> intentKey;
  final Value<String> kind;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String?> originOpId;
  final Value<String> evidenceJson;
  final Value<String> state;
  final Value<String?> resolutionJson;
  final Value<String?> resolutionOpId;
  final Value<int?> resolvedAt;
  final Value<int> createdAt;
  const CanonicalEditIntentsCompanion({
    this.intentId = const Value.absent(),
    this.userId = const Value.absent(),
    this.mappingSourceId = const Value.absent(),
    this.intentKey = const Value.absent(),
    this.kind = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.originOpId = const Value.absent(),
    this.evidenceJson = const Value.absent(),
    this.state = const Value.absent(),
    this.resolutionJson = const Value.absent(),
    this.resolutionOpId = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CanonicalEditIntentsCompanion.insert({
    required String intentId,
    required String userId,
    required String mappingSourceId,
    required String intentKey,
    required String kind,
    required String entityType,
    required String entityId,
    this.originOpId = const Value.absent(),
    required String evidenceJson,
    this.state = const Value.absent(),
    this.resolutionJson = const Value.absent(),
    this.resolutionOpId = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    required int createdAt,
  }) : intentId = Value(intentId),
       userId = Value(userId),
       mappingSourceId = Value(mappingSourceId),
       intentKey = Value(intentKey),
       kind = Value(kind),
       entityType = Value(entityType),
       entityId = Value(entityId),
       evidenceJson = Value(evidenceJson),
       createdAt = Value(createdAt);
  static Insertable<CanonicalEditIntent> custom({
    Expression<String>? intentId,
    Expression<String>? userId,
    Expression<String>? mappingSourceId,
    Expression<String>? intentKey,
    Expression<String>? kind,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? originOpId,
    Expression<String>? evidenceJson,
    Expression<String>? state,
    Expression<String>? resolutionJson,
    Expression<String>? resolutionOpId,
    Expression<int>? resolvedAt,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (intentId != null) 'intent_id': intentId,
      if (userId != null) 'user_id': userId,
      if (mappingSourceId != null) 'mapping_source_id': mappingSourceId,
      if (intentKey != null) 'intent_key': intentKey,
      if (kind != null) 'kind': kind,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (originOpId != null) 'origin_op_id': originOpId,
      if (evidenceJson != null) 'evidence_json': evidenceJson,
      if (state != null) 'state': state,
      if (resolutionJson != null) 'resolution_json': resolutionJson,
      if (resolutionOpId != null) 'resolution_op_id': resolutionOpId,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CanonicalEditIntentsCompanion copyWith({
    Value<String>? intentId,
    Value<String>? userId,
    Value<String>? mappingSourceId,
    Value<String>? intentKey,
    Value<String>? kind,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String?>? originOpId,
    Value<String>? evidenceJson,
    Value<String>? state,
    Value<String?>? resolutionJson,
    Value<String?>? resolutionOpId,
    Value<int?>? resolvedAt,
    Value<int>? createdAt,
  }) {
    return CanonicalEditIntentsCompanion(
      intentId: intentId ?? this.intentId,
      userId: userId ?? this.userId,
      mappingSourceId: mappingSourceId ?? this.mappingSourceId,
      intentKey: intentKey ?? this.intentKey,
      kind: kind ?? this.kind,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      originOpId: originOpId ?? this.originOpId,
      evidenceJson: evidenceJson ?? this.evidenceJson,
      state: state ?? this.state,
      resolutionJson: resolutionJson ?? this.resolutionJson,
      resolutionOpId: resolutionOpId ?? this.resolutionOpId,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (intentId.present) {
      map['intent_id'] = Variable<String>(intentId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (mappingSourceId.present) {
      map['mapping_source_id'] = Variable<String>(mappingSourceId.value);
    }
    if (intentKey.present) {
      map['intent_key'] = Variable<String>(intentKey.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (originOpId.present) {
      map['origin_op_id'] = Variable<String>(originOpId.value);
    }
    if (evidenceJson.present) {
      map['evidence_json'] = Variable<String>(evidenceJson.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (resolutionJson.present) {
      map['resolution_json'] = Variable<String>(resolutionJson.value);
    }
    if (resolutionOpId.present) {
      map['resolution_op_id'] = Variable<String>(resolutionOpId.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<int>(resolvedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CanonicalEditIntentsCompanion(')
          ..write('intentId: $intentId, ')
          ..write('userId: $userId, ')
          ..write('mappingSourceId: $mappingSourceId, ')
          ..write('intentKey: $intentKey, ')
          ..write('kind: $kind, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('originOpId: $originOpId, ')
          ..write('evidenceJson: $evidenceJson, ')
          ..write('state: $state, ')
          ..write('resolutionJson: $resolutionJson, ')
          ..write('resolutionOpId: $resolutionOpId, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class MutationMappingHolds extends Table
    with TableInfo<MutationMappingHolds, MutationMappingHold> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MutationMappingHolds(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _opIdMeta = const VerificationMeta('opId');
  late final GeneratedColumn<String> opId = GeneratedColumn<String>(
    'op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _mappingSourceIdMeta = const VerificationMeta(
    'mappingSourceId',
  );
  late final GeneratedColumn<String> mappingSourceId = GeneratedColumn<String>(
    'mapping_source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES song_aliases(source_song_id)',
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
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(reason) BETWEEN 1 AND 64)',
  );
  static const VerificationMeta _dispositionMeta = const VerificationMeta(
    'disposition',
  );
  late final GeneratedColumn<String> disposition = GeneratedColumn<String>(
    'disposition',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (disposition IN (\'BLOCK\', \'REPLAY_ORIGINAL\'))',
  );
  static const VerificationMeta _intentIdMeta = const VerificationMeta(
    'intentId',
  );
  late final GeneratedColumn<String> intentId = GeneratedColumn<String>(
    'intent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'REFERENCES canonical_edit_intents(intent_id)',
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
  static const VerificationMeta _releasedAtMeta = const VerificationMeta(
    'releasedAt',
  );
  late final GeneratedColumn<int> releasedAt = GeneratedColumn<int>(
    'released_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _releaseEvidenceMeta = const VerificationMeta(
    'releaseEvidence',
  );
  late final GeneratedColumn<String> releaseEvidence = GeneratedColumn<String>(
    'release_evidence',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (release_evidence IS NULL OR(json_valid(release_evidence) AND json_type(release_evidence) = \'object\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    opId,
    mappingSourceId,
    userId,
    reason,
    disposition,
    intentId,
    createdAt,
    releasedAt,
    releaseEvidence,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mutation_mapping_holds';
  @override
  VerificationContext validateIntegrity(
    Insertable<MutationMappingHold> instance, {
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
    if (data.containsKey('mapping_source_id')) {
      context.handle(
        _mappingSourceIdMeta,
        mappingSourceId.isAcceptableOrUnknown(
          data['mapping_source_id']!,
          _mappingSourceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mappingSourceIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('disposition')) {
      context.handle(
        _dispositionMeta,
        disposition.isAcceptableOrUnknown(
          data['disposition']!,
          _dispositionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dispositionMeta);
    }
    if (data.containsKey('intent_id')) {
      context.handle(
        _intentIdMeta,
        intentId.isAcceptableOrUnknown(data['intent_id']!, _intentIdMeta),
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
    if (data.containsKey('released_at')) {
      context.handle(
        _releasedAtMeta,
        releasedAt.isAcceptableOrUnknown(data['released_at']!, _releasedAtMeta),
      );
    }
    if (data.containsKey('release_evidence')) {
      context.handle(
        _releaseEvidenceMeta,
        releaseEvidence.isAcceptableOrUnknown(
          data['release_evidence']!,
          _releaseEvidenceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {opId, mappingSourceId, reason};
  @override
  MutationMappingHold map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MutationMappingHold(
      opId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_id'],
      )!,
      mappingSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mapping_source_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      disposition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}disposition'],
      )!,
      intentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intent_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      releasedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}released_at'],
      ),
      releaseEvidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}release_evidence'],
      ),
    );
  }

  @override
  MutationMappingHolds createAlias(String alias) {
    return MutationMappingHolds(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(op_id, mapping_source_id, reason)',
    'CHECK((released_at IS NULL AND release_evidence IS NULL)OR(released_at IS NOT NULL AND release_evidence IS NOT NULL))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class MutationMappingHold extends DataClass
    implements Insertable<MutationMappingHold> {
  final String opId;
  final String mappingSourceId;
  final String userId;
  final String reason;
  final String disposition;
  final String? intentId;
  final int createdAt;
  final int? releasedAt;
  final String? releaseEvidence;
  const MutationMappingHold({
    required this.opId,
    required this.mappingSourceId,
    required this.userId,
    required this.reason,
    required this.disposition,
    this.intentId,
    required this.createdAt,
    this.releasedAt,
    this.releaseEvidence,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['op_id'] = Variable<String>(opId);
    map['mapping_source_id'] = Variable<String>(mappingSourceId);
    map['user_id'] = Variable<String>(userId);
    map['reason'] = Variable<String>(reason);
    map['disposition'] = Variable<String>(disposition);
    if (!nullToAbsent || intentId != null) {
      map['intent_id'] = Variable<String>(intentId);
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || releasedAt != null) {
      map['released_at'] = Variable<int>(releasedAt);
    }
    if (!nullToAbsent || releaseEvidence != null) {
      map['release_evidence'] = Variable<String>(releaseEvidence);
    }
    return map;
  }

  MutationMappingHoldsCompanion toCompanion(bool nullToAbsent) {
    return MutationMappingHoldsCompanion(
      opId: Value(opId),
      mappingSourceId: Value(mappingSourceId),
      userId: Value(userId),
      reason: Value(reason),
      disposition: Value(disposition),
      intentId: intentId == null && nullToAbsent
          ? const Value.absent()
          : Value(intentId),
      createdAt: Value(createdAt),
      releasedAt: releasedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(releasedAt),
      releaseEvidence: releaseEvidence == null && nullToAbsent
          ? const Value.absent()
          : Value(releaseEvidence),
    );
  }

  factory MutationMappingHold.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MutationMappingHold(
      opId: serializer.fromJson<String>(json['op_id']),
      mappingSourceId: serializer.fromJson<String>(json['mapping_source_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      reason: serializer.fromJson<String>(json['reason']),
      disposition: serializer.fromJson<String>(json['disposition']),
      intentId: serializer.fromJson<String?>(json['intent_id']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      releasedAt: serializer.fromJson<int?>(json['released_at']),
      releaseEvidence: serializer.fromJson<String?>(json['release_evidence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'op_id': serializer.toJson<String>(opId),
      'mapping_source_id': serializer.toJson<String>(mappingSourceId),
      'user_id': serializer.toJson<String>(userId),
      'reason': serializer.toJson<String>(reason),
      'disposition': serializer.toJson<String>(disposition),
      'intent_id': serializer.toJson<String?>(intentId),
      'created_at': serializer.toJson<int>(createdAt),
      'released_at': serializer.toJson<int?>(releasedAt),
      'release_evidence': serializer.toJson<String?>(releaseEvidence),
    };
  }

  MutationMappingHold copyWith({
    String? opId,
    String? mappingSourceId,
    String? userId,
    String? reason,
    String? disposition,
    Value<String?> intentId = const Value.absent(),
    int? createdAt,
    Value<int?> releasedAt = const Value.absent(),
    Value<String?> releaseEvidence = const Value.absent(),
  }) => MutationMappingHold(
    opId: opId ?? this.opId,
    mappingSourceId: mappingSourceId ?? this.mappingSourceId,
    userId: userId ?? this.userId,
    reason: reason ?? this.reason,
    disposition: disposition ?? this.disposition,
    intentId: intentId.present ? intentId.value : this.intentId,
    createdAt: createdAt ?? this.createdAt,
    releasedAt: releasedAt.present ? releasedAt.value : this.releasedAt,
    releaseEvidence: releaseEvidence.present
        ? releaseEvidence.value
        : this.releaseEvidence,
  );
  MutationMappingHold copyWithCompanion(MutationMappingHoldsCompanion data) {
    return MutationMappingHold(
      opId: data.opId.present ? data.opId.value : this.opId,
      mappingSourceId: data.mappingSourceId.present
          ? data.mappingSourceId.value
          : this.mappingSourceId,
      userId: data.userId.present ? data.userId.value : this.userId,
      reason: data.reason.present ? data.reason.value : this.reason,
      disposition: data.disposition.present
          ? data.disposition.value
          : this.disposition,
      intentId: data.intentId.present ? data.intentId.value : this.intentId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      releasedAt: data.releasedAt.present
          ? data.releasedAt.value
          : this.releasedAt,
      releaseEvidence: data.releaseEvidence.present
          ? data.releaseEvidence.value
          : this.releaseEvidence,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MutationMappingHold(')
          ..write('opId: $opId, ')
          ..write('mappingSourceId: $mappingSourceId, ')
          ..write('userId: $userId, ')
          ..write('reason: $reason, ')
          ..write('disposition: $disposition, ')
          ..write('intentId: $intentId, ')
          ..write('createdAt: $createdAt, ')
          ..write('releasedAt: $releasedAt, ')
          ..write('releaseEvidence: $releaseEvidence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    opId,
    mappingSourceId,
    userId,
    reason,
    disposition,
    intentId,
    createdAt,
    releasedAt,
    releaseEvidence,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MutationMappingHold &&
          other.opId == this.opId &&
          other.mappingSourceId == this.mappingSourceId &&
          other.userId == this.userId &&
          other.reason == this.reason &&
          other.disposition == this.disposition &&
          other.intentId == this.intentId &&
          other.createdAt == this.createdAt &&
          other.releasedAt == this.releasedAt &&
          other.releaseEvidence == this.releaseEvidence);
}

class MutationMappingHoldsCompanion
    extends UpdateCompanion<MutationMappingHold> {
  final Value<String> opId;
  final Value<String> mappingSourceId;
  final Value<String> userId;
  final Value<String> reason;
  final Value<String> disposition;
  final Value<String?> intentId;
  final Value<int> createdAt;
  final Value<int?> releasedAt;
  final Value<String?> releaseEvidence;
  const MutationMappingHoldsCompanion({
    this.opId = const Value.absent(),
    this.mappingSourceId = const Value.absent(),
    this.userId = const Value.absent(),
    this.reason = const Value.absent(),
    this.disposition = const Value.absent(),
    this.intentId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.releasedAt = const Value.absent(),
    this.releaseEvidence = const Value.absent(),
  });
  MutationMappingHoldsCompanion.insert({
    required String opId,
    required String mappingSourceId,
    required String userId,
    required String reason,
    required String disposition,
    this.intentId = const Value.absent(),
    required int createdAt,
    this.releasedAt = const Value.absent(),
    this.releaseEvidence = const Value.absent(),
  }) : opId = Value(opId),
       mappingSourceId = Value(mappingSourceId),
       userId = Value(userId),
       reason = Value(reason),
       disposition = Value(disposition),
       createdAt = Value(createdAt);
  static Insertable<MutationMappingHold> custom({
    Expression<String>? opId,
    Expression<String>? mappingSourceId,
    Expression<String>? userId,
    Expression<String>? reason,
    Expression<String>? disposition,
    Expression<String>? intentId,
    Expression<int>? createdAt,
    Expression<int>? releasedAt,
    Expression<String>? releaseEvidence,
  }) {
    return RawValuesInsertable({
      if (opId != null) 'op_id': opId,
      if (mappingSourceId != null) 'mapping_source_id': mappingSourceId,
      if (userId != null) 'user_id': userId,
      if (reason != null) 'reason': reason,
      if (disposition != null) 'disposition': disposition,
      if (intentId != null) 'intent_id': intentId,
      if (createdAt != null) 'created_at': createdAt,
      if (releasedAt != null) 'released_at': releasedAt,
      if (releaseEvidence != null) 'release_evidence': releaseEvidence,
    });
  }

  MutationMappingHoldsCompanion copyWith({
    Value<String>? opId,
    Value<String>? mappingSourceId,
    Value<String>? userId,
    Value<String>? reason,
    Value<String>? disposition,
    Value<String?>? intentId,
    Value<int>? createdAt,
    Value<int?>? releasedAt,
    Value<String?>? releaseEvidence,
  }) {
    return MutationMappingHoldsCompanion(
      opId: opId ?? this.opId,
      mappingSourceId: mappingSourceId ?? this.mappingSourceId,
      userId: userId ?? this.userId,
      reason: reason ?? this.reason,
      disposition: disposition ?? this.disposition,
      intentId: intentId ?? this.intentId,
      createdAt: createdAt ?? this.createdAt,
      releasedAt: releasedAt ?? this.releasedAt,
      releaseEvidence: releaseEvidence ?? this.releaseEvidence,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (opId.present) {
      map['op_id'] = Variable<String>(opId.value);
    }
    if (mappingSourceId.present) {
      map['mapping_source_id'] = Variable<String>(mappingSourceId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (disposition.present) {
      map['disposition'] = Variable<String>(disposition.value);
    }
    if (intentId.present) {
      map['intent_id'] = Variable<String>(intentId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (releasedAt.present) {
      map['released_at'] = Variable<int>(releasedAt.value);
    }
    if (releaseEvidence.present) {
      map['release_evidence'] = Variable<String>(releaseEvidence.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MutationMappingHoldsCompanion(')
          ..write('opId: $opId, ')
          ..write('mappingSourceId: $mappingSourceId, ')
          ..write('userId: $userId, ')
          ..write('reason: $reason, ')
          ..write('disposition: $disposition, ')
          ..write('intentId: $intentId, ')
          ..write('createdAt: $createdAt, ')
          ..write('releasedAt: $releasedAt, ')
          ..write('releaseEvidence: $releaseEvidence')
          ..write(')'))
        .toString();
  }
}

class SnapshotDownloads extends Table
    with TableInfo<SnapshotDownloads, SnapshotDownload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SnapshotDownloads(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _snapshotTokenMeta = const VerificationMeta(
    'snapshotToken',
  );
  late final GeneratedColumn<String> snapshotToken = GeneratedColumn<String>(
    'snapshot_token',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY CHECK (length(snapshot_token) = 36)',
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
  static const VerificationMeta _manifestJsonMeta = const VerificationMeta(
    'manifestJson',
  );
  late final GeneratedColumn<String> manifestJson = GeneratedColumn<String>(
    'manifest_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(manifest_json) AND json_type(manifest_json) = \'object\')',
  );
  static const VerificationMeta _snapshotCursorMeta = const VerificationMeta(
    'snapshotCursor',
  );
  late final GeneratedColumn<int> snapshotCursor = GeneratedColumn<int>(
    'snapshot_cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (snapshot_cursor >= 0)',
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'RECEIVING\' CHECK (state IN (\'RECEIVING\', \'VERIFIED\', \'APPLIED\'))',
    defaultValue: const CustomExpression('\'RECEIVING\''),
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
    snapshotToken,
    userId,
    manifestJson,
    snapshotCursor,
    expiresAt,
    state,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snapshot_downloads';
  @override
  VerificationContext validateIntegrity(
    Insertable<SnapshotDownload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('snapshot_token')) {
      context.handle(
        _snapshotTokenMeta,
        snapshotToken.isAcceptableOrUnknown(
          data['snapshot_token']!,
          _snapshotTokenMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotTokenMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('manifest_json')) {
      context.handle(
        _manifestJsonMeta,
        manifestJson.isAcceptableOrUnknown(
          data['manifest_json']!,
          _manifestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manifestJsonMeta);
    }
    if (data.containsKey('snapshot_cursor')) {
      context.handle(
        _snapshotCursorMeta,
        snapshotCursor.isAcceptableOrUnknown(
          data['snapshot_cursor']!,
          _snapshotCursorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotCursorMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {snapshotToken};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {snapshotToken, userId},
  ];
  @override
  SnapshotDownload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnapshotDownload(
      snapshotToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_token'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      manifestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifest_json'],
      )!,
      snapshotCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snapshot_cursor'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  SnapshotDownloads createAlias(String alias) {
    return SnapshotDownloads(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE(snapshot_token, user_id)',
    'CHECK(json_extract(manifest_json, \'\$.snapshot_token\') IS snapshot_token)',
    'CHECK(json_extract(manifest_json, \'\$.snapshot_cursor\') IS snapshot_cursor)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class SnapshotDownload extends DataClass
    implements Insertable<SnapshotDownload> {
  final String snapshotToken;
  final String userId;
  final String manifestJson;
  final int snapshotCursor;
  final int expiresAt;
  final String state;
  final int createdAt;
  const SnapshotDownload({
    required this.snapshotToken,
    required this.userId,
    required this.manifestJson,
    required this.snapshotCursor,
    required this.expiresAt,
    required this.state,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['snapshot_token'] = Variable<String>(snapshotToken);
    map['user_id'] = Variable<String>(userId);
    map['manifest_json'] = Variable<String>(manifestJson);
    map['snapshot_cursor'] = Variable<int>(snapshotCursor);
    map['expires_at'] = Variable<int>(expiresAt);
    map['state'] = Variable<String>(state);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  SnapshotDownloadsCompanion toCompanion(bool nullToAbsent) {
    return SnapshotDownloadsCompanion(
      snapshotToken: Value(snapshotToken),
      userId: Value(userId),
      manifestJson: Value(manifestJson),
      snapshotCursor: Value(snapshotCursor),
      expiresAt: Value(expiresAt),
      state: Value(state),
      createdAt: Value(createdAt),
    );
  }

  factory SnapshotDownload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnapshotDownload(
      snapshotToken: serializer.fromJson<String>(json['snapshot_token']),
      userId: serializer.fromJson<String>(json['user_id']),
      manifestJson: serializer.fromJson<String>(json['manifest_json']),
      snapshotCursor: serializer.fromJson<int>(json['snapshot_cursor']),
      expiresAt: serializer.fromJson<int>(json['expires_at']),
      state: serializer.fromJson<String>(json['state']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'snapshot_token': serializer.toJson<String>(snapshotToken),
      'user_id': serializer.toJson<String>(userId),
      'manifest_json': serializer.toJson<String>(manifestJson),
      'snapshot_cursor': serializer.toJson<int>(snapshotCursor),
      'expires_at': serializer.toJson<int>(expiresAt),
      'state': serializer.toJson<String>(state),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  SnapshotDownload copyWith({
    String? snapshotToken,
    String? userId,
    String? manifestJson,
    int? snapshotCursor,
    int? expiresAt,
    String? state,
    int? createdAt,
  }) => SnapshotDownload(
    snapshotToken: snapshotToken ?? this.snapshotToken,
    userId: userId ?? this.userId,
    manifestJson: manifestJson ?? this.manifestJson,
    snapshotCursor: snapshotCursor ?? this.snapshotCursor,
    expiresAt: expiresAt ?? this.expiresAt,
    state: state ?? this.state,
    createdAt: createdAt ?? this.createdAt,
  );
  SnapshotDownload copyWithCompanion(SnapshotDownloadsCompanion data) {
    return SnapshotDownload(
      snapshotToken: data.snapshotToken.present
          ? data.snapshotToken.value
          : this.snapshotToken,
      userId: data.userId.present ? data.userId.value : this.userId,
      manifestJson: data.manifestJson.present
          ? data.manifestJson.value
          : this.manifestJson,
      snapshotCursor: data.snapshotCursor.present
          ? data.snapshotCursor.value
          : this.snapshotCursor,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      state: data.state.present ? data.state.value : this.state,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotDownload(')
          ..write('snapshotToken: $snapshotToken, ')
          ..write('userId: $userId, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('snapshotCursor: $snapshotCursor, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    snapshotToken,
    userId,
    manifestJson,
    snapshotCursor,
    expiresAt,
    state,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnapshotDownload &&
          other.snapshotToken == this.snapshotToken &&
          other.userId == this.userId &&
          other.manifestJson == this.manifestJson &&
          other.snapshotCursor == this.snapshotCursor &&
          other.expiresAt == this.expiresAt &&
          other.state == this.state &&
          other.createdAt == this.createdAt);
}

class SnapshotDownloadsCompanion extends UpdateCompanion<SnapshotDownload> {
  final Value<String> snapshotToken;
  final Value<String> userId;
  final Value<String> manifestJson;
  final Value<int> snapshotCursor;
  final Value<int> expiresAt;
  final Value<String> state;
  final Value<int> createdAt;
  final Value<int> rowid;
  const SnapshotDownloadsCompanion({
    this.snapshotToken = const Value.absent(),
    this.userId = const Value.absent(),
    this.manifestJson = const Value.absent(),
    this.snapshotCursor = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnapshotDownloadsCompanion.insert({
    required String snapshotToken,
    required String userId,
    required String manifestJson,
    required int snapshotCursor,
    required int expiresAt,
    this.state = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : snapshotToken = Value(snapshotToken),
       userId = Value(userId),
       manifestJson = Value(manifestJson),
       snapshotCursor = Value(snapshotCursor),
       expiresAt = Value(expiresAt),
       createdAt = Value(createdAt);
  static Insertable<SnapshotDownload> custom({
    Expression<String>? snapshotToken,
    Expression<String>? userId,
    Expression<String>? manifestJson,
    Expression<int>? snapshotCursor,
    Expression<int>? expiresAt,
    Expression<String>? state,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (snapshotToken != null) 'snapshot_token': snapshotToken,
      if (userId != null) 'user_id': userId,
      if (manifestJson != null) 'manifest_json': manifestJson,
      if (snapshotCursor != null) 'snapshot_cursor': snapshotCursor,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (state != null) 'state': state,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnapshotDownloadsCompanion copyWith({
    Value<String>? snapshotToken,
    Value<String>? userId,
    Value<String>? manifestJson,
    Value<int>? snapshotCursor,
    Value<int>? expiresAt,
    Value<String>? state,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return SnapshotDownloadsCompanion(
      snapshotToken: snapshotToken ?? this.snapshotToken,
      userId: userId ?? this.userId,
      manifestJson: manifestJson ?? this.manifestJson,
      snapshotCursor: snapshotCursor ?? this.snapshotCursor,
      expiresAt: expiresAt ?? this.expiresAt,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (snapshotToken.present) {
      map['snapshot_token'] = Variable<String>(snapshotToken.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (manifestJson.present) {
      map['manifest_json'] = Variable<String>(manifestJson.value);
    }
    if (snapshotCursor.present) {
      map['snapshot_cursor'] = Variable<int>(snapshotCursor.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotDownloadsCompanion(')
          ..write('snapshotToken: $snapshotToken, ')
          ..write('userId: $userId, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('snapshotCursor: $snapshotCursor, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class SnapshotDownloadRows extends Table
    with TableInfo<SnapshotDownloadRows, SnapshotDownloadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SnapshotDownloadRows(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _snapshotTokenMeta = const VerificationMeta(
    'snapshotToken',
  );
  late final GeneratedColumn<String> snapshotToken = GeneratedColumn<String>(
    'snapshot_token',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
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
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (entity IN (\'SONG\', \'SONG_SOURCE\', \'RECORDING\', \'RECORDING_FILE_SPEC\', \'RECORDING_ASSET\', \'PLAYLIST\', \'PLAYLIST_ITEM\', \'TAG\', \'RECORDING_TAG\', \'RECORDING_CONDITION\', \'USER_ENTITLEMENT\', \'STORAGE_USAGE\', \'SONG_CLOUD_SELECTION\', \'PIN_SLOT\', \'USER_SYNC_STATE\', \'CHANGE_LOG\', \'DELETION_BATCH\', \'DELETION_ITEM\', \'DELETION_LEDGER\'))',
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
  static const VerificationMeta _canonicalPayloadMeta = const VerificationMeta(
    'canonicalPayload',
  );
  late final GeneratedColumn<String> canonicalPayload = GeneratedColumn<String>(
    'canonical_payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(canonical_payload) AND json_type(canonical_payload) = \'object\')',
  );
  @override
  List<GeneratedColumn> get $columns => [
    snapshotToken,
    userId,
    entity,
    ordinal,
    resourceId,
    canonicalPayload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snapshot_download_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SnapshotDownloadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('snapshot_token')) {
      context.handle(
        _snapshotTokenMeta,
        snapshotToken.isAcceptableOrUnknown(
          data['snapshot_token']!,
          _snapshotTokenMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotTokenMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
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
    if (data.containsKey('canonical_payload')) {
      context.handle(
        _canonicalPayloadMeta,
        canonicalPayload.isAcceptableOrUnknown(
          data['canonical_payload']!,
          _canonicalPayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalPayloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {snapshotToken, entity, ordinal};
  @override
  SnapshotDownloadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnapshotDownloadRow(
      snapshotToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_token'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      resourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource_id'],
      )!,
      canonicalPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_payload'],
      )!,
    );
  }

  @override
  SnapshotDownloadRows createAlias(String alias) {
    return SnapshotDownloadRows(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(snapshot_token, entity, ordinal)',
    'FOREIGN KEY(snapshot_token, user_id)REFERENCES snapshot_downloads(snapshot_token, user_id)ON DELETE CASCADE',
    'CHECK(json_extract(canonical_payload, \'\$.user_id\') IS user_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class SnapshotDownloadRow extends DataClass
    implements Insertable<SnapshotDownloadRow> {
  final String snapshotToken;
  final String userId;
  final String entity;
  final int ordinal;
  final String resourceId;
  final String canonicalPayload;
  const SnapshotDownloadRow({
    required this.snapshotToken,
    required this.userId,
    required this.entity,
    required this.ordinal,
    required this.resourceId,
    required this.canonicalPayload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['snapshot_token'] = Variable<String>(snapshotToken);
    map['user_id'] = Variable<String>(userId);
    map['entity'] = Variable<String>(entity);
    map['ordinal'] = Variable<int>(ordinal);
    map['resource_id'] = Variable<String>(resourceId);
    map['canonical_payload'] = Variable<String>(canonicalPayload);
    return map;
  }

  SnapshotDownloadRowsCompanion toCompanion(bool nullToAbsent) {
    return SnapshotDownloadRowsCompanion(
      snapshotToken: Value(snapshotToken),
      userId: Value(userId),
      entity: Value(entity),
      ordinal: Value(ordinal),
      resourceId: Value(resourceId),
      canonicalPayload: Value(canonicalPayload),
    );
  }

  factory SnapshotDownloadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnapshotDownloadRow(
      snapshotToken: serializer.fromJson<String>(json['snapshot_token']),
      userId: serializer.fromJson<String>(json['user_id']),
      entity: serializer.fromJson<String>(json['entity']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      resourceId: serializer.fromJson<String>(json['resource_id']),
      canonicalPayload: serializer.fromJson<String>(json['canonical_payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'snapshot_token': serializer.toJson<String>(snapshotToken),
      'user_id': serializer.toJson<String>(userId),
      'entity': serializer.toJson<String>(entity),
      'ordinal': serializer.toJson<int>(ordinal),
      'resource_id': serializer.toJson<String>(resourceId),
      'canonical_payload': serializer.toJson<String>(canonicalPayload),
    };
  }

  SnapshotDownloadRow copyWith({
    String? snapshotToken,
    String? userId,
    String? entity,
    int? ordinal,
    String? resourceId,
    String? canonicalPayload,
  }) => SnapshotDownloadRow(
    snapshotToken: snapshotToken ?? this.snapshotToken,
    userId: userId ?? this.userId,
    entity: entity ?? this.entity,
    ordinal: ordinal ?? this.ordinal,
    resourceId: resourceId ?? this.resourceId,
    canonicalPayload: canonicalPayload ?? this.canonicalPayload,
  );
  SnapshotDownloadRow copyWithCompanion(SnapshotDownloadRowsCompanion data) {
    return SnapshotDownloadRow(
      snapshotToken: data.snapshotToken.present
          ? data.snapshotToken.value
          : this.snapshotToken,
      userId: data.userId.present ? data.userId.value : this.userId,
      entity: data.entity.present ? data.entity.value : this.entity,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      resourceId: data.resourceId.present
          ? data.resourceId.value
          : this.resourceId,
      canonicalPayload: data.canonicalPayload.present
          ? data.canonicalPayload.value
          : this.canonicalPayload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotDownloadRow(')
          ..write('snapshotToken: $snapshotToken, ')
          ..write('userId: $userId, ')
          ..write('entity: $entity, ')
          ..write('ordinal: $ordinal, ')
          ..write('resourceId: $resourceId, ')
          ..write('canonicalPayload: $canonicalPayload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    snapshotToken,
    userId,
    entity,
    ordinal,
    resourceId,
    canonicalPayload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnapshotDownloadRow &&
          other.snapshotToken == this.snapshotToken &&
          other.userId == this.userId &&
          other.entity == this.entity &&
          other.ordinal == this.ordinal &&
          other.resourceId == this.resourceId &&
          other.canonicalPayload == this.canonicalPayload);
}

class SnapshotDownloadRowsCompanion
    extends UpdateCompanion<SnapshotDownloadRow> {
  final Value<String> snapshotToken;
  final Value<String> userId;
  final Value<String> entity;
  final Value<int> ordinal;
  final Value<String> resourceId;
  final Value<String> canonicalPayload;
  final Value<int> rowid;
  const SnapshotDownloadRowsCompanion({
    this.snapshotToken = const Value.absent(),
    this.userId = const Value.absent(),
    this.entity = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.resourceId = const Value.absent(),
    this.canonicalPayload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnapshotDownloadRowsCompanion.insert({
    required String snapshotToken,
    required String userId,
    required String entity,
    required int ordinal,
    required String resourceId,
    required String canonicalPayload,
    this.rowid = const Value.absent(),
  }) : snapshotToken = Value(snapshotToken),
       userId = Value(userId),
       entity = Value(entity),
       ordinal = Value(ordinal),
       resourceId = Value(resourceId),
       canonicalPayload = Value(canonicalPayload);
  static Insertable<SnapshotDownloadRow> custom({
    Expression<String>? snapshotToken,
    Expression<String>? userId,
    Expression<String>? entity,
    Expression<int>? ordinal,
    Expression<String>? resourceId,
    Expression<String>? canonicalPayload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (snapshotToken != null) 'snapshot_token': snapshotToken,
      if (userId != null) 'user_id': userId,
      if (entity != null) 'entity': entity,
      if (ordinal != null) 'ordinal': ordinal,
      if (resourceId != null) 'resource_id': resourceId,
      if (canonicalPayload != null) 'canonical_payload': canonicalPayload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnapshotDownloadRowsCompanion copyWith({
    Value<String>? snapshotToken,
    Value<String>? userId,
    Value<String>? entity,
    Value<int>? ordinal,
    Value<String>? resourceId,
    Value<String>? canonicalPayload,
    Value<int>? rowid,
  }) {
    return SnapshotDownloadRowsCompanion(
      snapshotToken: snapshotToken ?? this.snapshotToken,
      userId: userId ?? this.userId,
      entity: entity ?? this.entity,
      ordinal: ordinal ?? this.ordinal,
      resourceId: resourceId ?? this.resourceId,
      canonicalPayload: canonicalPayload ?? this.canonicalPayload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (snapshotToken.present) {
      map['snapshot_token'] = Variable<String>(snapshotToken.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (resourceId.present) {
      map['resource_id'] = Variable<String>(resourceId.value);
    }
    if (canonicalPayload.present) {
      map['canonical_payload'] = Variable<String>(canonicalPayload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotDownloadRowsCompanion(')
          ..write('snapshotToken: $snapshotToken, ')
          ..write('userId: $userId, ')
          ..write('entity: $entity, ')
          ..write('ordinal: $ordinal, ')
          ..write('resourceId: $resourceId, ')
          ..write('canonicalPayload: $canonicalPayload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class SnapshotDownloadProgress extends Table
    with TableInfo<SnapshotDownloadProgress, SnapshotDownloadProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SnapshotDownloadProgress(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _snapshotTokenMeta = const VerificationMeta(
    'snapshotToken',
  );
  late final GeneratedColumn<String> snapshotToken = GeneratedColumn<String>(
    'snapshot_token',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES snapshot_downloads(snapshot_token)ON DELETE CASCADE',
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (entity IN (\'SONG\', \'SONG_SOURCE\', \'RECORDING\', \'RECORDING_FILE_SPEC\', \'RECORDING_ASSET\', \'PLAYLIST\', \'PLAYLIST_ITEM\', \'TAG\', \'RECORDING_TAG\', \'RECORDING_CONDITION\', \'USER_ENTITLEMENT\', \'STORAGE_USAGE\', \'SONG_CLOUD_SELECTION\', \'PIN_SLOT\', \'USER_SYNC_STATE\', \'CHANGE_LOG\', \'DELETION_BATCH\', \'DELETION_ITEM\', \'DELETION_LEDGER\'))',
  );
  static const VerificationMeta _lastOrdinalMeta = const VerificationMeta(
    'lastOrdinal',
  );
  late final GeneratedColumn<int> lastOrdinal = GeneratedColumn<int>(
    'last_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (last_ordinal >= 0)',
  );
  static const VerificationMeta _nextCursorMeta = const VerificationMeta(
    'nextCursor',
  );
  late final GeneratedColumn<String> nextCursor = GeneratedColumn<String>(
    'next_cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _finishedMeta = const VerificationMeta(
    'finished',
  );
  late final GeneratedColumn<int> finished = GeneratedColumn<int>(
    'finished',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (finished IN (0, 1))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    snapshotToken,
    entity,
    lastOrdinal,
    nextCursor,
    finished,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snapshot_download_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<SnapshotDownloadProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('snapshot_token')) {
      context.handle(
        _snapshotTokenMeta,
        snapshotToken.isAcceptableOrUnknown(
          data['snapshot_token']!,
          _snapshotTokenMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotTokenMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('last_ordinal')) {
      context.handle(
        _lastOrdinalMeta,
        lastOrdinal.isAcceptableOrUnknown(
          data['last_ordinal']!,
          _lastOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastOrdinalMeta);
    }
    if (data.containsKey('next_cursor')) {
      context.handle(
        _nextCursorMeta,
        nextCursor.isAcceptableOrUnknown(data['next_cursor']!, _nextCursorMeta),
      );
    }
    if (data.containsKey('finished')) {
      context.handle(
        _finishedMeta,
        finished.isAcceptableOrUnknown(data['finished']!, _finishedMeta),
      );
    } else if (isInserting) {
      context.missing(_finishedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {snapshotToken, entity};
  @override
  SnapshotDownloadProgressData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnapshotDownloadProgressData(
      snapshotToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_token'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      lastOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_ordinal'],
      )!,
      nextCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_cursor'],
      ),
      finished: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}finished'],
      )!,
    );
  }

  @override
  SnapshotDownloadProgress createAlias(String alias) {
    return SnapshotDownloadProgress(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(snapshot_token, entity)',
    'CHECK((finished = 1 AND next_cursor IS NULL)OR(finished = 0 AND next_cursor IS NOT NULL AND next_cursor LIKE \'sp1.%\' AND last_ordinal > 0))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class SnapshotDownloadProgressData extends DataClass
    implements Insertable<SnapshotDownloadProgressData> {
  final String snapshotToken;
  final String entity;
  final int lastOrdinal;
  final String? nextCursor;
  final int finished;
  const SnapshotDownloadProgressData({
    required this.snapshotToken,
    required this.entity,
    required this.lastOrdinal,
    this.nextCursor,
    required this.finished,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['snapshot_token'] = Variable<String>(snapshotToken);
    map['entity'] = Variable<String>(entity);
    map['last_ordinal'] = Variable<int>(lastOrdinal);
    if (!nullToAbsent || nextCursor != null) {
      map['next_cursor'] = Variable<String>(nextCursor);
    }
    map['finished'] = Variable<int>(finished);
    return map;
  }

  SnapshotDownloadProgressCompanion toCompanion(bool nullToAbsent) {
    return SnapshotDownloadProgressCompanion(
      snapshotToken: Value(snapshotToken),
      entity: Value(entity),
      lastOrdinal: Value(lastOrdinal),
      nextCursor: nextCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(nextCursor),
      finished: Value(finished),
    );
  }

  factory SnapshotDownloadProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnapshotDownloadProgressData(
      snapshotToken: serializer.fromJson<String>(json['snapshot_token']),
      entity: serializer.fromJson<String>(json['entity']),
      lastOrdinal: serializer.fromJson<int>(json['last_ordinal']),
      nextCursor: serializer.fromJson<String?>(json['next_cursor']),
      finished: serializer.fromJson<int>(json['finished']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'snapshot_token': serializer.toJson<String>(snapshotToken),
      'entity': serializer.toJson<String>(entity),
      'last_ordinal': serializer.toJson<int>(lastOrdinal),
      'next_cursor': serializer.toJson<String?>(nextCursor),
      'finished': serializer.toJson<int>(finished),
    };
  }

  SnapshotDownloadProgressData copyWith({
    String? snapshotToken,
    String? entity,
    int? lastOrdinal,
    Value<String?> nextCursor = const Value.absent(),
    int? finished,
  }) => SnapshotDownloadProgressData(
    snapshotToken: snapshotToken ?? this.snapshotToken,
    entity: entity ?? this.entity,
    lastOrdinal: lastOrdinal ?? this.lastOrdinal,
    nextCursor: nextCursor.present ? nextCursor.value : this.nextCursor,
    finished: finished ?? this.finished,
  );
  SnapshotDownloadProgressData copyWithCompanion(
    SnapshotDownloadProgressCompanion data,
  ) {
    return SnapshotDownloadProgressData(
      snapshotToken: data.snapshotToken.present
          ? data.snapshotToken.value
          : this.snapshotToken,
      entity: data.entity.present ? data.entity.value : this.entity,
      lastOrdinal: data.lastOrdinal.present
          ? data.lastOrdinal.value
          : this.lastOrdinal,
      nextCursor: data.nextCursor.present
          ? data.nextCursor.value
          : this.nextCursor,
      finished: data.finished.present ? data.finished.value : this.finished,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotDownloadProgressData(')
          ..write('snapshotToken: $snapshotToken, ')
          ..write('entity: $entity, ')
          ..write('lastOrdinal: $lastOrdinal, ')
          ..write('nextCursor: $nextCursor, ')
          ..write('finished: $finished')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(snapshotToken, entity, lastOrdinal, nextCursor, finished);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnapshotDownloadProgressData &&
          other.snapshotToken == this.snapshotToken &&
          other.entity == this.entity &&
          other.lastOrdinal == this.lastOrdinal &&
          other.nextCursor == this.nextCursor &&
          other.finished == this.finished);
}

class SnapshotDownloadProgressCompanion
    extends UpdateCompanion<SnapshotDownloadProgressData> {
  final Value<String> snapshotToken;
  final Value<String> entity;
  final Value<int> lastOrdinal;
  final Value<String?> nextCursor;
  final Value<int> finished;
  final Value<int> rowid;
  const SnapshotDownloadProgressCompanion({
    this.snapshotToken = const Value.absent(),
    this.entity = const Value.absent(),
    this.lastOrdinal = const Value.absent(),
    this.nextCursor = const Value.absent(),
    this.finished = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnapshotDownloadProgressCompanion.insert({
    required String snapshotToken,
    required String entity,
    required int lastOrdinal,
    this.nextCursor = const Value.absent(),
    required int finished,
    this.rowid = const Value.absent(),
  }) : snapshotToken = Value(snapshotToken),
       entity = Value(entity),
       lastOrdinal = Value(lastOrdinal),
       finished = Value(finished);
  static Insertable<SnapshotDownloadProgressData> custom({
    Expression<String>? snapshotToken,
    Expression<String>? entity,
    Expression<int>? lastOrdinal,
    Expression<String>? nextCursor,
    Expression<int>? finished,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (snapshotToken != null) 'snapshot_token': snapshotToken,
      if (entity != null) 'entity': entity,
      if (lastOrdinal != null) 'last_ordinal': lastOrdinal,
      if (nextCursor != null) 'next_cursor': nextCursor,
      if (finished != null) 'finished': finished,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnapshotDownloadProgressCompanion copyWith({
    Value<String>? snapshotToken,
    Value<String>? entity,
    Value<int>? lastOrdinal,
    Value<String?>? nextCursor,
    Value<int>? finished,
    Value<int>? rowid,
  }) {
    return SnapshotDownloadProgressCompanion(
      snapshotToken: snapshotToken ?? this.snapshotToken,
      entity: entity ?? this.entity,
      lastOrdinal: lastOrdinal ?? this.lastOrdinal,
      nextCursor: nextCursor ?? this.nextCursor,
      finished: finished ?? this.finished,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (snapshotToken.present) {
      map['snapshot_token'] = Variable<String>(snapshotToken.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (lastOrdinal.present) {
      map['last_ordinal'] = Variable<int>(lastOrdinal.value);
    }
    if (nextCursor.present) {
      map['next_cursor'] = Variable<String>(nextCursor.value);
    }
    if (finished.present) {
      map['finished'] = Variable<int>(finished.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotDownloadProgressCompanion(')
          ..write('snapshotToken: $snapshotToken, ')
          ..write('entity: $entity, ')
          ..write('lastOrdinal: $lastOrdinal, ')
          ..write('nextCursor: $nextCursor, ')
          ..write('finished: $finished, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class SnapshotBaseline extends Table
    with TableInfo<SnapshotBaseline, SnapshotBaselineData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SnapshotBaseline(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _snapshotTokenMeta = const VerificationMeta(
    'snapshotToken',
  );
  late final GeneratedColumn<String> snapshotToken = GeneratedColumn<String>(
    'snapshot_token',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
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
  @override
  List<GeneratedColumn> get $columns => [singleton, snapshotToken, userId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snapshot_baseline';
  @override
  VerificationContext validateIntegrity(
    Insertable<SnapshotBaselineData> instance, {
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
    if (data.containsKey('snapshot_token')) {
      context.handle(
        _snapshotTokenMeta,
        snapshotToken.isAcceptableOrUnknown(
          data['snapshot_token']!,
          _snapshotTokenMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotTokenMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  SnapshotBaselineData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnapshotBaselineData(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      snapshotToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_token'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
    );
  }

  @override
  SnapshotBaseline createAlias(String alias) {
    return SnapshotBaseline(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(snapshot_token, user_id)REFERENCES snapshot_downloads(snapshot_token, user_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class SnapshotBaselineData extends DataClass
    implements Insertable<SnapshotBaselineData> {
  final int singleton;
  final String snapshotToken;
  final String userId;
  const SnapshotBaselineData({
    required this.singleton,
    required this.snapshotToken,
    required this.userId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    map['snapshot_token'] = Variable<String>(snapshotToken);
    map['user_id'] = Variable<String>(userId);
    return map;
  }

  SnapshotBaselineCompanion toCompanion(bool nullToAbsent) {
    return SnapshotBaselineCompanion(
      singleton: Value(singleton),
      snapshotToken: Value(snapshotToken),
      userId: Value(userId),
    );
  }

  factory SnapshotBaselineData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnapshotBaselineData(
      singleton: serializer.fromJson<int>(json['singleton']),
      snapshotToken: serializer.fromJson<String>(json['snapshot_token']),
      userId: serializer.fromJson<String>(json['user_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'snapshot_token': serializer.toJson<String>(snapshotToken),
      'user_id': serializer.toJson<String>(userId),
    };
  }

  SnapshotBaselineData copyWith({
    int? singleton,
    String? snapshotToken,
    String? userId,
  }) => SnapshotBaselineData(
    singleton: singleton ?? this.singleton,
    snapshotToken: snapshotToken ?? this.snapshotToken,
    userId: userId ?? this.userId,
  );
  SnapshotBaselineData copyWithCompanion(SnapshotBaselineCompanion data) {
    return SnapshotBaselineData(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      snapshotToken: data.snapshotToken.present
          ? data.snapshotToken.value
          : this.snapshotToken,
      userId: data.userId.present ? data.userId.value : this.userId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotBaselineData(')
          ..write('singleton: $singleton, ')
          ..write('snapshotToken: $snapshotToken, ')
          ..write('userId: $userId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(singleton, snapshotToken, userId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnapshotBaselineData &&
          other.singleton == this.singleton &&
          other.snapshotToken == this.snapshotToken &&
          other.userId == this.userId);
}

class SnapshotBaselineCompanion extends UpdateCompanion<SnapshotBaselineData> {
  final Value<int> singleton;
  final Value<String> snapshotToken;
  final Value<String> userId;
  const SnapshotBaselineCompanion({
    this.singleton = const Value.absent(),
    this.snapshotToken = const Value.absent(),
    this.userId = const Value.absent(),
  });
  SnapshotBaselineCompanion.insert({
    this.singleton = const Value.absent(),
    required String snapshotToken,
    required String userId,
  }) : snapshotToken = Value(snapshotToken),
       userId = Value(userId);
  static Insertable<SnapshotBaselineData> custom({
    Expression<int>? singleton,
    Expression<String>? snapshotToken,
    Expression<String>? userId,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (snapshotToken != null) 'snapshot_token': snapshotToken,
      if (userId != null) 'user_id': userId,
    });
  }

  SnapshotBaselineCompanion copyWith({
    Value<int>? singleton,
    Value<String>? snapshotToken,
    Value<String>? userId,
  }) {
    return SnapshotBaselineCompanion(
      singleton: singleton ?? this.singleton,
      snapshotToken: snapshotToken ?? this.snapshotToken,
      userId: userId ?? this.userId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (snapshotToken.present) {
      map['snapshot_token'] = Variable<String>(snapshotToken.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotBaselineCompanion(')
          ..write('singleton: $singleton, ')
          ..write('snapshotToken: $snapshotToken, ')
          ..write('userId: $userId')
          ..write(')'))
        .toString();
  }
}

class MutationConflictResolutions extends Table
    with TableInfo<MutationConflictResolutions, MutationConflictResolution> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MutationConflictResolutions(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _originalOpIdMeta = const VerificationMeta(
    'originalOpId',
  );
  late final GeneratedColumn<String> originalOpId = GeneratedColumn<String>(
    'original_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id)',
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
  static const VerificationMeta _replacementOpIdMeta = const VerificationMeta(
    'replacementOpId',
  );
  late final GeneratedColumn<String> replacementOpId = GeneratedColumn<String>(
    'replacement_op_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'UNIQUE REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _originalAttemptCountMeta =
      const VerificationMeta('originalAttemptCount');
  late final GeneratedColumn<int> originalAttemptCount = GeneratedColumn<int>(
    'original_attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (original_attempt_count > 0)',
  );
  static const VerificationMeta _resolvedRevisionMeta = const VerificationMeta(
    'resolvedRevision',
  );
  late final GeneratedColumn<int> resolvedRevision = GeneratedColumn<int>(
    'resolved_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (resolved_revision > 0)',
  );
  static const VerificationMeta _serverSnapshotMeta = const VerificationMeta(
    'serverSnapshot',
  );
  late final GeneratedColumn<String> serverSnapshot = GeneratedColumn<String>(
    'server_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(server_snapshot) AND json_type(server_snapshot) = \'object\')',
  );
  static const VerificationMeta _choicesMeta = const VerificationMeta(
    'choices',
  );
  late final GeneratedColumn<String> choices = GeneratedColumn<String>(
    'choices',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(choices) AND json_type(choices) = \'object\')',
  );
  static const VerificationMeta _orderRootOpIdMeta = const VerificationMeta(
    'orderRootOpId',
  );
  late final GeneratedColumn<String> orderRootOpId = GeneratedColumn<String>(
    'order_root_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _logicalOrderMeta = const VerificationMeta(
    'logicalOrder',
  );
  late final GeneratedColumn<int> logicalOrder = GeneratedColumn<int>(
    'logical_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (logical_order > 0)',
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
    originalOpId,
    userId,
    replacementOpId,
    originalAttemptCount,
    resolvedRevision,
    serverSnapshot,
    choices,
    orderRootOpId,
    logicalOrder,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mutation_conflict_resolutions';
  @override
  VerificationContext validateIntegrity(
    Insertable<MutationConflictResolution> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('original_op_id')) {
      context.handle(
        _originalOpIdMeta,
        originalOpId.isAcceptableOrUnknown(
          data['original_op_id']!,
          _originalOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalOpIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('replacement_op_id')) {
      context.handle(
        _replacementOpIdMeta,
        replacementOpId.isAcceptableOrUnknown(
          data['replacement_op_id']!,
          _replacementOpIdMeta,
        ),
      );
    }
    if (data.containsKey('original_attempt_count')) {
      context.handle(
        _originalAttemptCountMeta,
        originalAttemptCount.isAcceptableOrUnknown(
          data['original_attempt_count']!,
          _originalAttemptCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalAttemptCountMeta);
    }
    if (data.containsKey('resolved_revision')) {
      context.handle(
        _resolvedRevisionMeta,
        resolvedRevision.isAcceptableOrUnknown(
          data['resolved_revision']!,
          _resolvedRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_resolvedRevisionMeta);
    }
    if (data.containsKey('server_snapshot')) {
      context.handle(
        _serverSnapshotMeta,
        serverSnapshot.isAcceptableOrUnknown(
          data['server_snapshot']!,
          _serverSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverSnapshotMeta);
    }
    if (data.containsKey('choices')) {
      context.handle(
        _choicesMeta,
        choices.isAcceptableOrUnknown(data['choices']!, _choicesMeta),
      );
    } else if (isInserting) {
      context.missing(_choicesMeta);
    }
    if (data.containsKey('order_root_op_id')) {
      context.handle(
        _orderRootOpIdMeta,
        orderRootOpId.isAcceptableOrUnknown(
          data['order_root_op_id']!,
          _orderRootOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_orderRootOpIdMeta);
    }
    if (data.containsKey('logical_order')) {
      context.handle(
        _logicalOrderMeta,
        logicalOrder.isAcceptableOrUnknown(
          data['logical_order']!,
          _logicalOrderMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_logicalOrderMeta);
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
  Set<GeneratedColumn> get $primaryKey => {originalOpId};
  @override
  MutationConflictResolution map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MutationConflictResolution(
      originalOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_op_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      replacementOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replacement_op_id'],
      ),
      originalAttemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}original_attempt_count'],
      )!,
      resolvedRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolved_revision'],
      )!,
      serverSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_snapshot'],
      )!,
      choices: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}choices'],
      )!,
      orderRootOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_root_op_id'],
      )!,
      logicalOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logical_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  MutationConflictResolutions createAlias(String alias) {
    return MutationConflictResolutions(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const [
    'CHECK(replacement_op_id IS NULL OR replacement_op_id <> original_op_id)',
    'CHECK(json_type(server_snapshot, \'\$.revision\') IS \'integer\' AND json_extract(server_snapshot, \'\$.revision\') = resolved_revision)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class MutationConflictResolution extends DataClass
    implements Insertable<MutationConflictResolution> {
  final String originalOpId;
  final String userId;
  final String? replacementOpId;
  final int originalAttemptCount;
  final int resolvedRevision;
  final String serverSnapshot;
  final String choices;
  final String orderRootOpId;
  final int logicalOrder;
  final int createdAt;
  const MutationConflictResolution({
    required this.originalOpId,
    required this.userId,
    this.replacementOpId,
    required this.originalAttemptCount,
    required this.resolvedRevision,
    required this.serverSnapshot,
    required this.choices,
    required this.orderRootOpId,
    required this.logicalOrder,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['original_op_id'] = Variable<String>(originalOpId);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || replacementOpId != null) {
      map['replacement_op_id'] = Variable<String>(replacementOpId);
    }
    map['original_attempt_count'] = Variable<int>(originalAttemptCount);
    map['resolved_revision'] = Variable<int>(resolvedRevision);
    map['server_snapshot'] = Variable<String>(serverSnapshot);
    map['choices'] = Variable<String>(choices);
    map['order_root_op_id'] = Variable<String>(orderRootOpId);
    map['logical_order'] = Variable<int>(logicalOrder);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  MutationConflictResolutionsCompanion toCompanion(bool nullToAbsent) {
    return MutationConflictResolutionsCompanion(
      originalOpId: Value(originalOpId),
      userId: Value(userId),
      replacementOpId: replacementOpId == null && nullToAbsent
          ? const Value.absent()
          : Value(replacementOpId),
      originalAttemptCount: Value(originalAttemptCount),
      resolvedRevision: Value(resolvedRevision),
      serverSnapshot: Value(serverSnapshot),
      choices: Value(choices),
      orderRootOpId: Value(orderRootOpId),
      logicalOrder: Value(logicalOrder),
      createdAt: Value(createdAt),
    );
  }

  factory MutationConflictResolution.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MutationConflictResolution(
      originalOpId: serializer.fromJson<String>(json['original_op_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      replacementOpId: serializer.fromJson<String?>(json['replacement_op_id']),
      originalAttemptCount: serializer.fromJson<int>(
        json['original_attempt_count'],
      ),
      resolvedRevision: serializer.fromJson<int>(json['resolved_revision']),
      serverSnapshot: serializer.fromJson<String>(json['server_snapshot']),
      choices: serializer.fromJson<String>(json['choices']),
      orderRootOpId: serializer.fromJson<String>(json['order_root_op_id']),
      logicalOrder: serializer.fromJson<int>(json['logical_order']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'original_op_id': serializer.toJson<String>(originalOpId),
      'user_id': serializer.toJson<String>(userId),
      'replacement_op_id': serializer.toJson<String?>(replacementOpId),
      'original_attempt_count': serializer.toJson<int>(originalAttemptCount),
      'resolved_revision': serializer.toJson<int>(resolvedRevision),
      'server_snapshot': serializer.toJson<String>(serverSnapshot),
      'choices': serializer.toJson<String>(choices),
      'order_root_op_id': serializer.toJson<String>(orderRootOpId),
      'logical_order': serializer.toJson<int>(logicalOrder),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  MutationConflictResolution copyWith({
    String? originalOpId,
    String? userId,
    Value<String?> replacementOpId = const Value.absent(),
    int? originalAttemptCount,
    int? resolvedRevision,
    String? serverSnapshot,
    String? choices,
    String? orderRootOpId,
    int? logicalOrder,
    int? createdAt,
  }) => MutationConflictResolution(
    originalOpId: originalOpId ?? this.originalOpId,
    userId: userId ?? this.userId,
    replacementOpId: replacementOpId.present
        ? replacementOpId.value
        : this.replacementOpId,
    originalAttemptCount: originalAttemptCount ?? this.originalAttemptCount,
    resolvedRevision: resolvedRevision ?? this.resolvedRevision,
    serverSnapshot: serverSnapshot ?? this.serverSnapshot,
    choices: choices ?? this.choices,
    orderRootOpId: orderRootOpId ?? this.orderRootOpId,
    logicalOrder: logicalOrder ?? this.logicalOrder,
    createdAt: createdAt ?? this.createdAt,
  );
  MutationConflictResolution copyWithCompanion(
    MutationConflictResolutionsCompanion data,
  ) {
    return MutationConflictResolution(
      originalOpId: data.originalOpId.present
          ? data.originalOpId.value
          : this.originalOpId,
      userId: data.userId.present ? data.userId.value : this.userId,
      replacementOpId: data.replacementOpId.present
          ? data.replacementOpId.value
          : this.replacementOpId,
      originalAttemptCount: data.originalAttemptCount.present
          ? data.originalAttemptCount.value
          : this.originalAttemptCount,
      resolvedRevision: data.resolvedRevision.present
          ? data.resolvedRevision.value
          : this.resolvedRevision,
      serverSnapshot: data.serverSnapshot.present
          ? data.serverSnapshot.value
          : this.serverSnapshot,
      choices: data.choices.present ? data.choices.value : this.choices,
      orderRootOpId: data.orderRootOpId.present
          ? data.orderRootOpId.value
          : this.orderRootOpId,
      logicalOrder: data.logicalOrder.present
          ? data.logicalOrder.value
          : this.logicalOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MutationConflictResolution(')
          ..write('originalOpId: $originalOpId, ')
          ..write('userId: $userId, ')
          ..write('replacementOpId: $replacementOpId, ')
          ..write('originalAttemptCount: $originalAttemptCount, ')
          ..write('resolvedRevision: $resolvedRevision, ')
          ..write('serverSnapshot: $serverSnapshot, ')
          ..write('choices: $choices, ')
          ..write('orderRootOpId: $orderRootOpId, ')
          ..write('logicalOrder: $logicalOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    originalOpId,
    userId,
    replacementOpId,
    originalAttemptCount,
    resolvedRevision,
    serverSnapshot,
    choices,
    orderRootOpId,
    logicalOrder,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MutationConflictResolution &&
          other.originalOpId == this.originalOpId &&
          other.userId == this.userId &&
          other.replacementOpId == this.replacementOpId &&
          other.originalAttemptCount == this.originalAttemptCount &&
          other.resolvedRevision == this.resolvedRevision &&
          other.serverSnapshot == this.serverSnapshot &&
          other.choices == this.choices &&
          other.orderRootOpId == this.orderRootOpId &&
          other.logicalOrder == this.logicalOrder &&
          other.createdAt == this.createdAt);
}

class MutationConflictResolutionsCompanion
    extends UpdateCompanion<MutationConflictResolution> {
  final Value<String> originalOpId;
  final Value<String> userId;
  final Value<String?> replacementOpId;
  final Value<int> originalAttemptCount;
  final Value<int> resolvedRevision;
  final Value<String> serverSnapshot;
  final Value<String> choices;
  final Value<String> orderRootOpId;
  final Value<int> logicalOrder;
  final Value<int> createdAt;
  const MutationConflictResolutionsCompanion({
    this.originalOpId = const Value.absent(),
    this.userId = const Value.absent(),
    this.replacementOpId = const Value.absent(),
    this.originalAttemptCount = const Value.absent(),
    this.resolvedRevision = const Value.absent(),
    this.serverSnapshot = const Value.absent(),
    this.choices = const Value.absent(),
    this.orderRootOpId = const Value.absent(),
    this.logicalOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MutationConflictResolutionsCompanion.insert({
    required String originalOpId,
    required String userId,
    this.replacementOpId = const Value.absent(),
    required int originalAttemptCount,
    required int resolvedRevision,
    required String serverSnapshot,
    required String choices,
    required String orderRootOpId,
    required int logicalOrder,
    required int createdAt,
  }) : originalOpId = Value(originalOpId),
       userId = Value(userId),
       originalAttemptCount = Value(originalAttemptCount),
       resolvedRevision = Value(resolvedRevision),
       serverSnapshot = Value(serverSnapshot),
       choices = Value(choices),
       orderRootOpId = Value(orderRootOpId),
       logicalOrder = Value(logicalOrder),
       createdAt = Value(createdAt);
  static Insertable<MutationConflictResolution> custom({
    Expression<String>? originalOpId,
    Expression<String>? userId,
    Expression<String>? replacementOpId,
    Expression<int>? originalAttemptCount,
    Expression<int>? resolvedRevision,
    Expression<String>? serverSnapshot,
    Expression<String>? choices,
    Expression<String>? orderRootOpId,
    Expression<int>? logicalOrder,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (originalOpId != null) 'original_op_id': originalOpId,
      if (userId != null) 'user_id': userId,
      if (replacementOpId != null) 'replacement_op_id': replacementOpId,
      if (originalAttemptCount != null)
        'original_attempt_count': originalAttemptCount,
      if (resolvedRevision != null) 'resolved_revision': resolvedRevision,
      if (serverSnapshot != null) 'server_snapshot': serverSnapshot,
      if (choices != null) 'choices': choices,
      if (orderRootOpId != null) 'order_root_op_id': orderRootOpId,
      if (logicalOrder != null) 'logical_order': logicalOrder,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MutationConflictResolutionsCompanion copyWith({
    Value<String>? originalOpId,
    Value<String>? userId,
    Value<String?>? replacementOpId,
    Value<int>? originalAttemptCount,
    Value<int>? resolvedRevision,
    Value<String>? serverSnapshot,
    Value<String>? choices,
    Value<String>? orderRootOpId,
    Value<int>? logicalOrder,
    Value<int>? createdAt,
  }) {
    return MutationConflictResolutionsCompanion(
      originalOpId: originalOpId ?? this.originalOpId,
      userId: userId ?? this.userId,
      replacementOpId: replacementOpId ?? this.replacementOpId,
      originalAttemptCount: originalAttemptCount ?? this.originalAttemptCount,
      resolvedRevision: resolvedRevision ?? this.resolvedRevision,
      serverSnapshot: serverSnapshot ?? this.serverSnapshot,
      choices: choices ?? this.choices,
      orderRootOpId: orderRootOpId ?? this.orderRootOpId,
      logicalOrder: logicalOrder ?? this.logicalOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (originalOpId.present) {
      map['original_op_id'] = Variable<String>(originalOpId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (replacementOpId.present) {
      map['replacement_op_id'] = Variable<String>(replacementOpId.value);
    }
    if (originalAttemptCount.present) {
      map['original_attempt_count'] = Variable<int>(originalAttemptCount.value);
    }
    if (resolvedRevision.present) {
      map['resolved_revision'] = Variable<int>(resolvedRevision.value);
    }
    if (serverSnapshot.present) {
      map['server_snapshot'] = Variable<String>(serverSnapshot.value);
    }
    if (choices.present) {
      map['choices'] = Variable<String>(choices.value);
    }
    if (orderRootOpId.present) {
      map['order_root_op_id'] = Variable<String>(orderRootOpId.value);
    }
    if (logicalOrder.present) {
      map['logical_order'] = Variable<int>(logicalOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MutationConflictResolutionsCompanion(')
          ..write('originalOpId: $originalOpId, ')
          ..write('userId: $userId, ')
          ..write('replacementOpId: $replacementOpId, ')
          ..write('originalAttemptCount: $originalAttemptCount, ')
          ..write('resolvedRevision: $resolvedRevision, ')
          ..write('serverSnapshot: $serverSnapshot, ')
          ..write('choices: $choices, ')
          ..write('orderRootOpId: $orderRootOpId, ')
          ..write('logicalOrder: $logicalOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class PendingEditResolutions extends Table
    with TableInfo<PendingEditResolutions, PendingEditResolution> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PendingEditResolutions(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _originalOpIdMeta = const VerificationMeta(
    'originalOpId',
  );
  late final GeneratedColumn<String> originalOpId = GeneratedColumn<String>(
    'original_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id)',
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
  static const VerificationMeta _replacementOpIdMeta = const VerificationMeta(
    'replacementOpId',
  );
  late final GeneratedColumn<String> replacementOpId = GeneratedColumn<String>(
    'replacement_op_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'UNIQUE REFERENCES local_mutations(op_id)',
  );
  static const VerificationMeta _serverSnapshotMeta = const VerificationMeta(
    'serverSnapshot',
  );
  late final GeneratedColumn<String> serverSnapshot = GeneratedColumn<String>(
    'server_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(server_snapshot) AND json_type(server_snapshot) = \'object\')',
  );
  static const VerificationMeta _choicesMeta = const VerificationMeta(
    'choices',
  );
  late final GeneratedColumn<String> choices = GeneratedColumn<String>(
    'choices',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(choices) AND json_type(choices) = \'object\')',
  );
  static const VerificationMeta _originalEvidenceMeta = const VerificationMeta(
    'originalEvidence',
  );
  late final GeneratedColumn<String> originalEvidence = GeneratedColumn<String>(
    'original_evidence',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(original_evidence) AND json_type(original_evidence) = \'object\')',
  );
  static const VerificationMeta _logicalOrderMeta = const VerificationMeta(
    'logicalOrder',
  );
  late final GeneratedColumn<int> logicalOrder = GeneratedColumn<int>(
    'logical_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (logical_order > 0)',
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
    originalOpId,
    userId,
    replacementOpId,
    serverSnapshot,
    choices,
    originalEvidence,
    logicalOrder,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_edit_resolutions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingEditResolution> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('original_op_id')) {
      context.handle(
        _originalOpIdMeta,
        originalOpId.isAcceptableOrUnknown(
          data['original_op_id']!,
          _originalOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalOpIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('replacement_op_id')) {
      context.handle(
        _replacementOpIdMeta,
        replacementOpId.isAcceptableOrUnknown(
          data['replacement_op_id']!,
          _replacementOpIdMeta,
        ),
      );
    }
    if (data.containsKey('server_snapshot')) {
      context.handle(
        _serverSnapshotMeta,
        serverSnapshot.isAcceptableOrUnknown(
          data['server_snapshot']!,
          _serverSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverSnapshotMeta);
    }
    if (data.containsKey('choices')) {
      context.handle(
        _choicesMeta,
        choices.isAcceptableOrUnknown(data['choices']!, _choicesMeta),
      );
    } else if (isInserting) {
      context.missing(_choicesMeta);
    }
    if (data.containsKey('original_evidence')) {
      context.handle(
        _originalEvidenceMeta,
        originalEvidence.isAcceptableOrUnknown(
          data['original_evidence']!,
          _originalEvidenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalEvidenceMeta);
    }
    if (data.containsKey('logical_order')) {
      context.handle(
        _logicalOrderMeta,
        logicalOrder.isAcceptableOrUnknown(
          data['logical_order']!,
          _logicalOrderMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_logicalOrderMeta);
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
  Set<GeneratedColumn> get $primaryKey => {originalOpId};
  @override
  PendingEditResolution map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingEditResolution(
      originalOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_op_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      replacementOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replacement_op_id'],
      ),
      serverSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_snapshot'],
      )!,
      choices: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}choices'],
      )!,
      originalEvidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_evidence'],
      )!,
      logicalOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logical_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  PendingEditResolutions createAlias(String alias) {
    return PendingEditResolutions(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const [
    'CHECK(replacement_op_id IS NULL OR replacement_op_id <> original_op_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class PendingEditResolution extends DataClass
    implements Insertable<PendingEditResolution> {
  final String originalOpId;
  final String userId;
  final String? replacementOpId;
  final String serverSnapshot;
  final String choices;
  final String originalEvidence;
  final int logicalOrder;
  final int createdAt;
  const PendingEditResolution({
    required this.originalOpId,
    required this.userId,
    this.replacementOpId,
    required this.serverSnapshot,
    required this.choices,
    required this.originalEvidence,
    required this.logicalOrder,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['original_op_id'] = Variable<String>(originalOpId);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || replacementOpId != null) {
      map['replacement_op_id'] = Variable<String>(replacementOpId);
    }
    map['server_snapshot'] = Variable<String>(serverSnapshot);
    map['choices'] = Variable<String>(choices);
    map['original_evidence'] = Variable<String>(originalEvidence);
    map['logical_order'] = Variable<int>(logicalOrder);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  PendingEditResolutionsCompanion toCompanion(bool nullToAbsent) {
    return PendingEditResolutionsCompanion(
      originalOpId: Value(originalOpId),
      userId: Value(userId),
      replacementOpId: replacementOpId == null && nullToAbsent
          ? const Value.absent()
          : Value(replacementOpId),
      serverSnapshot: Value(serverSnapshot),
      choices: Value(choices),
      originalEvidence: Value(originalEvidence),
      logicalOrder: Value(logicalOrder),
      createdAt: Value(createdAt),
    );
  }

  factory PendingEditResolution.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingEditResolution(
      originalOpId: serializer.fromJson<String>(json['original_op_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      replacementOpId: serializer.fromJson<String?>(json['replacement_op_id']),
      serverSnapshot: serializer.fromJson<String>(json['server_snapshot']),
      choices: serializer.fromJson<String>(json['choices']),
      originalEvidence: serializer.fromJson<String>(json['original_evidence']),
      logicalOrder: serializer.fromJson<int>(json['logical_order']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'original_op_id': serializer.toJson<String>(originalOpId),
      'user_id': serializer.toJson<String>(userId),
      'replacement_op_id': serializer.toJson<String?>(replacementOpId),
      'server_snapshot': serializer.toJson<String>(serverSnapshot),
      'choices': serializer.toJson<String>(choices),
      'original_evidence': serializer.toJson<String>(originalEvidence),
      'logical_order': serializer.toJson<int>(logicalOrder),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  PendingEditResolution copyWith({
    String? originalOpId,
    String? userId,
    Value<String?> replacementOpId = const Value.absent(),
    String? serverSnapshot,
    String? choices,
    String? originalEvidence,
    int? logicalOrder,
    int? createdAt,
  }) => PendingEditResolution(
    originalOpId: originalOpId ?? this.originalOpId,
    userId: userId ?? this.userId,
    replacementOpId: replacementOpId.present
        ? replacementOpId.value
        : this.replacementOpId,
    serverSnapshot: serverSnapshot ?? this.serverSnapshot,
    choices: choices ?? this.choices,
    originalEvidence: originalEvidence ?? this.originalEvidence,
    logicalOrder: logicalOrder ?? this.logicalOrder,
    createdAt: createdAt ?? this.createdAt,
  );
  PendingEditResolution copyWithCompanion(
    PendingEditResolutionsCompanion data,
  ) {
    return PendingEditResolution(
      originalOpId: data.originalOpId.present
          ? data.originalOpId.value
          : this.originalOpId,
      userId: data.userId.present ? data.userId.value : this.userId,
      replacementOpId: data.replacementOpId.present
          ? data.replacementOpId.value
          : this.replacementOpId,
      serverSnapshot: data.serverSnapshot.present
          ? data.serverSnapshot.value
          : this.serverSnapshot,
      choices: data.choices.present ? data.choices.value : this.choices,
      originalEvidence: data.originalEvidence.present
          ? data.originalEvidence.value
          : this.originalEvidence,
      logicalOrder: data.logicalOrder.present
          ? data.logicalOrder.value
          : this.logicalOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingEditResolution(')
          ..write('originalOpId: $originalOpId, ')
          ..write('userId: $userId, ')
          ..write('replacementOpId: $replacementOpId, ')
          ..write('serverSnapshot: $serverSnapshot, ')
          ..write('choices: $choices, ')
          ..write('originalEvidence: $originalEvidence, ')
          ..write('logicalOrder: $logicalOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    originalOpId,
    userId,
    replacementOpId,
    serverSnapshot,
    choices,
    originalEvidence,
    logicalOrder,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingEditResolution &&
          other.originalOpId == this.originalOpId &&
          other.userId == this.userId &&
          other.replacementOpId == this.replacementOpId &&
          other.serverSnapshot == this.serverSnapshot &&
          other.choices == this.choices &&
          other.originalEvidence == this.originalEvidence &&
          other.logicalOrder == this.logicalOrder &&
          other.createdAt == this.createdAt);
}

class PendingEditResolutionsCompanion
    extends UpdateCompanion<PendingEditResolution> {
  final Value<String> originalOpId;
  final Value<String> userId;
  final Value<String?> replacementOpId;
  final Value<String> serverSnapshot;
  final Value<String> choices;
  final Value<String> originalEvidence;
  final Value<int> logicalOrder;
  final Value<int> createdAt;
  const PendingEditResolutionsCompanion({
    this.originalOpId = const Value.absent(),
    this.userId = const Value.absent(),
    this.replacementOpId = const Value.absent(),
    this.serverSnapshot = const Value.absent(),
    this.choices = const Value.absent(),
    this.originalEvidence = const Value.absent(),
    this.logicalOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PendingEditResolutionsCompanion.insert({
    required String originalOpId,
    required String userId,
    this.replacementOpId = const Value.absent(),
    required String serverSnapshot,
    required String choices,
    required String originalEvidence,
    required int logicalOrder,
    required int createdAt,
  }) : originalOpId = Value(originalOpId),
       userId = Value(userId),
       serverSnapshot = Value(serverSnapshot),
       choices = Value(choices),
       originalEvidence = Value(originalEvidence),
       logicalOrder = Value(logicalOrder),
       createdAt = Value(createdAt);
  static Insertable<PendingEditResolution> custom({
    Expression<String>? originalOpId,
    Expression<String>? userId,
    Expression<String>? replacementOpId,
    Expression<String>? serverSnapshot,
    Expression<String>? choices,
    Expression<String>? originalEvidence,
    Expression<int>? logicalOrder,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (originalOpId != null) 'original_op_id': originalOpId,
      if (userId != null) 'user_id': userId,
      if (replacementOpId != null) 'replacement_op_id': replacementOpId,
      if (serverSnapshot != null) 'server_snapshot': serverSnapshot,
      if (choices != null) 'choices': choices,
      if (originalEvidence != null) 'original_evidence': originalEvidence,
      if (logicalOrder != null) 'logical_order': logicalOrder,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PendingEditResolutionsCompanion copyWith({
    Value<String>? originalOpId,
    Value<String>? userId,
    Value<String?>? replacementOpId,
    Value<String>? serverSnapshot,
    Value<String>? choices,
    Value<String>? originalEvidence,
    Value<int>? logicalOrder,
    Value<int>? createdAt,
  }) {
    return PendingEditResolutionsCompanion(
      originalOpId: originalOpId ?? this.originalOpId,
      userId: userId ?? this.userId,
      replacementOpId: replacementOpId ?? this.replacementOpId,
      serverSnapshot: serverSnapshot ?? this.serverSnapshot,
      choices: choices ?? this.choices,
      originalEvidence: originalEvidence ?? this.originalEvidence,
      logicalOrder: logicalOrder ?? this.logicalOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (originalOpId.present) {
      map['original_op_id'] = Variable<String>(originalOpId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (replacementOpId.present) {
      map['replacement_op_id'] = Variable<String>(replacementOpId.value);
    }
    if (serverSnapshot.present) {
      map['server_snapshot'] = Variable<String>(serverSnapshot.value);
    }
    if (choices.present) {
      map['choices'] = Variable<String>(choices.value);
    }
    if (originalEvidence.present) {
      map['original_evidence'] = Variable<String>(originalEvidence.value);
    }
    if (logicalOrder.present) {
      map['logical_order'] = Variable<int>(logicalOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingEditResolutionsCompanion(')
          ..write('originalOpId: $originalOpId, ')
          ..write('userId: $userId, ')
          ..write('replacementOpId: $replacementOpId, ')
          ..write('serverSnapshot: $serverSnapshot, ')
          ..write('choices: $choices, ')
          ..write('originalEvidence: $originalEvidence, ')
          ..write('logicalOrder: $logicalOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class LocalUploadQueue extends Table
    with TableInfo<LocalUploadQueue, LocalUploadQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LocalUploadQueue(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _renewOperationIdMeta = const VerificationMeta(
    'renewOperationId',
  );
  late final GeneratedColumn<String> renewOperationId = GeneratedColumn<String>(
    'renew_operation_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (renew_operation_id IS NULL OR length(renew_operation_id) = 36)',
  );
  static const VerificationMeta _attemptIdMeta = const VerificationMeta(
    'attemptId',
  );
  late final GeneratedColumn<String> attemptId = GeneratedColumn<String>(
    'attempt_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (attempt_id IS NULL OR length(attempt_id) = 36)',
  );
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (phase IN (\'PENDING\', \'SENDING\', \'RETRY\', \'BLOCKED\', \'CANCELLED\', \'UPLOADED\', \'STORED\'))',
  );
  static const VerificationMeta _claimIdMeta = const VerificationMeta(
    'claimId',
  );
  late final GeneratedColumn<String> claimId = GeneratedColumn<String>(
    'claim_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _expectedSizeMeta = const VerificationMeta(
    'expectedSize',
  );
  late final GeneratedColumn<int> expectedSize = GeneratedColumn<int>(
    'expected_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (expected_size BETWEEN 1 AND 6291456)',
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(sha256) = 64 AND sha256 NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _automaticRetriesMeta = const VerificationMeta(
    'automaticRetries',
  );
  late final GeneratedColumn<int> automaticRetries = GeneratedColumn<int>(
    'automatic_retries',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT 0 CHECK (automatic_retries BETWEEN 0 AND 3)',
    defaultValue: const CustomExpression('0'),
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
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
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
    recordingId,
    userId,
    operationId,
    renewOperationId,
    attemptId,
    phase,
    claimId,
    expectedSize,
    sha256,
    automaticRetries,
    attemptCount,
    nextAttemptAt,
    reason,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_upload_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalUploadQueueData> instance, {
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
    if (data.containsKey('renew_operation_id')) {
      context.handle(
        _renewOperationIdMeta,
        renewOperationId.isAcceptableOrUnknown(
          data['renew_operation_id']!,
          _renewOperationIdMeta,
        ),
      );
    }
    if (data.containsKey('attempt_id')) {
      context.handle(
        _attemptIdMeta,
        attemptId.isAcceptableOrUnknown(data['attempt_id']!, _attemptIdMeta),
      );
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    } else if (isInserting) {
      context.missing(_phaseMeta);
    }
    if (data.containsKey('claim_id')) {
      context.handle(
        _claimIdMeta,
        claimId.isAcceptableOrUnknown(data['claim_id']!, _claimIdMeta),
      );
    }
    if (data.containsKey('expected_size')) {
      context.handle(
        _expectedSizeMeta,
        expectedSize.isAcceptableOrUnknown(
          data['expected_size']!,
          _expectedSizeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedSizeMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('automatic_retries')) {
      context.handle(
        _automaticRetriesMeta,
        automaticRetries.isAcceptableOrUnknown(
          data['automatic_retries']!,
          _automaticRetriesMeta,
        ),
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
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
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
  Set<GeneratedColumn> get $primaryKey => {recordingId};
  @override
  LocalUploadQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalUploadQueueData(
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
      renewOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}renew_operation_id'],
      ),
      attemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attempt_id'],
      ),
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      )!,
      claimId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}claim_id'],
      ),
      expectedSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_size'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      automaticRetries: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}automatic_retries'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at'],
      ),
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
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
  LocalUploadQueue createAlias(String alias) {
    return LocalUploadQueue(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(user_id, recording_id)REFERENCES local_recording_files(user_id, recording_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class LocalUploadQueueData extends DataClass
    implements Insertable<LocalUploadQueueData> {
  final String recordingId;
  final String userId;
  final String operationId;
  final String? renewOperationId;
  final String? attemptId;
  final String phase;
  final String? claimId;
  final int expectedSize;
  final String sha256;
  final int automaticRetries;
  final int attemptCount;
  final int? nextAttemptAt;
  final String? reason;
  final int createdAt;
  final int updatedAt;
  const LocalUploadQueueData({
    required this.recordingId,
    required this.userId,
    required this.operationId,
    this.renewOperationId,
    this.attemptId,
    required this.phase,
    this.claimId,
    required this.expectedSize,
    required this.sha256,
    required this.automaticRetries,
    required this.attemptCount,
    this.nextAttemptAt,
    this.reason,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['recording_id'] = Variable<String>(recordingId);
    map['user_id'] = Variable<String>(userId);
    map['operation_id'] = Variable<String>(operationId);
    if (!nullToAbsent || renewOperationId != null) {
      map['renew_operation_id'] = Variable<String>(renewOperationId);
    }
    if (!nullToAbsent || attemptId != null) {
      map['attempt_id'] = Variable<String>(attemptId);
    }
    map['phase'] = Variable<String>(phase);
    if (!nullToAbsent || claimId != null) {
      map['claim_id'] = Variable<String>(claimId);
    }
    map['expected_size'] = Variable<int>(expectedSize);
    map['sha256'] = Variable<String>(sha256);
    map['automatic_retries'] = Variable<int>(automaticRetries);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    }
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  LocalUploadQueueCompanion toCompanion(bool nullToAbsent) {
    return LocalUploadQueueCompanion(
      recordingId: Value(recordingId),
      userId: Value(userId),
      operationId: Value(operationId),
      renewOperationId: renewOperationId == null && nullToAbsent
          ? const Value.absent()
          : Value(renewOperationId),
      attemptId: attemptId == null && nullToAbsent
          ? const Value.absent()
          : Value(attemptId),
      phase: Value(phase),
      claimId: claimId == null && nullToAbsent
          ? const Value.absent()
          : Value(claimId),
      expectedSize: Value(expectedSize),
      sha256: Value(sha256),
      automaticRetries: Value(automaticRetries),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalUploadQueueData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalUploadQueueData(
      recordingId: serializer.fromJson<String>(json['recording_id']),
      userId: serializer.fromJson<String>(json['user_id']),
      operationId: serializer.fromJson<String>(json['operation_id']),
      renewOperationId: serializer.fromJson<String?>(
        json['renew_operation_id'],
      ),
      attemptId: serializer.fromJson<String?>(json['attempt_id']),
      phase: serializer.fromJson<String>(json['phase']),
      claimId: serializer.fromJson<String?>(json['claim_id']),
      expectedSize: serializer.fromJson<int>(json['expected_size']),
      sha256: serializer.fromJson<String>(json['sha256']),
      automaticRetries: serializer.fromJson<int>(json['automatic_retries']),
      attemptCount: serializer.fromJson<int>(json['attempt_count']),
      nextAttemptAt: serializer.fromJson<int?>(json['next_attempt_at']),
      reason: serializer.fromJson<String?>(json['reason']),
      createdAt: serializer.fromJson<int>(json['created_at']),
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
      'renew_operation_id': serializer.toJson<String?>(renewOperationId),
      'attempt_id': serializer.toJson<String?>(attemptId),
      'phase': serializer.toJson<String>(phase),
      'claim_id': serializer.toJson<String?>(claimId),
      'expected_size': serializer.toJson<int>(expectedSize),
      'sha256': serializer.toJson<String>(sha256),
      'automatic_retries': serializer.toJson<int>(automaticRetries),
      'attempt_count': serializer.toJson<int>(attemptCount),
      'next_attempt_at': serializer.toJson<int?>(nextAttemptAt),
      'reason': serializer.toJson<String?>(reason),
      'created_at': serializer.toJson<int>(createdAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  LocalUploadQueueData copyWith({
    String? recordingId,
    String? userId,
    String? operationId,
    Value<String?> renewOperationId = const Value.absent(),
    Value<String?> attemptId = const Value.absent(),
    String? phase,
    Value<String?> claimId = const Value.absent(),
    int? expectedSize,
    String? sha256,
    int? automaticRetries,
    int? attemptCount,
    Value<int?> nextAttemptAt = const Value.absent(),
    Value<String?> reason = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => LocalUploadQueueData(
    recordingId: recordingId ?? this.recordingId,
    userId: userId ?? this.userId,
    operationId: operationId ?? this.operationId,
    renewOperationId: renewOperationId.present
        ? renewOperationId.value
        : this.renewOperationId,
    attemptId: attemptId.present ? attemptId.value : this.attemptId,
    phase: phase ?? this.phase,
    claimId: claimId.present ? claimId.value : this.claimId,
    expectedSize: expectedSize ?? this.expectedSize,
    sha256: sha256 ?? this.sha256,
    automaticRetries: automaticRetries ?? this.automaticRetries,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    reason: reason.present ? reason.value : this.reason,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalUploadQueueData copyWithCompanion(LocalUploadQueueCompanion data) {
    return LocalUploadQueueData(
      recordingId: data.recordingId.present
          ? data.recordingId.value
          : this.recordingId,
      userId: data.userId.present ? data.userId.value : this.userId,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      renewOperationId: data.renewOperationId.present
          ? data.renewOperationId.value
          : this.renewOperationId,
      attemptId: data.attemptId.present ? data.attemptId.value : this.attemptId,
      phase: data.phase.present ? data.phase.value : this.phase,
      claimId: data.claimId.present ? data.claimId.value : this.claimId,
      expectedSize: data.expectedSize.present
          ? data.expectedSize.value
          : this.expectedSize,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      automaticRetries: data.automaticRetries.present
          ? data.automaticRetries.value
          : this.automaticRetries,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      reason: data.reason.present ? data.reason.value : this.reason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalUploadQueueData(')
          ..write('recordingId: $recordingId, ')
          ..write('userId: $userId, ')
          ..write('operationId: $operationId, ')
          ..write('renewOperationId: $renewOperationId, ')
          ..write('attemptId: $attemptId, ')
          ..write('phase: $phase, ')
          ..write('claimId: $claimId, ')
          ..write('expectedSize: $expectedSize, ')
          ..write('sha256: $sha256, ')
          ..write('automaticRetries: $automaticRetries, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    recordingId,
    userId,
    operationId,
    renewOperationId,
    attemptId,
    phase,
    claimId,
    expectedSize,
    sha256,
    automaticRetries,
    attemptCount,
    nextAttemptAt,
    reason,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalUploadQueueData &&
          other.recordingId == this.recordingId &&
          other.userId == this.userId &&
          other.operationId == this.operationId &&
          other.renewOperationId == this.renewOperationId &&
          other.attemptId == this.attemptId &&
          other.phase == this.phase &&
          other.claimId == this.claimId &&
          other.expectedSize == this.expectedSize &&
          other.sha256 == this.sha256 &&
          other.automaticRetries == this.automaticRetries &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.reason == this.reason &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalUploadQueueCompanion extends UpdateCompanion<LocalUploadQueueData> {
  final Value<String> recordingId;
  final Value<String> userId;
  final Value<String> operationId;
  final Value<String?> renewOperationId;
  final Value<String?> attemptId;
  final Value<String> phase;
  final Value<String?> claimId;
  final Value<int> expectedSize;
  final Value<String> sha256;
  final Value<int> automaticRetries;
  final Value<int> attemptCount;
  final Value<int?> nextAttemptAt;
  final Value<String?> reason;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const LocalUploadQueueCompanion({
    this.recordingId = const Value.absent(),
    this.userId = const Value.absent(),
    this.operationId = const Value.absent(),
    this.renewOperationId = const Value.absent(),
    this.attemptId = const Value.absent(),
    this.phase = const Value.absent(),
    this.claimId = const Value.absent(),
    this.expectedSize = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.automaticRetries = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.reason = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalUploadQueueCompanion.insert({
    required String recordingId,
    required String userId,
    required String operationId,
    this.renewOperationId = const Value.absent(),
    this.attemptId = const Value.absent(),
    required String phase,
    this.claimId = const Value.absent(),
    required int expectedSize,
    required String sha256,
    this.automaticRetries = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.reason = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : recordingId = Value(recordingId),
       userId = Value(userId),
       operationId = Value(operationId),
       phase = Value(phase),
       expectedSize = Value(expectedSize),
       sha256 = Value(sha256),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalUploadQueueData> custom({
    Expression<String>? recordingId,
    Expression<String>? userId,
    Expression<String>? operationId,
    Expression<String>? renewOperationId,
    Expression<String>? attemptId,
    Expression<String>? phase,
    Expression<String>? claimId,
    Expression<int>? expectedSize,
    Expression<String>? sha256,
    Expression<int>? automaticRetries,
    Expression<int>? attemptCount,
    Expression<int>? nextAttemptAt,
    Expression<String>? reason,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordingId != null) 'recording_id': recordingId,
      if (userId != null) 'user_id': userId,
      if (operationId != null) 'operation_id': operationId,
      if (renewOperationId != null) 'renew_operation_id': renewOperationId,
      if (attemptId != null) 'attempt_id': attemptId,
      if (phase != null) 'phase': phase,
      if (claimId != null) 'claim_id': claimId,
      if (expectedSize != null) 'expected_size': expectedSize,
      if (sha256 != null) 'sha256': sha256,
      if (automaticRetries != null) 'automatic_retries': automaticRetries,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (reason != null) 'reason': reason,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalUploadQueueCompanion copyWith({
    Value<String>? recordingId,
    Value<String>? userId,
    Value<String>? operationId,
    Value<String?>? renewOperationId,
    Value<String?>? attemptId,
    Value<String>? phase,
    Value<String?>? claimId,
    Value<int>? expectedSize,
    Value<String>? sha256,
    Value<int>? automaticRetries,
    Value<int>? attemptCount,
    Value<int?>? nextAttemptAt,
    Value<String?>? reason,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalUploadQueueCompanion(
      recordingId: recordingId ?? this.recordingId,
      userId: userId ?? this.userId,
      operationId: operationId ?? this.operationId,
      renewOperationId: renewOperationId ?? this.renewOperationId,
      attemptId: attemptId ?? this.attemptId,
      phase: phase ?? this.phase,
      claimId: claimId ?? this.claimId,
      expectedSize: expectedSize ?? this.expectedSize,
      sha256: sha256 ?? this.sha256,
      automaticRetries: automaticRetries ?? this.automaticRetries,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
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
    if (renewOperationId.present) {
      map['renew_operation_id'] = Variable<String>(renewOperationId.value);
    }
    if (attemptId.present) {
      map['attempt_id'] = Variable<String>(attemptId.value);
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (claimId.present) {
      map['claim_id'] = Variable<String>(claimId.value);
    }
    if (expectedSize.present) {
      map['expected_size'] = Variable<int>(expectedSize.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (automaticRetries.present) {
      map['automatic_retries'] = Variable<int>(automaticRetries.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
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
    return (StringBuffer('LocalUploadQueueCompanion(')
          ..write('recordingId: $recordingId, ')
          ..write('userId: $userId, ')
          ..write('operationId: $operationId, ')
          ..write('renewOperationId: $renewOperationId, ')
          ..write('attemptId: $attemptId, ')
          ..write('phase: $phase, ')
          ..write('claimId: $claimId, ')
          ..write('expectedSize: $expectedSize, ')
          ..write('sha256: $sha256, ')
          ..write('automaticRetries: $automaticRetries, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class LocalCleanupConfirmations extends Table
    with TableInfo<LocalCleanupConfirmations, LocalCleanupConfirmation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LocalCleanupConfirmations(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tokenMeta = const VerificationMeta('token');
  late final GeneratedColumn<String> token = GeneratedColumn<String>(
    'token',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(token) = 36)',
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
  static const VerificationMeta _recordingIdMeta = const VerificationMeta(
    'recordingId',
  );
  late final GeneratedColumn<String> recordingId = GeneratedColumn<String>(
    'recording_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  late final GeneratedColumn<String> generation = GeneratedColumn<String>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(generation) = 36)',
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(sha256) = 64 AND sha256 NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _cloudRevisionMeta = const VerificationMeta(
    'cloudRevision',
  );
  late final GeneratedColumn<int> cloudRevision = GeneratedColumn<int>(
    'cloud_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (cloud_revision > 0)',
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (state IN (\'PREPARING\', \'CONFIRMED\', \'SUCCEEDED\', \'CANCELLED\', \'EXPIRED\'))',
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
    token,
    userId,
    recordingId,
    generation,
    sha256,
    cloudRevision,
    expiresAt,
    state,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_cleanup_confirmations';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCleanupConfirmation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('token')) {
      context.handle(
        _tokenMeta,
        token.isAcceptableOrUnknown(data['token']!, _tokenMeta),
      );
    } else if (isInserting) {
      context.missing(_tokenMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
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
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    } else if (isInserting) {
      context.missing(_generationMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('cloud_revision')) {
      context.handle(
        _cloudRevisionMeta,
        cloudRevision.isAcceptableOrUnknown(
          data['cloud_revision']!,
          _cloudRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cloudRevisionMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
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
  Set<GeneratedColumn> get $primaryKey => {token};
  @override
  LocalCleanupConfirmation map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCleanupConfirmation(
      token: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      recordingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recording_id'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}generation'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      cloudRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cloud_revision'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
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
  LocalCleanupConfirmations createAlias(String alias) {
    return LocalCleanupConfirmations(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(user_id, recording_id)REFERENCES local_recording_files(user_id, recording_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class LocalCleanupConfirmation extends DataClass
    implements Insertable<LocalCleanupConfirmation> {
  final String token;
  final String userId;
  final String recordingId;
  final String generation;
  final String sha256;
  final int cloudRevision;
  final int expiresAt;
  final String state;
  final int createdAt;
  final int updatedAt;
  const LocalCleanupConfirmation({
    required this.token,
    required this.userId,
    required this.recordingId,
    required this.generation,
    required this.sha256,
    required this.cloudRevision,
    required this.expiresAt,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['token'] = Variable<String>(token);
    map['user_id'] = Variable<String>(userId);
    map['recording_id'] = Variable<String>(recordingId);
    map['generation'] = Variable<String>(generation);
    map['sha256'] = Variable<String>(sha256);
    map['cloud_revision'] = Variable<int>(cloudRevision);
    map['expires_at'] = Variable<int>(expiresAt);
    map['state'] = Variable<String>(state);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  LocalCleanupConfirmationsCompanion toCompanion(bool nullToAbsent) {
    return LocalCleanupConfirmationsCompanion(
      token: Value(token),
      userId: Value(userId),
      recordingId: Value(recordingId),
      generation: Value(generation),
      sha256: Value(sha256),
      cloudRevision: Value(cloudRevision),
      expiresAt: Value(expiresAt),
      state: Value(state),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalCleanupConfirmation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCleanupConfirmation(
      token: serializer.fromJson<String>(json['token']),
      userId: serializer.fromJson<String>(json['user_id']),
      recordingId: serializer.fromJson<String>(json['recording_id']),
      generation: serializer.fromJson<String>(json['generation']),
      sha256: serializer.fromJson<String>(json['sha256']),
      cloudRevision: serializer.fromJson<int>(json['cloud_revision']),
      expiresAt: serializer.fromJson<int>(json['expires_at']),
      state: serializer.fromJson<String>(json['state']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'token': serializer.toJson<String>(token),
      'user_id': serializer.toJson<String>(userId),
      'recording_id': serializer.toJson<String>(recordingId),
      'generation': serializer.toJson<String>(generation),
      'sha256': serializer.toJson<String>(sha256),
      'cloud_revision': serializer.toJson<int>(cloudRevision),
      'expires_at': serializer.toJson<int>(expiresAt),
      'state': serializer.toJson<String>(state),
      'created_at': serializer.toJson<int>(createdAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  LocalCleanupConfirmation copyWith({
    String? token,
    String? userId,
    String? recordingId,
    String? generation,
    String? sha256,
    int? cloudRevision,
    int? expiresAt,
    String? state,
    int? createdAt,
    int? updatedAt,
  }) => LocalCleanupConfirmation(
    token: token ?? this.token,
    userId: userId ?? this.userId,
    recordingId: recordingId ?? this.recordingId,
    generation: generation ?? this.generation,
    sha256: sha256 ?? this.sha256,
    cloudRevision: cloudRevision ?? this.cloudRevision,
    expiresAt: expiresAt ?? this.expiresAt,
    state: state ?? this.state,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalCleanupConfirmation copyWithCompanion(
    LocalCleanupConfirmationsCompanion data,
  ) {
    return LocalCleanupConfirmation(
      token: data.token.present ? data.token.value : this.token,
      userId: data.userId.present ? data.userId.value : this.userId,
      recordingId: data.recordingId.present
          ? data.recordingId.value
          : this.recordingId,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      cloudRevision: data.cloudRevision.present
          ? data.cloudRevision.value
          : this.cloudRevision,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      state: data.state.present ? data.state.value : this.state,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCleanupConfirmation(')
          ..write('token: $token, ')
          ..write('userId: $userId, ')
          ..write('recordingId: $recordingId, ')
          ..write('generation: $generation, ')
          ..write('sha256: $sha256, ')
          ..write('cloudRevision: $cloudRevision, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    token,
    userId,
    recordingId,
    generation,
    sha256,
    cloudRevision,
    expiresAt,
    state,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCleanupConfirmation &&
          other.token == this.token &&
          other.userId == this.userId &&
          other.recordingId == this.recordingId &&
          other.generation == this.generation &&
          other.sha256 == this.sha256 &&
          other.cloudRevision == this.cloudRevision &&
          other.expiresAt == this.expiresAt &&
          other.state == this.state &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalCleanupConfirmationsCompanion
    extends UpdateCompanion<LocalCleanupConfirmation> {
  final Value<String> token;
  final Value<String> userId;
  final Value<String> recordingId;
  final Value<String> generation;
  final Value<String> sha256;
  final Value<int> cloudRevision;
  final Value<int> expiresAt;
  final Value<String> state;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const LocalCleanupConfirmationsCompanion({
    this.token = const Value.absent(),
    this.userId = const Value.absent(),
    this.recordingId = const Value.absent(),
    this.generation = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.cloudRevision = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCleanupConfirmationsCompanion.insert({
    required String token,
    required String userId,
    required String recordingId,
    required String generation,
    required String sha256,
    required int cloudRevision,
    required int expiresAt,
    required String state,
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : token = Value(token),
       userId = Value(userId),
       recordingId = Value(recordingId),
       generation = Value(generation),
       sha256 = Value(sha256),
       cloudRevision = Value(cloudRevision),
       expiresAt = Value(expiresAt),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalCleanupConfirmation> custom({
    Expression<String>? token,
    Expression<String>? userId,
    Expression<String>? recordingId,
    Expression<String>? generation,
    Expression<String>? sha256,
    Expression<int>? cloudRevision,
    Expression<int>? expiresAt,
    Expression<String>? state,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (token != null) 'token': token,
      if (userId != null) 'user_id': userId,
      if (recordingId != null) 'recording_id': recordingId,
      if (generation != null) 'generation': generation,
      if (sha256 != null) 'sha256': sha256,
      if (cloudRevision != null) 'cloud_revision': cloudRevision,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (state != null) 'state': state,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCleanupConfirmationsCompanion copyWith({
    Value<String>? token,
    Value<String>? userId,
    Value<String>? recordingId,
    Value<String>? generation,
    Value<String>? sha256,
    Value<int>? cloudRevision,
    Value<int>? expiresAt,
    Value<String>? state,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalCleanupConfirmationsCompanion(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      recordingId: recordingId ?? this.recordingId,
      generation: generation ?? this.generation,
      sha256: sha256 ?? this.sha256,
      cloudRevision: cloudRevision ?? this.cloudRevision,
      expiresAt: expiresAt ?? this.expiresAt,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (token.present) {
      map['token'] = Variable<String>(token.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (recordingId.present) {
      map['recording_id'] = Variable<String>(recordingId.value);
    }
    if (generation.present) {
      map['generation'] = Variable<String>(generation.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (cloudRevision.present) {
      map['cloud_revision'] = Variable<int>(cloudRevision.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
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
    return (StringBuffer('LocalCleanupConfirmationsCompanion(')
          ..write('token: $token, ')
          ..write('userId: $userId, ')
          ..write('recordingId: $recordingId, ')
          ..write('generation: $generation, ')
          ..write('sha256: $sha256, ')
          ..write('cloudRevision: $cloudRevision, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
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
  late final RecordingFollowups recordingFollowups = RecordingFollowups(this);
  late final Trigger recordingFollowupValidInsert = Trigger(
    'CREATE TRIGGER recording_followup_valid_insert BEFORE INSERT ON recording_followups BEGIN SELECT RAISE (ABORT, \'Invalid metadata followup\') WHERE NOT EXISTS (SELECT 1 FROM local_mutations AS o JOIN local_mutations AS r ON r.op_id = NEW.replacement_op_id JOIN local_mutations AS p ON p.op_id = NEW.predecessor_op_id WHERE o.op_id = NEW.original_op_id AND o.user_id = NEW.user_id AND r.user_id = o.user_id AND p.user_id = o.user_id AND o.entity_type IN (\'RECORDING\', \'SONG\', \'TAG\', \'PLAYLIST\') AND r.entity_type = o.entity_type AND p.entity_type = o.entity_type AND r.entity_id = o.entity_id AND p.entity_id = o.entity_id AND(o.operation = \'PATCH\' OR(o.entity_type = \'PLAYLIST\' AND o.operation = \'PURGE\'))AND r.operation = o.operation AND o.base_revision = 0 AND o.attempt_count = 0 AND o.queue_state = \'PENDING\' AND r.base_revision > 0 AND r.attempt_count = 0 AND r.queue_state = \'PENDING\' AND p.queue_state = \'ACKED\' AND p.attempt_count > 0 AND NEW.logical_order = o."rowid" AND r."rowid" > o."rowid" AND json_extract(p.server_response, \'\$.revision\') = r.base_revision);END',
    'recording_followup_valid_insert',
  );
  late final Trigger recordingFollowupNoUpdate = Trigger(
    'CREATE TRIGGER recording_followup_no_update BEFORE UPDATE ON recording_followups BEGIN SELECT RAISE (ABORT, \'Recording followup evidence is immutable\');END',
    'recording_followup_no_update',
  );
  late final Trigger recordingFollowupNoDelete = Trigger(
    'CREATE TRIGGER recording_followup_no_delete BEFORE DELETE ON recording_followups BEGIN SELECT RAISE (ABORT, \'Recording followup evidence must be retained\');END',
    'recording_followup_no_delete',
  );
  late final Trigger recordingFollowupNoReplace = Trigger(
    'CREATE TRIGGER recording_followup_no_replace BEFORE INSERT ON recording_followups BEGIN SELECT RAISE (ABORT, \'Recording followup evidence cannot be replaced\') WHERE EXISTS (SELECT 1 FROM recording_followups WHERE original_op_id = NEW.original_op_id OR replacement_op_id = NEW.replacement_op_id);END',
    'recording_followup_no_replace',
  );
  late final Trigger recordingFollowupOriginalNoClaim = Trigger(
    'CREATE TRIGGER recording_followup_original_no_claim BEFORE UPDATE OF attempt_count ON local_mutations WHEN NEW.attempt_count > OLD.attempt_count AND EXISTS (SELECT 1 FROM recording_followups WHERE original_op_id = OLD.op_id) BEGIN SELECT RAISE (ABORT, \'Original offline intent cannot be sent after materialization\');END',
    'recording_followup_original_no_claim',
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
  late final SongAliases songAliases = SongAliases(this);
  late final Index songAliasDestination = Index(
    'song_alias_destination',
    'CREATE INDEX song_alias_destination ON song_aliases (canonical_song_id)',
  );
  late final MutationSupersessions mutationSupersessions =
      MutationSupersessions(this);
  late final CanonicalEditIntents canonicalEditIntents = CanonicalEditIntents(
    this,
  );
  late final Index canonicalIntentTarget = Index(
    'canonical_intent_target',
    'CREATE INDEX canonical_intent_target ON canonical_edit_intents (entity_type, entity_id, state)',
  );
  late final MutationMappingHolds mutationMappingHolds = MutationMappingHolds(
    this,
  );
  late final Index mutationMappingActiveHolds = Index(
    'mutation_mapping_active_holds',
    'CREATE INDEX mutation_mapping_active_holds ON mutation_mapping_holds (op_id, released_at)',
  );
  late final Trigger songAliasValidInsert = Trigger(
    'CREATE TRIGGER song_alias_valid_insert BEFORE INSERT ON song_aliases BEGIN SELECT RAISE (ABORT, \'Alias requires its original song CREATE\') WHERE NOT EXISTS (SELECT 1 FROM local_mutations AS m WHERE m.op_id = NEW.mapping_op_id AND m.user_id = NEW.user_id AND m.entity_type = \'SONG\' AND m.entity_id = NEW.source_song_id AND m.operation = \'CREATE\');SELECT RAISE (ABORT, \'Song alias cycle\') WHERE EXISTS (WITH RECURSIVE destinations (id) AS (SELECT NEW.canonical_song_id UNION SELECT a.canonical_song_id FROM song_aliases AS a JOIN destinations AS d ON a.source_song_id = d.id) SELECT 1 FROM destinations WHERE id = NEW.source_song_id);END',
    'song_alias_valid_insert',
  );
  late final Trigger songAliasNoUpdate = Trigger(
    'CREATE TRIGGER song_alias_no_update BEFORE UPDATE ON song_aliases BEGIN SELECT RAISE (ABORT, \'Song aliases and receipts are immutable\');END',
    'song_alias_no_update',
  );
  late final Trigger songAliasNoDelete = Trigger(
    'CREATE TRIGGER song_alias_no_delete BEFORE DELETE ON song_aliases BEGIN SELECT RAISE (ABORT, \'Song alias evidence must be retained\');END',
    'song_alias_no_delete',
  );
  late final Trigger mutationSupersessionValidInsert = Trigger(
    'CREATE TRIGGER mutation_supersession_valid_insert BEFORE INSERT ON mutation_supersessions BEGIN SELECT RAISE (ABORT, \'Cannot prepend a frozen replacement chain\') WHERE EXISTS (SELECT 1 FROM mutation_supersessions WHERE original_op_id = NEW.replacement_op_id);SELECT RAISE (ABORT, \'Invalid replacement order\') WHERE NOT EXISTS (SELECT 1 FROM local_mutations AS original JOIN local_mutations AS replacement ON replacement.op_id = NEW.replacement_op_id WHERE original.op_id = NEW.original_op_id AND replacement."rowid" > original."rowid");SELECT RAISE (ABORT, \'Replacement must inherit original logical order\') WHERE NEW.order_root_op_id IS NOT COALESCE((SELECT order_root_op_id FROM mutation_supersessions WHERE replacement_op_id = NEW.original_op_id), NEW.original_op_id) OR NEW.logical_order IS NOT COALESCE((SELECT logical_order FROM mutation_supersessions WHERE replacement_op_id = NEW.original_op_id), (SELECT "rowid" FROM local_mutations WHERE op_id = NEW.original_op_id));END',
    'mutation_supersession_valid_insert',
  );
  late final Trigger mutationSupersessionNoUpdate = Trigger(
    'CREATE TRIGGER mutation_supersession_no_update BEFORE UPDATE ON mutation_supersessions BEGIN SELECT RAISE (ABORT, \'Mutation supersessions are immutable\');END',
    'mutation_supersession_no_update',
  );
  late final Trigger mutationSupersessionNoDelete = Trigger(
    'CREATE TRIGGER mutation_supersession_no_delete BEFORE DELETE ON mutation_supersessions BEGIN SELECT RAISE (ABORT, \'Mutation supersession history must be retained\');END',
    'mutation_supersession_no_delete',
  );
  late final Trigger supersededMutationNoClaim = Trigger(
    'CREATE TRIGGER superseded_mutation_no_claim BEFORE UPDATE OF attempt_count ON local_mutations WHEN NEW.attempt_count > OLD.attempt_count AND EXISTS (SELECT 1 FROM mutation_supersessions WHERE original_op_id = OLD.op_id) BEGIN SELECT RAISE (ABORT, \'Superseded mutation cannot be claimed\');END',
    'superseded_mutation_no_claim',
  );
  late final Trigger canonicalIntentEvidenceImmutable = Trigger(
    'CREATE TRIGGER canonical_intent_evidence_immutable BEFORE UPDATE ON canonical_edit_intents WHEN NEW.intent_id IS NOT OLD.intent_id OR NEW.user_id IS NOT OLD.user_id OR NEW.mapping_source_id IS NOT OLD.mapping_source_id OR NEW.intent_key IS NOT OLD.intent_key OR NEW.kind IS NOT OLD.kind OR NEW.entity_type IS NOT OLD.entity_type OR NEW.entity_id IS NOT OLD.entity_id OR NEW.origin_op_id IS NOT OLD.origin_op_id OR NEW.evidence_json IS NOT OLD.evidence_json OR NEW.created_at IS NOT OLD.created_at OR OLD.state = \'RESOLVED\' OR(OLD.state = \'QUEUED\' AND NEW.state <> \'RESOLVED\')BEGIN SELECT RAISE (ABORT, \'Canonical intent evidence cannot be rewritten\');END',
    'canonical_intent_evidence_immutable',
  );
  late final Trigger canonicalIntentNoDelete = Trigger(
    'CREATE TRIGGER canonical_intent_no_delete BEFORE DELETE ON canonical_edit_intents BEGIN SELECT RAISE (ABORT, \'Canonical edit evidence must be retained\');END',
    'canonical_intent_no_delete',
  );
  late final Trigger mappingHoldReleaseOnly = Trigger(
    'CREATE TRIGGER mapping_hold_release_only BEFORE UPDATE ON mutation_mapping_holds WHEN NEW.op_id IS NOT OLD.op_id OR NEW.mapping_source_id IS NOT OLD.mapping_source_id OR NEW.user_id IS NOT OLD.user_id OR NEW.reason IS NOT OLD.reason OR NEW.disposition IS NOT OLD.disposition OR NEW.intent_id IS NOT OLD.intent_id OR NEW.created_at IS NOT OLD.created_at OR OLD.released_at IS NOT NULL OR NEW.released_at IS NULL BEGIN SELECT RAISE (ABORT, \'Mapping hold permits one evidenced release only\');END',
    'mapping_hold_release_only',
  );
  late final Trigger mappingHoldNoDelete = Trigger(
    'CREATE TRIGGER mapping_hold_no_delete BEFORE DELETE ON mutation_mapping_holds BEGIN SELECT RAISE (ABORT, \'Mapping hold history must be retained\');END',
    'mapping_hold_no_delete',
  );
  late final Trigger songAliasNoReplace = Trigger(
    'CREATE TRIGGER song_alias_no_replace BEFORE INSERT ON song_aliases BEGIN SELECT RAISE (ABORT, \'Preserved evidence cannot be replaced\') WHERE EXISTS (SELECT 1 FROM song_aliases WHERE source_song_id = NEW.source_song_id OR mapping_op_id = NEW.mapping_op_id);END',
    'song_alias_no_replace',
  );
  late final Trigger mutationSupersessionNoReplace = Trigger(
    'CREATE TRIGGER mutation_supersession_no_replace BEFORE INSERT ON mutation_supersessions BEGIN SELECT RAISE (ABORT, \'Preserved evidence cannot be replaced\') WHERE EXISTS (SELECT 1 FROM mutation_supersessions WHERE original_op_id = NEW.original_op_id OR replacement_op_id = NEW.replacement_op_id);END',
    'mutation_supersession_no_replace',
  );
  late final Trigger canonicalIntentNoReplace = Trigger(
    'CREATE TRIGGER canonical_intent_no_replace BEFORE INSERT ON canonical_edit_intents BEGIN SELECT RAISE (ABORT, \'Preserved evidence cannot be replaced\') WHERE EXISTS (SELECT 1 FROM canonical_edit_intents WHERE intent_id = NEW.intent_id OR(mapping_source_id = NEW.mapping_source_id AND intent_key = NEW.intent_key));END',
    'canonical_intent_no_replace',
  );
  late final Trigger mappingHoldNoReplace = Trigger(
    'CREATE TRIGGER mapping_hold_no_replace BEFORE INSERT ON mutation_mapping_holds BEGIN SELECT RAISE (ABORT, \'Preserved evidence cannot be replaced\') WHERE EXISTS (SELECT 1 FROM mutation_mapping_holds WHERE op_id = NEW.op_id AND mapping_source_id = NEW.mapping_source_id AND reason = NEW.reason);END',
    'mapping_hold_no_replace',
  );
  late final Trigger mutationRowidImmutable = Trigger(
    'CREATE TRIGGER mutation_rowid_immutable BEFORE UPDATE ON local_mutations WHEN NEW."rowid" IS NOT OLD."rowid" BEGIN SELECT RAISE (ABORT, \'Mutation rowid must remain immutable\');END',
    'mutation_rowid_immutable',
  );
  late final Trigger mutationHistoryNoReplace = Trigger(
    'CREATE TRIGGER mutation_history_no_replace BEFORE INSERT ON local_mutations WHEN EXISTS (SELECT 1 FROM local_mutations WHERE op_id = NEW.op_id OR(NEW."rowid" <> -1 AND "rowid" = NEW."rowid")) BEGIN SELECT RAISE (ABORT, \'Mutation history cannot be replaced\');END',
    'mutation_history_no_replace',
  );
  late final Trigger mutationOrderPositive = Trigger(
    'CREATE TRIGGER mutation_order_positive AFTER INSERT ON local_mutations WHEN NEW."rowid" <= 0 BEGIN SELECT RAISE (ABORT, \'New mutation order must be positive\');END',
    'mutation_order_positive',
  );
  late final Trigger mutationHistoryNoDelete = Trigger(
    'CREATE TRIGGER mutation_history_no_delete BEFORE DELETE ON local_mutations BEGIN SELECT RAISE (ABORT, \'Mutation ordering history must be retained\');END',
    'mutation_history_no_delete',
  );
  late final SnapshotDownloads snapshotDownloads = SnapshotDownloads(this);
  late final SnapshotDownloadRows snapshotDownloadRows = SnapshotDownloadRows(
    this,
  );
  late final SnapshotDownloadProgress snapshotDownloadProgress =
      SnapshotDownloadProgress(this);
  late final SnapshotBaseline snapshotBaseline = SnapshotBaseline(this);
  late final Trigger snapshotDownloadIdentity = Trigger(
    'CREATE TRIGGER snapshot_download_identity BEFORE UPDATE ON snapshot_downloads WHEN NEW.snapshot_token IS NOT OLD.snapshot_token OR NEW.user_id IS NOT OLD.user_id OR NEW.manifest_json IS NOT OLD.manifest_json OR NEW.snapshot_cursor IS NOT OLD.snapshot_cursor OR NEW.expires_at IS NOT OLD.expires_at OR NEW.created_at IS NOT OLD.created_at OR NOT((OLD.state = \'RECEIVING\' AND NEW.state = \'VERIFIED\')OR(OLD.state = \'VERIFIED\' AND NEW.state = \'APPLIED\'))BEGIN SELECT RAISE (ABORT, \'Snapshot manifest and forward state are immutable\');END',
    'snapshot_download_identity',
  );
  late final Trigger snapshotDownloadNoReplace = Trigger(
    'CREATE TRIGGER snapshot_download_no_replace BEFORE INSERT ON snapshot_downloads WHEN NEW.state <> \'RECEIVING\' OR EXISTS (SELECT 1 FROM snapshot_downloads WHERE snapshot_token = NEW.snapshot_token) BEGIN SELECT RAISE (ABORT, \'Snapshot manifest cannot be replaced\');END',
    'snapshot_download_no_replace',
  );
  late final Trigger snapshotRowInsert = Trigger(
    'CREATE TRIGGER snapshot_row_insert BEFORE INSERT ON snapshot_download_rows WHEN NOT EXISTS (SELECT 1 FROM snapshot_downloads WHERE snapshot_token = NEW.snapshot_token AND user_id = NEW.user_id AND state = \'RECEIVING\') OR EXISTS (SELECT 1 FROM snapshot_download_rows WHERE snapshot_token = NEW.snapshot_token AND entity = NEW.entity AND ordinal = NEW.ordinal) BEGIN SELECT RAISE (ABORT, \'Only new receiving snapshot rows may be inserted\');END',
    'snapshot_row_insert',
  );
  late final Trigger snapshotRowNoUpdate = Trigger(
    'CREATE TRIGGER snapshot_row_no_update BEFORE UPDATE ON snapshot_download_rows BEGIN SELECT RAISE (ABORT, \'Snapshot rows are immutable\');END',
    'snapshot_row_no_update',
  );
  late final Trigger snapshotRowDelete = Trigger(
    'CREATE TRIGGER snapshot_row_delete BEFORE DELETE ON snapshot_download_rows WHEN EXISTS (SELECT 1 FROM snapshot_downloads WHERE snapshot_token = OLD.snapshot_token AND state <> \'RECEIVING\') BEGIN SELECT RAISE (ABORT, \'Verified snapshot rows must remain intact\');END',
    'snapshot_row_delete',
  );
  late final Trigger snapshotProgressInsert = Trigger(
    'CREATE TRIGGER snapshot_progress_insert BEFORE INSERT ON snapshot_download_progress WHEN NOT EXISTS (SELECT 1 FROM snapshot_downloads WHERE snapshot_token = NEW.snapshot_token AND state = \'RECEIVING\') OR EXISTS (SELECT 1 FROM snapshot_download_progress WHERE snapshot_token = NEW.snapshot_token AND entity = NEW.entity) BEGIN SELECT RAISE (ABORT, \'Snapshot progress cannot be replaced\');END',
    'snapshot_progress_insert',
  );
  late final Trigger snapshotProgressUpdate = Trigger(
    'CREATE TRIGGER snapshot_progress_update BEFORE UPDATE ON snapshot_download_progress WHEN NEW.snapshot_token IS NOT OLD.snapshot_token OR NEW.entity IS NOT OLD.entity OR OLD.finished = 1 OR NEW.last_ordinal <= OLD.last_ordinal OR NOT EXISTS (SELECT 1 FROM snapshot_downloads WHERE snapshot_token = NEW.snapshot_token AND state = \'RECEIVING\') BEGIN SELECT RAISE (ABORT, \'Snapshot progress must advance while receiving\');END',
    'snapshot_progress_update',
  );
  late final Trigger snapshotBaselineInsert = Trigger(
    'CREATE TRIGGER snapshot_baseline_insert BEFORE INSERT ON snapshot_baseline WHEN NOT EXISTS (SELECT 1 FROM snapshot_downloads WHERE snapshot_token = NEW.snapshot_token AND user_id = NEW.user_id AND state = \'APPLIED\') BEGIN SELECT RAISE (ABORT, \'Only an applied snapshot may become baseline\');END',
    'snapshot_baseline_insert',
  );
  late final Trigger snapshotBaselineUpdate = Trigger(
    'CREATE TRIGGER snapshot_baseline_update BEFORE UPDATE ON snapshot_baseline WHEN NEW.singleton IS NOT OLD.singleton OR NEW.user_id IS NOT OLD.user_id OR NOT EXISTS (SELECT 1 FROM snapshot_downloads WHERE snapshot_token = NEW.snapshot_token AND user_id = NEW.user_id AND state = \'APPLIED\') BEGIN SELECT RAISE (ABORT, \'Only an applied snapshot may become baseline\');END',
    'snapshot_baseline_update',
  );
  late final MutationConflictResolutions mutationConflictResolutions =
      MutationConflictResolutions(this);
  late final Trigger conflictResolutionValidInsert = Trigger(
    'CREATE TRIGGER conflict_resolution_valid_insert BEFORE INSERT ON mutation_conflict_resolutions BEGIN SELECT RAISE (ABORT, \'Resolution requires the current revision conflict\') WHERE NOT EXISTS (SELECT 1 FROM local_mutations AS m WHERE m.op_id = NEW.original_op_id AND m.user_id = NEW.user_id AND m.operation = \'PATCH\' AND m.entity_type IN (\'SONG\', \'RECORDING\', \'TAG\') AND m.queue_state = \'CONFLICT\' AND m.attempt_count = NEW.original_attempt_count AND json_extract(m.server_response, \'\$.status\') = 409 AND json_extract(m.server_response, \'\$.code\') = \'REVISION_CONFLICT\' AND json_type(m.server_response, \'\$.current.revision\') = \'integer\' AND NEW.resolved_revision >= json_extract(m.server_response, \'\$.current.revision\') AND NEW.resolved_revision > m.base_revision AND json_extract(NEW.server_snapshot, \'\$.id\') = m.entity_id AND(json_type(NEW.server_snapshot, \'\$.user_id\') IS NULL OR json_extract(NEW.server_snapshot, \'\$.user_id\') = NEW.user_id));SELECT RAISE (ABORT, \'Resolution choice must be explicit\') WHERE EXISTS (SELECT 1 FROM json_each(NEW.choices)AS choice WHERE choice.type <> \'text\' OR choice.value NOT IN (\'LOCAL\', \'SERVER\'));SELECT RAISE (ABORT, \'Mapping evidence must be resolved separately\') WHERE EXISTS (SELECT 1 FROM mutation_mapping_holds WHERE op_id = NEW.original_op_id AND released_at IS NULL) OR EXISTS (SELECT 1 FROM mutation_supersessions WHERE original_op_id = NEW.original_op_id OR replacement_op_id = NEW.original_op_id);SELECT RAISE (ABORT, \'Invalid conflict replacement\') WHERE NEW.replacement_op_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM local_mutations AS original JOIN local_mutations AS replacement ON replacement.op_id = NEW.replacement_op_id WHERE original.op_id = NEW.original_op_id AND replacement.user_id = NEW.user_id AND replacement.entity_type = original.entity_type AND replacement.entity_id = original.entity_id AND replacement.operation = \'PATCH\' AND replacement.queue_state = \'PENDING\' AND replacement.attempt_count = 0 AND replacement."rowid" > original."rowid" AND replacement.base_revision = NEW.resolved_revision AND replacement.base_payload = NEW.server_snapshot AND json_type(replacement.payload, \'\$.base_revision\') = \'integer\' AND json_extract(replacement.payload, \'\$.base_revision\') = NEW.resolved_revision AND NOT EXISTS (SELECT 1 FROM mutation_wire_requests WHERE op_id = replacement.op_id));SELECT RAISE (ABORT, \'Conflict resolution order must be inherited\') WHERE NEW.order_root_op_id IS NOT COALESCE((SELECT order_root_op_id FROM mutation_conflict_resolutions WHERE replacement_op_id = NEW.original_op_id), NEW.original_op_id) OR NEW.logical_order IS NOT COALESCE((SELECT logical_order FROM mutation_conflict_resolutions WHERE replacement_op_id = NEW.original_op_id), (SELECT logical_order FROM recording_followups WHERE replacement_op_id = NEW.original_op_id), (SELECT "rowid" FROM local_mutations WHERE op_id = NEW.original_op_id));SELECT RAISE (ABORT, \'Cannot prepend a resolution chain\') WHERE EXISTS (SELECT 1 FROM mutation_conflict_resolutions WHERE original_op_id = NEW.replacement_op_id);END',
    'conflict_resolution_valid_insert',
  );
  late final Trigger conflictResolutionNoReplace = Trigger(
    'CREATE TRIGGER conflict_resolution_no_replace BEFORE INSERT ON mutation_conflict_resolutions WHEN EXISTS (SELECT 1 FROM mutation_conflict_resolutions WHERE original_op_id = NEW.original_op_id OR(NEW.replacement_op_id IS NOT NULL AND replacement_op_id = NEW.replacement_op_id)) BEGIN SELECT RAISE (ABORT, \'Conflict resolution evidence cannot be replaced\');END',
    'conflict_resolution_no_replace',
  );
  late final Trigger conflictResolutionNoUpdate = Trigger(
    'CREATE TRIGGER conflict_resolution_no_update BEFORE UPDATE ON mutation_conflict_resolutions BEGIN SELECT RAISE (ABORT, \'Conflict resolution evidence is immutable\');END',
    'conflict_resolution_no_update',
  );
  late final Trigger conflictResolutionNoDelete = Trigger(
    'CREATE TRIGGER conflict_resolution_no_delete BEFORE DELETE ON mutation_conflict_resolutions BEGIN SELECT RAISE (ABORT, \'Conflict resolution evidence must be retained\');END',
    'conflict_resolution_no_delete',
  );
  late final Trigger resolvedMutationNoClaim = Trigger(
    'CREATE TRIGGER resolved_mutation_no_claim BEFORE UPDATE OF attempt_count ON local_mutations WHEN NEW.attempt_count > OLD.attempt_count AND EXISTS (SELECT 1 FROM mutation_conflict_resolutions WHERE original_op_id = OLD.op_id) BEGIN SELECT RAISE (ABORT, \'Resolved original operation cannot be retried\');END',
    'resolved_mutation_no_claim',
  );
  late final PendingEditResolutions pendingEditResolutions =
      PendingEditResolutions(this);
  late final Trigger pendingEditValidInsert = Trigger(
    'CREATE TRIGGER pending_edit_valid_insert BEFORE INSERT ON pending_edit_resolutions BEGIN SELECT RAISE (ABORT, \'Pending review requires an unsent original\') WHERE NOT EXISTS (SELECT 1 FROM local_mutations AS m WHERE m.op_id = NEW.original_op_id AND m.user_id = NEW.user_id AND m.operation = \'PATCH\' AND m.entity_type IN (\'SONG\', \'RECORDING\', \'TAG\') AND m.queue_state = \'PENDING\' AND m.attempt_count = 0 AND m.server_response IS NULL AND m.base_revision > 0 AND NEW.logical_order = m."rowid" AND json_extract(NEW.server_snapshot, \'\$.id\') = m.entity_id AND json_type(NEW.server_snapshot, \'\$.revision\') = \'integer\' AND json_extract(NEW.server_snapshot, \'\$.revision\') > m.base_revision AND(json_type(NEW.server_snapshot, \'\$.user_id\') IS NULL OR json_extract(NEW.server_snapshot, \'\$.user_id\') = NEW.user_id)AND NOT EXISTS (SELECT 1 FROM mutation_wire_requests WHERE op_id = m.op_id) AND NOT EXISTS (SELECT 1 FROM mutation_mapping_holds WHERE op_id = m.op_id AND released_at IS NULL));SELECT RAISE (ABORT, \'Invalid pending review choice\') WHERE EXISTS (SELECT 1 FROM json_each(NEW.choices)AS choice WHERE choice.type <> \'text\' OR choice.value NOT IN (\'LOCAL\', \'SERVER\'));SELECT RAISE (ABORT, \'Invalid pending review replacement\') WHERE NEW.replacement_op_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM local_mutations AS o JOIN local_mutations AS n ON n.op_id = NEW.replacement_op_id WHERE o.op_id = NEW.original_op_id AND n.user_id = NEW.user_id AND n.entity_type = o.entity_type AND n.entity_id = o.entity_id AND n.operation = \'PATCH\' AND n.queue_state = \'PENDING\' AND n.attempt_count = 0 AND n."rowid" > o."rowid" AND n.base_revision = json_extract(NEW.server_snapshot, \'\$.revision\') AND n.base_payload = NEW.server_snapshot AND json_extract(n.payload, \'\$.base_revision\') = n.base_revision AND NOT EXISTS (SELECT 1 FROM mutation_wire_requests WHERE op_id = n.op_id));END',
    'pending_edit_valid_insert',
  );
  late final Trigger pendingEditNoReplace = Trigger(
    'CREATE TRIGGER pending_edit_no_replace BEFORE INSERT ON pending_edit_resolutions WHEN EXISTS (SELECT 1 FROM pending_edit_resolutions WHERE original_op_id = NEW.original_op_id OR(NEW.replacement_op_id IS NOT NULL AND replacement_op_id = NEW.replacement_op_id)) BEGIN SELECT RAISE (ABORT, \'Pending review evidence cannot be replaced\');END',
    'pending_edit_no_replace',
  );
  late final Trigger pendingEditNoUpdate = Trigger(
    'CREATE TRIGGER pending_edit_no_update BEFORE UPDATE ON pending_edit_resolutions BEGIN SELECT RAISE (ABORT, \'Pending review evidence is immutable\');END',
    'pending_edit_no_update',
  );
  late final Trigger pendingEditNoDelete = Trigger(
    'CREATE TRIGGER pending_edit_no_delete BEFORE DELETE ON pending_edit_resolutions BEGIN SELECT RAISE (ABORT, \'Pending review evidence must be retained\');END',
    'pending_edit_no_delete',
  );
  late final Trigger pendingEditOriginalNoClaim = Trigger(
    'CREATE TRIGGER pending_edit_original_no_claim BEFORE UPDATE OF attempt_count ON local_mutations WHEN NEW.attempt_count > OLD.attempt_count AND EXISTS (SELECT 1 FROM pending_edit_resolutions WHERE original_op_id = OLD.op_id) BEGIN SELECT RAISE (ABORT, \'Reviewed pending original cannot be retried\');END',
    'pending_edit_original_no_claim',
  );
  late final LocalUploadQueue localUploadQueue = LocalUploadQueue(this);
  late final Index localUploadReady = Index(
    'local_upload_ready',
    'CREATE INDEX local_upload_ready ON local_upload_queue (phase, next_attempt_at, created_at)',
  );
  late final Trigger localUploadIdentity = Trigger(
    'CREATE TRIGGER local_upload_identity BEFORE UPDATE ON local_upload_queue WHEN NEW.recording_id <> OLD.recording_id OR NEW.user_id <> OLD.user_id OR NEW.operation_id <> OLD.operation_id OR NEW.expected_size <> OLD.expected_size OR NEW.sha256 <> OLD.sha256 OR NEW.created_at <> OLD.created_at OR NEW.automatic_retries < OLD.automatic_retries OR NEW.attempt_count < OLD.attempt_count BEGIN SELECT RAISE (ABORT, \'Upload identity and retry budget are immutable\');END',
    'local_upload_identity',
  );
  late final LocalCleanupConfirmations localCleanupConfirmations =
      LocalCleanupConfirmations(this);
  late final Index localCleanupRecording = Index(
    'local_cleanup_recording',
    'CREATE INDEX local_cleanup_recording ON local_cleanup_confirmations (recording_id, state)',
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
    recordingFollowups,
    recordingFollowupValidInsert,
    recordingFollowupNoUpdate,
    recordingFollowupNoDelete,
    recordingFollowupNoReplace,
    recordingFollowupOriginalNoClaim,
    mutationWireRequests,
    mutationWireRequestImmutable,
    mutationRetryControls,
    mutationRetryBudgetMonotonic,
    songAliases,
    songAliasDestination,
    mutationSupersessions,
    canonicalEditIntents,
    canonicalIntentTarget,
    mutationMappingHolds,
    mutationMappingActiveHolds,
    songAliasValidInsert,
    songAliasNoUpdate,
    songAliasNoDelete,
    mutationSupersessionValidInsert,
    mutationSupersessionNoUpdate,
    mutationSupersessionNoDelete,
    supersededMutationNoClaim,
    canonicalIntentEvidenceImmutable,
    canonicalIntentNoDelete,
    mappingHoldReleaseOnly,
    mappingHoldNoDelete,
    songAliasNoReplace,
    mutationSupersessionNoReplace,
    canonicalIntentNoReplace,
    mappingHoldNoReplace,
    mutationRowidImmutable,
    mutationHistoryNoReplace,
    mutationOrderPositive,
    mutationHistoryNoDelete,
    snapshotDownloads,
    snapshotDownloadRows,
    snapshotDownloadProgress,
    snapshotBaseline,
    snapshotDownloadIdentity,
    snapshotDownloadNoReplace,
    snapshotRowInsert,
    snapshotRowNoUpdate,
    snapshotRowDelete,
    snapshotProgressInsert,
    snapshotProgressUpdate,
    snapshotBaselineInsert,
    snapshotBaselineUpdate,
    mutationConflictResolutions,
    conflictResolutionValidInsert,
    conflictResolutionNoReplace,
    conflictResolutionNoUpdate,
    conflictResolutionNoDelete,
    resolvedMutationNoClaim,
    pendingEditResolutions,
    pendingEditValidInsert,
    pendingEditNoReplace,
    pendingEditNoUpdate,
    pendingEditNoDelete,
    pendingEditOriginalNoClaim,
    localUploadQueue,
    localUploadReady,
    localUploadIdentity,
    localCleanupConfirmations,
    localCleanupRecording,
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
        'recording_followups',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recording_followups',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recording_followups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recording_followups',
        limitUpdateKind: UpdateKind.insert,
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
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'song_aliases',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'song_aliases',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'song_aliases',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_supersessions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_supersessions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_supersessions',
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
        'canonical_edit_intents',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'canonical_edit_intents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_mapping_holds',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_mapping_holds',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'song_aliases',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_supersessions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'canonical_edit_intents',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_mapping_holds',
        limitUpdateKind: UpdateKind.insert,
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
        'local_mutations',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_mutations',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_mutations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_downloads',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('snapshot_download_rows', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_downloads',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('snapshot_download_progress', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_downloads',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_downloads',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_download_rows',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_download_rows',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_download_rows',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_download_progress',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_download_progress',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_baseline',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'snapshot_baseline',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_conflict_resolutions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_conflict_resolutions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_conflict_resolutions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mutation_conflict_resolutions',
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
        'pending_edit_resolutions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'pending_edit_resolutions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'pending_edit_resolutions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'pending_edit_resolutions',
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
        'local_upload_queue',
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

  static MultiTypedResultKey<RecordingFollowups, List<RecordingFollowup>>
  _recordingFollowupsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.recordingFollowups,
        aliasName: 'local_account__user_id__recording_followups__user_id',
      );

  $RecordingFollowupsProcessedTableManager get recordingFollowupsRefs {
    final manager =
        $RecordingFollowupsTableManager($_db, $_db.recordingFollowups).filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _recordingFollowupsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<SongAliases, List<SongAliase>>
  _songAliasesRefsTable(_$AccountDatabase db) => MultiTypedResultKey.fromTable(
    db.songAliases,
    aliasName: 'local_account__user_id__song_aliases__user_id',
  );

  $SongAliasesProcessedTableManager get songAliasesRefs {
    final manager = $SongAliasesTableManager($_db, $_db.songAliases).filter(
      (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_songAliasesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<MutationSupersessions, List<MutationSupersession>>
  _mutationSupersessionsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mutationSupersessions,
        aliasName: 'local_account__user_id__mutation_supersessions__user_id',
      );

  $MutationSupersessionsProcessedTableManager get mutationSupersessionsRefs {
    final manager =
        $MutationSupersessionsTableManager(
          $_db,
          $_db.mutationSupersessions,
        ).filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _mutationSupersessionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<CanonicalEditIntents, List<CanonicalEditIntent>>
  _canonicalEditIntentsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.canonicalEditIntents,
        aliasName: 'local_account__user_id__canonical_edit_intents__user_id',
      );

  $CanonicalEditIntentsProcessedTableManager get canonicalEditIntentsRefs {
    final manager =
        $CanonicalEditIntentsTableManager(
          $_db,
          $_db.canonicalEditIntents,
        ).filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _canonicalEditIntentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<MutationMappingHolds, List<MutationMappingHold>>
  _mutationMappingHoldsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mutationMappingHolds,
        aliasName: 'local_account__user_id__mutation_mapping_holds__user_id',
      );

  $MutationMappingHoldsProcessedTableManager get mutationMappingHoldsRefs {
    final manager =
        $MutationMappingHoldsTableManager(
          $_db,
          $_db.mutationMappingHolds,
        ).filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _mutationMappingHoldsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<SnapshotDownloads, List<SnapshotDownload>>
  _snapshotDownloadsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.snapshotDownloads,
        aliasName: 'local_account__user_id__snapshot_downloads__user_id',
      );

  $SnapshotDownloadsProcessedTableManager get snapshotDownloadsRefs {
    final manager = $SnapshotDownloadsTableManager($_db, $_db.snapshotDownloads)
        .filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _snapshotDownloadsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<SnapshotDownloadRows, List<SnapshotDownloadRow>>
  _snapshotDownloadRowsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.snapshotDownloadRows,
        aliasName: 'local_account__user_id__snapshot_download_rows__user_id',
      );

  $SnapshotDownloadRowsProcessedTableManager get snapshotDownloadRowsRefs {
    final manager =
        $SnapshotDownloadRowsTableManager(
          $_db,
          $_db.snapshotDownloadRows,
        ).filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _snapshotDownloadRowsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<SnapshotBaseline, List<SnapshotBaselineData>>
  _snapshotBaselineRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.snapshotBaseline,
        aliasName: 'local_account__user_id__snapshot_baseline__user_id',
      );

  $SnapshotBaselineProcessedTableManager get snapshotBaselineRefs {
    final manager = $SnapshotBaselineTableManager($_db, $_db.snapshotBaseline)
        .filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _snapshotBaselineRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    MutationConflictResolutions,
    List<MutationConflictResolution>
  >
  _mutationConflictResolutionsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mutationConflictResolutions,
        aliasName:
            'local_account__user_id__mutation_conflict_resolutions__user_id',
      );

  $MutationConflictResolutionsProcessedTableManager
  get mutationConflictResolutionsRefs {
    final manager =
        $MutationConflictResolutionsTableManager(
          $_db,
          $_db.mutationConflictResolutions,
        ).filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _mutationConflictResolutionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    PendingEditResolutions,
    List<PendingEditResolution>
  >
  _pendingEditResolutionsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.pendingEditResolutions,
        aliasName: 'local_account__user_id__pending_edit_resolutions__user_id',
      );

  $PendingEditResolutionsProcessedTableManager get pendingEditResolutionsRefs {
    final manager =
        $PendingEditResolutionsTableManager(
          $_db,
          $_db.pendingEditResolutions,
        ).filter(
          (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _pendingEditResolutionsRefsTable($_db),
    );
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

  Expression<bool> recordingFollowupsRefs(
    Expression<bool> Function($RecordingFollowupsFilterComposer f) f,
  ) {
    final $RecordingFollowupsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.recordingFollowups,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RecordingFollowupsFilterComposer(
            $db: $db,
            $table: $db.recordingFollowups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> songAliasesRefs(
    Expression<bool> Function($SongAliasesFilterComposer f) f,
  ) {
    final $SongAliasesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesFilterComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mutationSupersessionsRefs(
    Expression<bool> Function($MutationSupersessionsFilterComposer f) f,
  ) {
    final $MutationSupersessionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.mutationSupersessions,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationSupersessionsFilterComposer(
            $db: $db,
            $table: $db.mutationSupersessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> canonicalEditIntentsRefs(
    Expression<bool> Function($CanonicalEditIntentsFilterComposer f) f,
  ) {
    final $CanonicalEditIntentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.canonicalEditIntents,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CanonicalEditIntentsFilterComposer(
            $db: $db,
            $table: $db.canonicalEditIntents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mutationMappingHoldsRefs(
    Expression<bool> Function($MutationMappingHoldsFilterComposer f) f,
  ) {
    final $MutationMappingHoldsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.mutationMappingHolds,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationMappingHoldsFilterComposer(
            $db: $db,
            $table: $db.mutationMappingHolds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> snapshotDownloadsRefs(
    Expression<bool> Function($SnapshotDownloadsFilterComposer f) f,
  ) {
    final $SnapshotDownloadsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.snapshotDownloads,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SnapshotDownloadsFilterComposer(
            $db: $db,
            $table: $db.snapshotDownloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> snapshotDownloadRowsRefs(
    Expression<bool> Function($SnapshotDownloadRowsFilterComposer f) f,
  ) {
    final $SnapshotDownloadRowsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.snapshotDownloadRows,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SnapshotDownloadRowsFilterComposer(
            $db: $db,
            $table: $db.snapshotDownloadRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> snapshotBaselineRefs(
    Expression<bool> Function($SnapshotBaselineFilterComposer f) f,
  ) {
    final $SnapshotBaselineFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.snapshotBaseline,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SnapshotBaselineFilterComposer(
            $db: $db,
            $table: $db.snapshotBaseline,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mutationConflictResolutionsRefs(
    Expression<bool> Function($MutationConflictResolutionsFilterComposer f) f,
  ) {
    final $MutationConflictResolutionsFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.userId,
          referencedTable: $db.mutationConflictResolutions,
          getReferencedColumn: (t) => t.userId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $MutationConflictResolutionsFilterComposer(
                $db: $db,
                $table: $db.mutationConflictResolutions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> pendingEditResolutionsRefs(
    Expression<bool> Function($PendingEditResolutionsFilterComposer f) f,
  ) {
    final $PendingEditResolutionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.pendingEditResolutions,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $PendingEditResolutionsFilterComposer(
            $db: $db,
            $table: $db.pendingEditResolutions,
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

  Expression<T> recordingFollowupsRefs<T extends Object>(
    Expression<T> Function($RecordingFollowupsAnnotationComposer a) f,
  ) {
    final $RecordingFollowupsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.recordingFollowups,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RecordingFollowupsAnnotationComposer(
            $db: $db,
            $table: $db.recordingFollowups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> songAliasesRefs<T extends Object>(
    Expression<T> Function($SongAliasesAnnotationComposer a) f,
  ) {
    final $SongAliasesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesAnnotationComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mutationSupersessionsRefs<T extends Object>(
    Expression<T> Function($MutationSupersessionsAnnotationComposer a) f,
  ) {
    final $MutationSupersessionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.mutationSupersessions,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationSupersessionsAnnotationComposer(
            $db: $db,
            $table: $db.mutationSupersessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> canonicalEditIntentsRefs<T extends Object>(
    Expression<T> Function($CanonicalEditIntentsAnnotationComposer a) f,
  ) {
    final $CanonicalEditIntentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.canonicalEditIntents,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CanonicalEditIntentsAnnotationComposer(
            $db: $db,
            $table: $db.canonicalEditIntents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mutationMappingHoldsRefs<T extends Object>(
    Expression<T> Function($MutationMappingHoldsAnnotationComposer a) f,
  ) {
    final $MutationMappingHoldsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.mutationMappingHolds,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationMappingHoldsAnnotationComposer(
            $db: $db,
            $table: $db.mutationMappingHolds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> snapshotDownloadsRefs<T extends Object>(
    Expression<T> Function($SnapshotDownloadsAnnotationComposer a) f,
  ) {
    final $SnapshotDownloadsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.snapshotDownloads,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SnapshotDownloadsAnnotationComposer(
            $db: $db,
            $table: $db.snapshotDownloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> snapshotDownloadRowsRefs<T extends Object>(
    Expression<T> Function($SnapshotDownloadRowsAnnotationComposer a) f,
  ) {
    final $SnapshotDownloadRowsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.snapshotDownloadRows,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SnapshotDownloadRowsAnnotationComposer(
            $db: $db,
            $table: $db.snapshotDownloadRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> snapshotBaselineRefs<T extends Object>(
    Expression<T> Function($SnapshotBaselineAnnotationComposer a) f,
  ) {
    final $SnapshotBaselineAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.snapshotBaseline,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SnapshotBaselineAnnotationComposer(
            $db: $db,
            $table: $db.snapshotBaseline,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mutationConflictResolutionsRefs<T extends Object>(
    Expression<T> Function($MutationConflictResolutionsAnnotationComposer a) f,
  ) {
    final $MutationConflictResolutionsAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.userId,
          referencedTable: $db.mutationConflictResolutions,
          getReferencedColumn: (t) => t.userId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $MutationConflictResolutionsAnnotationComposer(
                $db: $db,
                $table: $db.mutationConflictResolutions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> pendingEditResolutionsRefs<T extends Object>(
    Expression<T> Function($PendingEditResolutionsAnnotationComposer a) f,
  ) {
    final $PendingEditResolutionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.pendingEditResolutions,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $PendingEditResolutionsAnnotationComposer(
            $db: $db,
            $table: $db.pendingEditResolutions,
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
            bool recordingFollowupsRefs,
            bool songAliasesRefs,
            bool mutationSupersessionsRefs,
            bool canonicalEditIntentsRefs,
            bool mutationMappingHoldsRefs,
            bool snapshotDownloadsRefs,
            bool snapshotDownloadRowsRefs,
            bool snapshotBaselineRefs,
            bool mutationConflictResolutionsRefs,
            bool pendingEditResolutionsRefs,
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
                recordingFollowupsRefs = false,
                songAliasesRefs = false,
                mutationSupersessionsRefs = false,
                canonicalEditIntentsRefs = false,
                mutationMappingHoldsRefs = false,
                snapshotDownloadsRefs = false,
                snapshotDownloadRowsRefs = false,
                snapshotBaselineRefs = false,
                mutationConflictResolutionsRefs = false,
                pendingEditResolutionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (metadataCopiesRefs) db.metadataCopies,
                    if (localMutationsRefs) db.localMutations,
                    if (localRecordingFilesRefs) db.localRecordingFiles,
                    if (importJobsRefs) db.importJobs,
                    if (syncCursorsRefs) db.syncCursors,
                    if (recordingFollowupsRefs) db.recordingFollowups,
                    if (songAliasesRefs) db.songAliases,
                    if (mutationSupersessionsRefs) db.mutationSupersessions,
                    if (canonicalEditIntentsRefs) db.canonicalEditIntents,
                    if (mutationMappingHoldsRefs) db.mutationMappingHolds,
                    if (snapshotDownloadsRefs) db.snapshotDownloads,
                    if (snapshotDownloadRowsRefs) db.snapshotDownloadRows,
                    if (snapshotBaselineRefs) db.snapshotBaseline,
                    if (mutationConflictResolutionsRefs)
                      db.mutationConflictResolutions,
                    if (pendingEditResolutionsRefs) db.pendingEditResolutions,
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
                      if (recordingFollowupsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          RecordingFollowup
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._recordingFollowupsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).recordingFollowupsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (songAliasesRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          SongAliase
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._songAliasesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).songAliasesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (mutationSupersessionsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          MutationSupersession
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._mutationSupersessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).mutationSupersessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (canonicalEditIntentsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          CanonicalEditIntent
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._canonicalEditIntentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).canonicalEditIntentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (mutationMappingHoldsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          MutationMappingHold
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._mutationMappingHoldsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).mutationMappingHoldsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (snapshotDownloadsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          SnapshotDownload
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._snapshotDownloadsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).snapshotDownloadsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (snapshotDownloadRowsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          SnapshotDownloadRow
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._snapshotDownloadRowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).snapshotDownloadRowsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (snapshotBaselineRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          SnapshotBaselineData
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._snapshotBaselineRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).snapshotBaselineRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (mutationConflictResolutionsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          MutationConflictResolution
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._mutationConflictResolutionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).mutationConflictResolutionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (pendingEditResolutionsRefs)
                        await $_getPrefetchedData<
                          LocalAccountData,
                          LocalAccount,
                          PendingEditResolution
                        >(
                          currentTable: table,
                          referencedTable: $LocalAccountReferences
                              ._pendingEditResolutionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalAccountReferences(
                                db,
                                table,
                                p0,
                              ).pendingEditResolutionsRefs,
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
        bool recordingFollowupsRefs,
        bool songAliasesRefs,
        bool mutationSupersessionsRefs,
        bool canonicalEditIntentsRefs,
        bool mutationMappingHoldsRefs,
        bool snapshotDownloadsRefs,
        bool snapshotDownloadRowsRefs,
        bool snapshotBaselineRefs,
        bool mutationConflictResolutionsRefs,
        bool pendingEditResolutionsRefs,
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

  static MultiTypedResultKey<SongAliases, List<SongAliase>>
  _songAliasesRefsTable(_$AccountDatabase db) => MultiTypedResultKey.fromTable(
    db.songAliases,
    aliasName: 'local_mutations__op_id__song_aliases__mapping_op_id',
  );

  $SongAliasesProcessedTableManager get songAliasesRefs {
    final manager = $SongAliasesTableManager($_db, $_db.songAliases).filter(
      (f) => f.mappingOpId.opId.sqlEquals($_itemColumn<String>('op_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_songAliasesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<MutationMappingHolds, List<MutationMappingHold>>
  _mutationMappingHoldsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mutationMappingHolds,
        aliasName: 'local_mutations__op_id__mutation_mapping_holds__op_id',
      );

  $MutationMappingHoldsProcessedTableManager get mutationMappingHoldsRefs {
    final manager = $MutationMappingHoldsTableManager(
      $_db,
      $_db.mutationMappingHolds,
    ).filter((f) => f.opId.opId.sqlEquals($_itemColumn<String>('op_id')!));

    final cache = $_typedResult.readTableOrNull(
      _mutationMappingHoldsRefsTable($_db),
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

  Expression<bool> songAliasesRefs(
    Expression<bool> Function($SongAliasesFilterComposer f) f,
  ) {
    final $SongAliasesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.mappingOpId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesFilterComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mutationMappingHoldsRefs(
    Expression<bool> Function($MutationMappingHoldsFilterComposer f) f,
  ) {
    final $MutationMappingHoldsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.mutationMappingHolds,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationMappingHoldsFilterComposer(
            $db: $db,
            $table: $db.mutationMappingHolds,
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

  Expression<T> songAliasesRefs<T extends Object>(
    Expression<T> Function($SongAliasesAnnotationComposer a) f,
  ) {
    final $SongAliasesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.mappingOpId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesAnnotationComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mutationMappingHoldsRefs<T extends Object>(
    Expression<T> Function($MutationMappingHoldsAnnotationComposer a) f,
  ) {
    final $MutationMappingHoldsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opId,
      referencedTable: $db.mutationMappingHolds,
      getReferencedColumn: (t) => t.opId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationMappingHoldsAnnotationComposer(
            $db: $db,
            $table: $db.mutationMappingHolds,
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
            bool songAliasesRefs,
            bool mutationMappingHoldsRefs,
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
                songAliasesRefs = false,
                mutationMappingHoldsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mutationWireRequestsRefs) db.mutationWireRequests,
                    if (mutationRetryControlsRefs) db.mutationRetryControls,
                    if (songAliasesRefs) db.songAliases,
                    if (mutationMappingHoldsRefs) db.mutationMappingHolds,
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
                      if (songAliasesRefs)
                        await $_getPrefetchedData<
                          LocalMutation,
                          LocalMutations,
                          SongAliase
                        >(
                          currentTable: table,
                          referencedTable: $LocalMutationsReferences
                              ._songAliasesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalMutationsReferences(
                                db,
                                table,
                                p0,
                              ).songAliasesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.mappingOpId == item.opId,
                              ),
                          typedResults: items,
                        ),
                      if (mutationMappingHoldsRefs)
                        await $_getPrefetchedData<
                          LocalMutation,
                          LocalMutations,
                          MutationMappingHold
                        >(
                          currentTable: table,
                          referencedTable: $LocalMutationsReferences
                              ._mutationMappingHoldsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LocalMutationsReferences(
                                db,
                                table,
                                p0,
                              ).mutationMappingHoldsRefs,
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
        bool songAliasesRefs,
        bool mutationMappingHoldsRefs,
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
typedef $RecordingFollowupsCreateCompanionBuilder =
    RecordingFollowupsCompanion Function({
      required String originalOpId,
      required String replacementOpId,
      required String predecessorOpId,
      required String userId,
      required int logicalOrder,
      required int createdAt,
    });
typedef $RecordingFollowupsUpdateCompanionBuilder =
    RecordingFollowupsCompanion Function({
      Value<String> originalOpId,
      Value<String> replacementOpId,
      Value<String> predecessorOpId,
      Value<String> userId,
      Value<int> logicalOrder,
      Value<int> createdAt,
    });

final class $RecordingFollowupsReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          RecordingFollowups,
          RecordingFollowup
        > {
  $RecordingFollowupsReferences(super.$_db, super.$_table, super.$_typedResult);

  static LocalMutations _originalOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'recording_followups__original_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager get originalOpId {
    final $_column = $_itemColumn<String>('original_op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_originalOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalMutations _replacementOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'recording_followups__replacement_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager get replacementOpId {
    final $_column = $_itemColumn<String>('replacement_op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_replacementOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalMutations _predecessorOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'recording_followups__predecessor_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager get predecessorOpId {
    final $_column = $_itemColumn<String>('predecessor_op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_predecessorOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('recording_followups__user_id__local_account__user_id');

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

class $RecordingFollowupsFilterComposer
    extends Composer<_$AccountDatabase, RecordingFollowups> {
  $RecordingFollowupsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $LocalMutationsFilterComposer get originalOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsFilterComposer get replacementOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

  $LocalMutationsFilterComposer get predecessorOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.predecessorOpId,
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

class $RecordingFollowupsOrderingComposer
    extends Composer<_$AccountDatabase, RecordingFollowups> {
  $RecordingFollowupsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalMutationsOrderingComposer get originalOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsOrderingComposer get replacementOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

  $LocalMutationsOrderingComposer get predecessorOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.predecessorOpId,
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

class $RecordingFollowupsAnnotationComposer
    extends Composer<_$AccountDatabase, RecordingFollowups> {
  $RecordingFollowupsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $LocalMutationsAnnotationComposer get originalOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsAnnotationComposer get replacementOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

  $LocalMutationsAnnotationComposer get predecessorOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.predecessorOpId,
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

class $RecordingFollowupsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          RecordingFollowups,
          RecordingFollowup,
          $RecordingFollowupsFilterComposer,
          $RecordingFollowupsOrderingComposer,
          $RecordingFollowupsAnnotationComposer,
          $RecordingFollowupsCreateCompanionBuilder,
          $RecordingFollowupsUpdateCompanionBuilder,
          (RecordingFollowup, $RecordingFollowupsReferences),
          RecordingFollowup,
          PrefetchHooks Function({
            bool originalOpId,
            bool replacementOpId,
            bool predecessorOpId,
            bool userId,
          })
        > {
  $RecordingFollowupsTableManager(
    _$AccountDatabase db,
    RecordingFollowups table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $RecordingFollowupsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $RecordingFollowupsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $RecordingFollowupsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> originalOpId = const Value.absent(),
                Value<String> replacementOpId = const Value.absent(),
                Value<String> predecessorOpId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int> logicalOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => RecordingFollowupsCompanion(
                originalOpId: originalOpId,
                replacementOpId: replacementOpId,
                predecessorOpId: predecessorOpId,
                userId: userId,
                logicalOrder: logicalOrder,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                required String originalOpId,
                required String replacementOpId,
                required String predecessorOpId,
                required String userId,
                required int logicalOrder,
                required int createdAt,
              }) => RecordingFollowupsCompanion.insert(
                originalOpId: originalOpId,
                replacementOpId: replacementOpId,
                predecessorOpId: predecessorOpId,
                userId: userId,
                logicalOrder: logicalOrder,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<RecordingFollowups, RecordingFollowup>(table),
                  $RecordingFollowupsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                originalOpId = false,
                replacementOpId = false,
                predecessorOpId = false,
                userId = false,
              }) {
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
                        if (originalOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.originalOpId,
                            referencedTable: $RecordingFollowupsReferences
                                ._originalOpIdTable(db),
                            referencedColumn: $RecordingFollowupsReferences
                                ._originalOpIdTable(db)
                                .opId,
                          ) as T;
                        }
                        if (replacementOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.replacementOpId,
                            referencedTable: $RecordingFollowupsReferences
                                ._replacementOpIdTable(db),
                            referencedColumn: $RecordingFollowupsReferences
                                ._replacementOpIdTable(db)
                                .opId,
                          ) as T;
                        }
                        if (predecessorOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.predecessorOpId,
                            referencedTable: $RecordingFollowupsReferences
                                ._predecessorOpIdTable(db),
                            referencedColumn: $RecordingFollowupsReferences
                                ._predecessorOpIdTable(db)
                                .opId,
                          ) as T;
                        }
                        if (userId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.userId,
                            referencedTable: $RecordingFollowupsReferences
                                ._userIdTable(db),
                            referencedColumn: $RecordingFollowupsReferences
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

typedef $RecordingFollowupsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      RecordingFollowups,
      RecordingFollowup,
      $RecordingFollowupsFilterComposer,
      $RecordingFollowupsOrderingComposer,
      $RecordingFollowupsAnnotationComposer,
      $RecordingFollowupsCreateCompanionBuilder,
      $RecordingFollowupsUpdateCompanionBuilder,
      (RecordingFollowup, $RecordingFollowupsReferences),
      RecordingFollowup,
      PrefetchHooks Function({
        bool originalOpId,
        bool replacementOpId,
        bool predecessorOpId,
        bool userId,
      })
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
typedef $SongAliasesCreateCompanionBuilder = SongAliasesCompanion Function({
  required String sourceSongId,
  required String canonicalSongId,
  required String userId,
  Value<String> entityType,
  required String mappingOpId,
  required int receiptStatus,
  required String receiptBody,
  required int createdAt,
});
typedef $SongAliasesUpdateCompanionBuilder = SongAliasesCompanion Function({
  Value<String> sourceSongId,
  Value<String> canonicalSongId,
  Value<String> userId,
  Value<String> entityType,
  Value<String> mappingOpId,
  Value<int> receiptStatus,
  Value<String> receiptBody,
  Value<int> createdAt,
});

final class $SongAliasesReferences
    extends BaseReferences<_$AccountDatabase, SongAliases, SongAliase> {
  $SongAliasesReferences(super.$_db, super.$_table, super.$_typedResult);

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('song_aliases__user_id__local_account__user_id');

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

  static LocalMutations _mappingOpIdTable(_$AccountDatabase db) => db
      .localMutations
      .createAlias('song_aliases__mapping_op_id__local_mutations__op_id');

  $LocalMutationsProcessedTableManager get mappingOpId {
    final $_column = $_itemColumn<String>('mapping_op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mappingOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<MutationSupersessions, List<MutationSupersession>>
  _mutationSupersessionsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mutationSupersessions,
        aliasName: 'song_aliases__source_song_id__mutation_supersessions__mapping_source_id',
      );

  $MutationSupersessionsProcessedTableManager get mutationSupersessionsRefs {
    final manager =
        $MutationSupersessionsTableManager(
          $_db,
          $_db.mutationSupersessions,
        ).filter(
          (f) => f.mappingSourceId.sourceSongId.sqlEquals(
            $_itemColumn<String>('source_song_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _mutationSupersessionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<CanonicalEditIntents, List<CanonicalEditIntent>>
  _canonicalEditIntentsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.canonicalEditIntents,
        aliasName: 'song_aliases__source_song_id__canonical_edit_intents__mapping_source_id',
      );

  $CanonicalEditIntentsProcessedTableManager get canonicalEditIntentsRefs {
    final manager =
        $CanonicalEditIntentsTableManager(
          $_db,
          $_db.canonicalEditIntents,
        ).filter(
          (f) => f.mappingSourceId.sourceSongId.sqlEquals(
            $_itemColumn<String>('source_song_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _canonicalEditIntentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<MutationMappingHolds, List<MutationMappingHold>>
  _mutationMappingHoldsRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mutationMappingHolds,
        aliasName: 'song_aliases__source_song_id__mutation_mapping_holds__mapping_source_id',
      );

  $MutationMappingHoldsProcessedTableManager get mutationMappingHoldsRefs {
    final manager =
        $MutationMappingHoldsTableManager(
          $_db,
          $_db.mutationMappingHolds,
        ).filter(
          (f) => f.mappingSourceId.sourceSongId.sqlEquals(
            $_itemColumn<String>('source_song_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _mutationMappingHoldsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $SongAliasesFilterComposer
    extends Composer<_$AccountDatabase, SongAliases> {
  $SongAliasesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceSongId => $composableBuilder(
    column: $table.sourceSongId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get canonicalSongId => $composableBuilder(
    column: $table.canonicalSongId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receiptStatus => $composableBuilder(
    column: $table.receiptStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptBody => $composableBuilder(
    column: $table.receiptBody,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
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

  $LocalMutationsFilterComposer get mappingOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingOpId,
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

  Expression<bool> mutationSupersessionsRefs(
    Expression<bool> Function($MutationSupersessionsFilterComposer f) f,
  ) {
    final $MutationSupersessionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceSongId,
      referencedTable: $db.mutationSupersessions,
      getReferencedColumn: (t) => t.mappingSourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationSupersessionsFilterComposer(
            $db: $db,
            $table: $db.mutationSupersessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> canonicalEditIntentsRefs(
    Expression<bool> Function($CanonicalEditIntentsFilterComposer f) f,
  ) {
    final $CanonicalEditIntentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceSongId,
      referencedTable: $db.canonicalEditIntents,
      getReferencedColumn: (t) => t.mappingSourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CanonicalEditIntentsFilterComposer(
            $db: $db,
            $table: $db.canonicalEditIntents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mutationMappingHoldsRefs(
    Expression<bool> Function($MutationMappingHoldsFilterComposer f) f,
  ) {
    final $MutationMappingHoldsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceSongId,
      referencedTable: $db.mutationMappingHolds,
      getReferencedColumn: (t) => t.mappingSourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationMappingHoldsFilterComposer(
            $db: $db,
            $table: $db.mutationMappingHolds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $SongAliasesOrderingComposer
    extends Composer<_$AccountDatabase, SongAliases> {
  $SongAliasesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceSongId => $composableBuilder(
    column: $table.sourceSongId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get canonicalSongId => $composableBuilder(
    column: $table.canonicalSongId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receiptStatus => $composableBuilder(
    column: $table.receiptStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptBody => $composableBuilder(
    column: $table.receiptBody,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
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

  $LocalMutationsOrderingComposer get mappingOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingOpId,
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

class $SongAliasesAnnotationComposer
    extends Composer<_$AccountDatabase, SongAliases> {
  $SongAliasesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceSongId => $composableBuilder(
    column: $table.sourceSongId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get canonicalSongId => $composableBuilder(
    column: $table.canonicalSongId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get receiptStatus => $composableBuilder(
    column: $table.receiptStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get receiptBody => $composableBuilder(
    column: $table.receiptBody,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

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

  $LocalMutationsAnnotationComposer get mappingOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingOpId,
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

  Expression<T> mutationSupersessionsRefs<T extends Object>(
    Expression<T> Function($MutationSupersessionsAnnotationComposer a) f,
  ) {
    final $MutationSupersessionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceSongId,
      referencedTable: $db.mutationSupersessions,
      getReferencedColumn: (t) => t.mappingSourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationSupersessionsAnnotationComposer(
            $db: $db,
            $table: $db.mutationSupersessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> canonicalEditIntentsRefs<T extends Object>(
    Expression<T> Function($CanonicalEditIntentsAnnotationComposer a) f,
  ) {
    final $CanonicalEditIntentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceSongId,
      referencedTable: $db.canonicalEditIntents,
      getReferencedColumn: (t) => t.mappingSourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CanonicalEditIntentsAnnotationComposer(
            $db: $db,
            $table: $db.canonicalEditIntents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mutationMappingHoldsRefs<T extends Object>(
    Expression<T> Function($MutationMappingHoldsAnnotationComposer a) f,
  ) {
    final $MutationMappingHoldsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceSongId,
      referencedTable: $db.mutationMappingHolds,
      getReferencedColumn: (t) => t.mappingSourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationMappingHoldsAnnotationComposer(
            $db: $db,
            $table: $db.mutationMappingHolds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $SongAliasesTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          SongAliases,
          SongAliase,
          $SongAliasesFilterComposer,
          $SongAliasesOrderingComposer,
          $SongAliasesAnnotationComposer,
          $SongAliasesCreateCompanionBuilder,
          $SongAliasesUpdateCompanionBuilder,
          (SongAliase, $SongAliasesReferences),
          SongAliase,
          PrefetchHooks Function({
            bool userId,
            bool mappingOpId,
            bool mutationSupersessionsRefs,
            bool canonicalEditIntentsRefs,
            bool mutationMappingHoldsRefs,
          })
        > {
  $SongAliasesTableManager(_$AccountDatabase db, SongAliases table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SongAliasesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SongAliasesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SongAliasesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceSongId = const Value.absent(),
                Value<String> canonicalSongId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> mappingOpId = const Value.absent(),
                Value<int> receiptStatus = const Value.absent(),
                Value<String> receiptBody = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => SongAliasesCompanion(
                sourceSongId: sourceSongId,
                canonicalSongId: canonicalSongId,
                userId: userId,
                entityType: entityType,
                mappingOpId: mappingOpId,
                receiptStatus: receiptStatus,
                receiptBody: receiptBody,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                required String sourceSongId,
                required String canonicalSongId,
                required String userId,
                Value<String> entityType = const Value.absent(),
                required String mappingOpId,
                required int receiptStatus,
                required String receiptBody,
                required int createdAt,
              }) => SongAliasesCompanion.insert(
                sourceSongId: sourceSongId,
                canonicalSongId: canonicalSongId,
                userId: userId,
                entityType: entityType,
                mappingOpId: mappingOpId,
                receiptStatus: receiptStatus,
                receiptBody: receiptBody,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<SongAliases, SongAliase>(table),
                  $SongAliasesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                userId = false,
                mappingOpId = false,
                mutationSupersessionsRefs = false,
                canonicalEditIntentsRefs = false,
                mutationMappingHoldsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mutationSupersessionsRefs) db.mutationSupersessions,
                    if (canonicalEditIntentsRefs) db.canonicalEditIntents,
                    if (mutationMappingHoldsRefs) db.mutationMappingHolds,
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
                            referencedTable: $SongAliasesReferences
                                ._userIdTable(db),
                            referencedColumn: $SongAliasesReferences
                                ._userIdTable(db)
                                .userId,
                          ) as T;
                        }
                        if (mappingOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.mappingOpId,
                            referencedTable: $SongAliasesReferences
                                ._mappingOpIdTable(db),
                            referencedColumn: $SongAliasesReferences
                                ._mappingOpIdTable(db)
                                .opId,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (mutationSupersessionsRefs)
                        await $_getPrefetchedData<
                          SongAliase,
                          SongAliases,
                          MutationSupersession
                        >(
                          currentTable: table,
                          referencedTable: $SongAliasesReferences
                              ._mutationSupersessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $SongAliasesReferences(
                                db,
                                table,
                                p0,
                              ).mutationSupersessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.mappingSourceId == item.sourceSongId,
                              ),
                          typedResults: items,
                        ),
                      if (canonicalEditIntentsRefs)
                        await $_getPrefetchedData<
                          SongAliase,
                          SongAliases,
                          CanonicalEditIntent
                        >(
                          currentTable: table,
                          referencedTable: $SongAliasesReferences
                              ._canonicalEditIntentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $SongAliasesReferences(
                                db,
                                table,
                                p0,
                              ).canonicalEditIntentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.mappingSourceId == item.sourceSongId,
                              ),
                          typedResults: items,
                        ),
                      if (mutationMappingHoldsRefs)
                        await $_getPrefetchedData<
                          SongAliase,
                          SongAliases,
                          MutationMappingHold
                        >(
                          currentTable: table,
                          referencedTable: $SongAliasesReferences
                              ._mutationMappingHoldsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $SongAliasesReferences(
                                db,
                                table,
                                p0,
                              ).mutationMappingHoldsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.mappingSourceId == item.sourceSongId,
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

typedef $SongAliasesProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      SongAliases,
      SongAliase,
      $SongAliasesFilterComposer,
      $SongAliasesOrderingComposer,
      $SongAliasesAnnotationComposer,
      $SongAliasesCreateCompanionBuilder,
      $SongAliasesUpdateCompanionBuilder,
      (SongAliase, $SongAliasesReferences),
      SongAliase,
      PrefetchHooks Function({
        bool userId,
        bool mappingOpId,
        bool mutationSupersessionsRefs,
        bool canonicalEditIntentsRefs,
        bool mutationMappingHoldsRefs,
      })
    >;
typedef $MutationSupersessionsCreateCompanionBuilder =
    MutationSupersessionsCompanion Function({
      required String originalOpId,
      required String replacementOpId,
      required String mappingSourceId,
      required String userId,
      required String orderRootOpId,
      required int logicalOrder,
      required int createdAt,
    });
typedef $MutationSupersessionsUpdateCompanionBuilder =
    MutationSupersessionsCompanion Function({
      Value<String> originalOpId,
      Value<String> replacementOpId,
      Value<String> mappingSourceId,
      Value<String> userId,
      Value<String> orderRootOpId,
      Value<int> logicalOrder,
      Value<int> createdAt,
    });

final class $MutationSupersessionsReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          MutationSupersessions,
          MutationSupersession
        > {
  $MutationSupersessionsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static LocalMutations _originalOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'mutation_supersessions__original_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager get originalOpId {
    final $_column = $_itemColumn<String>('original_op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_originalOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalMutations _replacementOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'mutation_supersessions__replacement_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager get replacementOpId {
    final $_column = $_itemColumn<String>('replacement_op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_replacementOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static SongAliases _mappingSourceIdTable(
    _$AccountDatabase db,
  ) => db.songAliases.createAlias(
    'mutation_supersessions__mapping_source_id__song_aliases__source_song_id',
  );

  $SongAliasesProcessedTableManager get mappingSourceId {
    final $_column = $_itemColumn<String>('mapping_source_id')!;

    final manager = $SongAliasesTableManager(
      $_db,
      $_db.songAliases,
    ).filter((f) => f.sourceSongId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mappingSourceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('mutation_supersessions__user_id__local_account__user_id');

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

  static LocalMutations _orderRootOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'mutation_supersessions__order_root_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager get orderRootOpId {
    final $_column = $_itemColumn<String>('order_root_op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_orderRootOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $MutationSupersessionsFilterComposer
    extends Composer<_$AccountDatabase, MutationSupersessions> {
  $MutationSupersessionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $LocalMutationsFilterComposer get originalOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsFilterComposer get replacementOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

  $SongAliasesFilterComposer get mappingSourceId {
    final $SongAliasesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingSourceId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.sourceSongId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesFilterComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

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

  $LocalMutationsFilterComposer get orderRootOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderRootOpId,
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

class $MutationSupersessionsOrderingComposer
    extends Composer<_$AccountDatabase, MutationSupersessions> {
  $MutationSupersessionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalMutationsOrderingComposer get originalOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsOrderingComposer get replacementOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

  $SongAliasesOrderingComposer get mappingSourceId {
    final $SongAliasesOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingSourceId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.sourceSongId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesOrderingComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

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

  $LocalMutationsOrderingComposer get orderRootOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderRootOpId,
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

class $MutationSupersessionsAnnotationComposer
    extends Composer<_$AccountDatabase, MutationSupersessions> {
  $MutationSupersessionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $LocalMutationsAnnotationComposer get originalOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsAnnotationComposer get replacementOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

  $SongAliasesAnnotationComposer get mappingSourceId {
    final $SongAliasesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingSourceId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.sourceSongId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesAnnotationComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

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

  $LocalMutationsAnnotationComposer get orderRootOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderRootOpId,
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

class $MutationSupersessionsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          MutationSupersessions,
          MutationSupersession,
          $MutationSupersessionsFilterComposer,
          $MutationSupersessionsOrderingComposer,
          $MutationSupersessionsAnnotationComposer,
          $MutationSupersessionsCreateCompanionBuilder,
          $MutationSupersessionsUpdateCompanionBuilder,
          (MutationSupersession, $MutationSupersessionsReferences),
          MutationSupersession,
          PrefetchHooks Function({
            bool originalOpId,
            bool replacementOpId,
            bool mappingSourceId,
            bool userId,
            bool orderRootOpId,
          })
        > {
  $MutationSupersessionsTableManager(
    _$AccountDatabase db,
    MutationSupersessions table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MutationSupersessionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MutationSupersessionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MutationSupersessionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> originalOpId = const Value.absent(),
                Value<String> replacementOpId = const Value.absent(),
                Value<String> mappingSourceId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> orderRootOpId = const Value.absent(),
                Value<int> logicalOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => MutationSupersessionsCompanion(
                originalOpId: originalOpId,
                replacementOpId: replacementOpId,
                mappingSourceId: mappingSourceId,
                userId: userId,
                orderRootOpId: orderRootOpId,
                logicalOrder: logicalOrder,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                required String originalOpId,
                required String replacementOpId,
                required String mappingSourceId,
                required String userId,
                required String orderRootOpId,
                required int logicalOrder,
                required int createdAt,
              }) => MutationSupersessionsCompanion.insert(
                originalOpId: originalOpId,
                replacementOpId: replacementOpId,
                mappingSourceId: mappingSourceId,
                userId: userId,
                orderRootOpId: orderRootOpId,
                logicalOrder: logicalOrder,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<MutationSupersessions, MutationSupersession>(
                    table,
                  ),
                  $MutationSupersessionsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                originalOpId = false,
                replacementOpId = false,
                mappingSourceId = false,
                userId = false,
                orderRootOpId = false,
              }) {
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
                        if (originalOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.originalOpId,
                            referencedTable: $MutationSupersessionsReferences
                                ._originalOpIdTable(db),
                            referencedColumn: $MutationSupersessionsReferences
                                ._originalOpIdTable(db)
                                .opId,
                          ) as T;
                        }
                        if (replacementOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.replacementOpId,
                            referencedTable: $MutationSupersessionsReferences
                                ._replacementOpIdTable(db),
                            referencedColumn: $MutationSupersessionsReferences
                                ._replacementOpIdTable(db)
                                .opId,
                          ) as T;
                        }
                        if (mappingSourceId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.mappingSourceId,
                            referencedTable: $MutationSupersessionsReferences
                                ._mappingSourceIdTable(db),
                            referencedColumn: $MutationSupersessionsReferences
                                ._mappingSourceIdTable(db)
                                .sourceSongId,
                          ) as T;
                        }
                        if (userId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.userId,
                            referencedTable: $MutationSupersessionsReferences
                                ._userIdTable(db),
                            referencedColumn: $MutationSupersessionsReferences
                                ._userIdTable(db)
                                .userId,
                          ) as T;
                        }
                        if (orderRootOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.orderRootOpId,
                            referencedTable: $MutationSupersessionsReferences
                                ._orderRootOpIdTable(db),
                            referencedColumn: $MutationSupersessionsReferences
                                ._orderRootOpIdTable(db)
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

typedef $MutationSupersessionsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      MutationSupersessions,
      MutationSupersession,
      $MutationSupersessionsFilterComposer,
      $MutationSupersessionsOrderingComposer,
      $MutationSupersessionsAnnotationComposer,
      $MutationSupersessionsCreateCompanionBuilder,
      $MutationSupersessionsUpdateCompanionBuilder,
      (MutationSupersession, $MutationSupersessionsReferences),
      MutationSupersession,
      PrefetchHooks Function({
        bool originalOpId,
        bool replacementOpId,
        bool mappingSourceId,
        bool userId,
        bool orderRootOpId,
      })
    >;
typedef $CanonicalEditIntentsCreateCompanionBuilder =
    CanonicalEditIntentsCompanion Function({
      required String intentId,
      required String userId,
      required String mappingSourceId,
      required String intentKey,
      required String kind,
      required String entityType,
      required String entityId,
      Value<String?> originOpId,
      required String evidenceJson,
      Value<String> state,
      Value<String?> resolutionJson,
      Value<String?> resolutionOpId,
      Value<int?> resolvedAt,
      required int createdAt,
    });
typedef $CanonicalEditIntentsUpdateCompanionBuilder =
    CanonicalEditIntentsCompanion Function({
      Value<String> intentId,
      Value<String> userId,
      Value<String> mappingSourceId,
      Value<String> intentKey,
      Value<String> kind,
      Value<String> entityType,
      Value<String> entityId,
      Value<String?> originOpId,
      Value<String> evidenceJson,
      Value<String> state,
      Value<String?> resolutionJson,
      Value<String?> resolutionOpId,
      Value<int?> resolvedAt,
      Value<int> createdAt,
    });

final class $CanonicalEditIntentsReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          CanonicalEditIntents,
          CanonicalEditIntent
        > {
  $CanonicalEditIntentsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('canonical_edit_intents__user_id__local_account__user_id');

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

  static SongAliases _mappingSourceIdTable(
    _$AccountDatabase db,
  ) => db.songAliases.createAlias(
    'canonical_edit_intents__mapping_source_id__song_aliases__source_song_id',
  );

  $SongAliasesProcessedTableManager get mappingSourceId {
    final $_column = $_itemColumn<String>('mapping_source_id')!;

    final manager = $SongAliasesTableManager(
      $_db,
      $_db.songAliases,
    ).filter((f) => f.sourceSongId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mappingSourceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalMutations _originOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'canonical_edit_intents__origin_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager? get originOpId {
    final $_column = $_itemColumn<String>('origin_op_id');
    if ($_column == null) return null;
    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_originOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalMutations _resolutionOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'canonical_edit_intents__resolution_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager? get resolutionOpId {
    final $_column = $_itemColumn<String>('resolution_op_id');
    if ($_column == null) return null;
    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_resolutionOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<MutationMappingHolds, List<MutationMappingHold>>
  _mutationMappingHoldsRefsTable(
    _$AccountDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.mutationMappingHolds,
    aliasName:
        'canonical_edit_intents__intent_id__mutation_mapping_holds__intent_id',
  );

  $MutationMappingHoldsProcessedTableManager get mutationMappingHoldsRefs {
    final manager =
        $MutationMappingHoldsTableManager(
          $_db,
          $_db.mutationMappingHolds,
        ).filter(
          (f) =>
              f.intentId.intentId.sqlEquals($_itemColumn<String>('intent_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _mutationMappingHoldsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $CanonicalEditIntentsFilterComposer
    extends Composer<_$AccountDatabase, CanonicalEditIntents> {
  $CanonicalEditIntentsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get intentId => $composableBuilder(
    column: $table.intentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intentKey => $composableBuilder(
    column: $table.intentKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
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

  ColumnFilters<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolutionJson => $composableBuilder(
    column: $table.resolutionJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
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

  $SongAliasesFilterComposer get mappingSourceId {
    final $SongAliasesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingSourceId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.sourceSongId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesFilterComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $LocalMutationsFilterComposer get originOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originOpId,
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

  $LocalMutationsFilterComposer get resolutionOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.resolutionOpId,
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

  Expression<bool> mutationMappingHoldsRefs(
    Expression<bool> Function($MutationMappingHoldsFilterComposer f) f,
  ) {
    final $MutationMappingHoldsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.intentId,
      referencedTable: $db.mutationMappingHolds,
      getReferencedColumn: (t) => t.intentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationMappingHoldsFilterComposer(
            $db: $db,
            $table: $db.mutationMappingHolds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $CanonicalEditIntentsOrderingComposer
    extends Composer<_$AccountDatabase, CanonicalEditIntents> {
  $CanonicalEditIntentsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get intentId => $composableBuilder(
    column: $table.intentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intentKey => $composableBuilder(
    column: $table.intentKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
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

  ColumnOrderings<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolutionJson => $composableBuilder(
    column: $table.resolutionJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
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

  $SongAliasesOrderingComposer get mappingSourceId {
    final $SongAliasesOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingSourceId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.sourceSongId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesOrderingComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $LocalMutationsOrderingComposer get originOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originOpId,
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

  $LocalMutationsOrderingComposer get resolutionOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.resolutionOpId,
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

class $CanonicalEditIntentsAnnotationComposer
    extends Composer<_$AccountDatabase, CanonicalEditIntents> {
  $CanonicalEditIntentsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get intentId =>
      $composableBuilder(column: $table.intentId, builder: (column) => column);

  GeneratedColumn<String> get intentKey =>
      $composableBuilder(column: $table.intentKey, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get resolutionJson => $composableBuilder(
    column: $table.resolutionJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

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

  $SongAliasesAnnotationComposer get mappingSourceId {
    final $SongAliasesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingSourceId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.sourceSongId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesAnnotationComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $LocalMutationsAnnotationComposer get originOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originOpId,
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

  $LocalMutationsAnnotationComposer get resolutionOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.resolutionOpId,
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

  Expression<T> mutationMappingHoldsRefs<T extends Object>(
    Expression<T> Function($MutationMappingHoldsAnnotationComposer a) f,
  ) {
    final $MutationMappingHoldsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.intentId,
      referencedTable: $db.mutationMappingHolds,
      getReferencedColumn: (t) => t.intentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MutationMappingHoldsAnnotationComposer(
            $db: $db,
            $table: $db.mutationMappingHolds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $CanonicalEditIntentsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          CanonicalEditIntents,
          CanonicalEditIntent,
          $CanonicalEditIntentsFilterComposer,
          $CanonicalEditIntentsOrderingComposer,
          $CanonicalEditIntentsAnnotationComposer,
          $CanonicalEditIntentsCreateCompanionBuilder,
          $CanonicalEditIntentsUpdateCompanionBuilder,
          (CanonicalEditIntent, $CanonicalEditIntentsReferences),
          CanonicalEditIntent,
          PrefetchHooks Function({
            bool userId,
            bool mappingSourceId,
            bool originOpId,
            bool resolutionOpId,
            bool mutationMappingHoldsRefs,
          })
        > {
  $CanonicalEditIntentsTableManager(
    _$AccountDatabase db,
    CanonicalEditIntents table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $CanonicalEditIntentsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $CanonicalEditIntentsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $CanonicalEditIntentsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> intentId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> mappingSourceId = const Value.absent(),
                Value<String> intentKey = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String?> originOpId = const Value.absent(),
                Value<String> evidenceJson = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> resolutionJson = const Value.absent(),
                Value<String?> resolutionOpId = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => CanonicalEditIntentsCompanion(
                intentId: intentId,
                userId: userId,
                mappingSourceId: mappingSourceId,
                intentKey: intentKey,
                kind: kind,
                entityType: entityType,
                entityId: entityId,
                originOpId: originOpId,
                evidenceJson: evidenceJson,
                state: state,
                resolutionJson: resolutionJson,
                resolutionOpId: resolutionOpId,
                resolvedAt: resolvedAt,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                required String intentId,
                required String userId,
                required String mappingSourceId,
                required String intentKey,
                required String kind,
                required String entityType,
                required String entityId,
                Value<String?> originOpId = const Value.absent(),
                required String evidenceJson,
                Value<String> state = const Value.absent(),
                Value<String?> resolutionJson = const Value.absent(),
                Value<String?> resolutionOpId = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
                required int createdAt,
              }) => CanonicalEditIntentsCompanion.insert(
                intentId: intentId,
                userId: userId,
                mappingSourceId: mappingSourceId,
                intentKey: intentKey,
                kind: kind,
                entityType: entityType,
                entityId: entityId,
                originOpId: originOpId,
                evidenceJson: evidenceJson,
                state: state,
                resolutionJson: resolutionJson,
                resolutionOpId: resolutionOpId,
                resolvedAt: resolvedAt,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<CanonicalEditIntents, CanonicalEditIntent>(table),
                  $CanonicalEditIntentsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                userId = false,
                mappingSourceId = false,
                originOpId = false,
                resolutionOpId = false,
                mutationMappingHoldsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mutationMappingHoldsRefs) db.mutationMappingHolds,
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
                            referencedTable: $CanonicalEditIntentsReferences
                                ._userIdTable(db),
                            referencedColumn: $CanonicalEditIntentsReferences
                                ._userIdTable(db)
                                .userId,
                          ) as T;
                        }
                        if (mappingSourceId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.mappingSourceId,
                            referencedTable: $CanonicalEditIntentsReferences
                                ._mappingSourceIdTable(db),
                            referencedColumn: $CanonicalEditIntentsReferences
                                ._mappingSourceIdTable(db)
                                .sourceSongId,
                          ) as T;
                        }
                        if (originOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.originOpId,
                            referencedTable: $CanonicalEditIntentsReferences
                                ._originOpIdTable(db),
                            referencedColumn: $CanonicalEditIntentsReferences
                                ._originOpIdTable(db)
                                .opId,
                          ) as T;
                        }
                        if (resolutionOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.resolutionOpId,
                            referencedTable: $CanonicalEditIntentsReferences
                                ._resolutionOpIdTable(db),
                            referencedColumn: $CanonicalEditIntentsReferences
                                ._resolutionOpIdTable(db)
                                .opId,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (mutationMappingHoldsRefs)
                        await $_getPrefetchedData<
                          CanonicalEditIntent,
                          CanonicalEditIntents,
                          MutationMappingHold
                        >(
                          currentTable: table,
                          referencedTable: $CanonicalEditIntentsReferences
                              ._mutationMappingHoldsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $CanonicalEditIntentsReferences(
                                db,
                                table,
                                p0,
                              ).mutationMappingHoldsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.intentId == item.intentId,
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

typedef $CanonicalEditIntentsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      CanonicalEditIntents,
      CanonicalEditIntent,
      $CanonicalEditIntentsFilterComposer,
      $CanonicalEditIntentsOrderingComposer,
      $CanonicalEditIntentsAnnotationComposer,
      $CanonicalEditIntentsCreateCompanionBuilder,
      $CanonicalEditIntentsUpdateCompanionBuilder,
      (CanonicalEditIntent, $CanonicalEditIntentsReferences),
      CanonicalEditIntent,
      PrefetchHooks Function({
        bool userId,
        bool mappingSourceId,
        bool originOpId,
        bool resolutionOpId,
        bool mutationMappingHoldsRefs,
      })
    >;
typedef $MutationMappingHoldsCreateCompanionBuilder =
    MutationMappingHoldsCompanion Function({
      required String opId,
      required String mappingSourceId,
      required String userId,
      required String reason,
      required String disposition,
      Value<String?> intentId,
      required int createdAt,
      Value<int?> releasedAt,
      Value<String?> releaseEvidence,
    });
typedef $MutationMappingHoldsUpdateCompanionBuilder =
    MutationMappingHoldsCompanion Function({
      Value<String> opId,
      Value<String> mappingSourceId,
      Value<String> userId,
      Value<String> reason,
      Value<String> disposition,
      Value<String?> intentId,
      Value<int> createdAt,
      Value<int?> releasedAt,
      Value<String?> releaseEvidence,
    });

final class $MutationMappingHoldsReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          MutationMappingHolds,
          MutationMappingHold
        > {
  $MutationMappingHoldsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static LocalMutations _opIdTable(_$AccountDatabase db) => db.localMutations
      .createAlias('mutation_mapping_holds__op_id__local_mutations__op_id');

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

  static SongAliases _mappingSourceIdTable(
    _$AccountDatabase db,
  ) => db.songAliases.createAlias(
    'mutation_mapping_holds__mapping_source_id__song_aliases__source_song_id',
  );

  $SongAliasesProcessedTableManager get mappingSourceId {
    final $_column = $_itemColumn<String>('mapping_source_id')!;

    final manager = $SongAliasesTableManager(
      $_db,
      $_db.songAliases,
    ).filter((f) => f.sourceSongId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mappingSourceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('mutation_mapping_holds__user_id__local_account__user_id');

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

  static CanonicalEditIntents _intentIdTable(_$AccountDatabase db) =>
      db.canonicalEditIntents.createAlias(
        'mutation_mapping_holds__intent_id__canonical_edit_intents__intent_id',
      );

  $CanonicalEditIntentsProcessedTableManager? get intentId {
    final $_column = $_itemColumn<String>('intent_id');
    if ($_column == null) return null;
    final manager = $CanonicalEditIntentsTableManager(
      $_db,
      $_db.canonicalEditIntents,
    ).filter((f) => f.intentId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_intentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $MutationMappingHoldsFilterComposer
    extends Composer<_$AccountDatabase, MutationMappingHolds> {
  $MutationMappingHoldsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get disposition => $composableBuilder(
    column: $table.disposition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releaseEvidence => $composableBuilder(
    column: $table.releaseEvidence,
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

  $SongAliasesFilterComposer get mappingSourceId {
    final $SongAliasesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingSourceId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.sourceSongId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesFilterComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

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

  $CanonicalEditIntentsFilterComposer get intentId {
    final $CanonicalEditIntentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.intentId,
      referencedTable: $db.canonicalEditIntents,
      getReferencedColumn: (t) => t.intentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CanonicalEditIntentsFilterComposer(
            $db: $db,
            $table: $db.canonicalEditIntents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MutationMappingHoldsOrderingComposer
    extends Composer<_$AccountDatabase, MutationMappingHolds> {
  $MutationMappingHoldsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get disposition => $composableBuilder(
    column: $table.disposition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releaseEvidence => $composableBuilder(
    column: $table.releaseEvidence,
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

  $SongAliasesOrderingComposer get mappingSourceId {
    final $SongAliasesOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingSourceId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.sourceSongId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesOrderingComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

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

  $CanonicalEditIntentsOrderingComposer get intentId {
    final $CanonicalEditIntentsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.intentId,
      referencedTable: $db.canonicalEditIntents,
      getReferencedColumn: (t) => t.intentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CanonicalEditIntentsOrderingComposer(
            $db: $db,
            $table: $db.canonicalEditIntents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MutationMappingHoldsAnnotationComposer
    extends Composer<_$AccountDatabase, MutationMappingHolds> {
  $MutationMappingHoldsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get disposition => $composableBuilder(
    column: $table.disposition,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get releaseEvidence => $composableBuilder(
    column: $table.releaseEvidence,
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

  $SongAliasesAnnotationComposer get mappingSourceId {
    final $SongAliasesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mappingSourceId,
      referencedTable: $db.songAliases,
      getReferencedColumn: (t) => t.sourceSongId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SongAliasesAnnotationComposer(
            $db: $db,
            $table: $db.songAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

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

  $CanonicalEditIntentsAnnotationComposer get intentId {
    final $CanonicalEditIntentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.intentId,
      referencedTable: $db.canonicalEditIntents,
      getReferencedColumn: (t) => t.intentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CanonicalEditIntentsAnnotationComposer(
            $db: $db,
            $table: $db.canonicalEditIntents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MutationMappingHoldsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          MutationMappingHolds,
          MutationMappingHold,
          $MutationMappingHoldsFilterComposer,
          $MutationMappingHoldsOrderingComposer,
          $MutationMappingHoldsAnnotationComposer,
          $MutationMappingHoldsCreateCompanionBuilder,
          $MutationMappingHoldsUpdateCompanionBuilder,
          (MutationMappingHold, $MutationMappingHoldsReferences),
          MutationMappingHold,
          PrefetchHooks Function({
            bool opId,
            bool mappingSourceId,
            bool userId,
            bool intentId,
          })
        > {
  $MutationMappingHoldsTableManager(
    _$AccountDatabase db,
    MutationMappingHolds table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MutationMappingHoldsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MutationMappingHoldsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MutationMappingHoldsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> opId = const Value.absent(),
                Value<String> mappingSourceId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<String> disposition = const Value.absent(),
                Value<String?> intentId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> releasedAt = const Value.absent(),
                Value<String?> releaseEvidence = const Value.absent(),
              }) => MutationMappingHoldsCompanion(
                opId: opId,
                mappingSourceId: mappingSourceId,
                userId: userId,
                reason: reason,
                disposition: disposition,
                intentId: intentId,
                createdAt: createdAt,
                releasedAt: releasedAt,
                releaseEvidence: releaseEvidence,
              ),
          createCompanionCallback:
              ({
                required String opId,
                required String mappingSourceId,
                required String userId,
                required String reason,
                required String disposition,
                Value<String?> intentId = const Value.absent(),
                required int createdAt,
                Value<int?> releasedAt = const Value.absent(),
                Value<String?> releaseEvidence = const Value.absent(),
              }) => MutationMappingHoldsCompanion.insert(
                opId: opId,
                mappingSourceId: mappingSourceId,
                userId: userId,
                reason: reason,
                disposition: disposition,
                intentId: intentId,
                createdAt: createdAt,
                releasedAt: releasedAt,
                releaseEvidence: releaseEvidence,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<MutationMappingHolds, MutationMappingHold>(table),
                  $MutationMappingHoldsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                opId = false,
                mappingSourceId = false,
                userId = false,
                intentId = false,
              }) {
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
                            referencedTable: $MutationMappingHoldsReferences
                                ._opIdTable(db),
                            referencedColumn: $MutationMappingHoldsReferences
                                ._opIdTable(db)
                                .opId,
                          ) as T;
                        }
                        if (mappingSourceId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.mappingSourceId,
                            referencedTable: $MutationMappingHoldsReferences
                                ._mappingSourceIdTable(db),
                            referencedColumn: $MutationMappingHoldsReferences
                                ._mappingSourceIdTable(db)
                                .sourceSongId,
                          ) as T;
                        }
                        if (userId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.userId,
                            referencedTable: $MutationMappingHoldsReferences
                                ._userIdTable(db),
                            referencedColumn: $MutationMappingHoldsReferences
                                ._userIdTable(db)
                                .userId,
                          ) as T;
                        }
                        if (intentId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.intentId,
                            referencedTable: $MutationMappingHoldsReferences
                                ._intentIdTable(db),
                            referencedColumn: $MutationMappingHoldsReferences
                                ._intentIdTable(db)
                                .intentId,
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

typedef $MutationMappingHoldsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      MutationMappingHolds,
      MutationMappingHold,
      $MutationMappingHoldsFilterComposer,
      $MutationMappingHoldsOrderingComposer,
      $MutationMappingHoldsAnnotationComposer,
      $MutationMappingHoldsCreateCompanionBuilder,
      $MutationMappingHoldsUpdateCompanionBuilder,
      (MutationMappingHold, $MutationMappingHoldsReferences),
      MutationMappingHold,
      PrefetchHooks Function({
        bool opId,
        bool mappingSourceId,
        bool userId,
        bool intentId,
      })
    >;
typedef $SnapshotDownloadsCreateCompanionBuilder =
    SnapshotDownloadsCompanion Function({
      required String snapshotToken,
      required String userId,
      required String manifestJson,
      required int snapshotCursor,
      required int expiresAt,
      Value<String> state,
      required int createdAt,
      Value<int> rowid,
    });
typedef $SnapshotDownloadsUpdateCompanionBuilder =
    SnapshotDownloadsCompanion Function({
      Value<String> snapshotToken,
      Value<String> userId,
      Value<String> manifestJson,
      Value<int> snapshotCursor,
      Value<int> expiresAt,
      Value<String> state,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $SnapshotDownloadsReferences
    extends
        BaseReferences<_$AccountDatabase, SnapshotDownloads, SnapshotDownload> {
  $SnapshotDownloadsReferences(super.$_db, super.$_table, super.$_typedResult);

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('snapshot_downloads__user_id__local_account__user_id');

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

  static MultiTypedResultKey<
    SnapshotDownloadProgress,
    List<SnapshotDownloadProgressData>
  >
  _snapshotDownloadProgressRefsTable(_$AccountDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.snapshotDownloadProgress,
        aliasName: 'snapshot_downloads__snapshot_token__snapshot_download_progress__snapshot_token',
      );

  $SnapshotDownloadProgressProcessedTableManager
  get snapshotDownloadProgressRefs {
    final manager =
        $SnapshotDownloadProgressTableManager(
          $_db,
          $_db.snapshotDownloadProgress,
        ).filter(
          (f) => f.snapshotToken.snapshotToken.sqlEquals(
            $_itemColumn<String>('snapshot_token')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _snapshotDownloadProgressRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $SnapshotDownloadsFilterComposer
    extends Composer<_$AccountDatabase, SnapshotDownloads> {
  $SnapshotDownloadsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get snapshotToken => $composableBuilder(
    column: $table.snapshotToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snapshotCursor => $composableBuilder(
    column: $table.snapshotCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
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

  Expression<bool> snapshotDownloadProgressRefs(
    Expression<bool> Function($SnapshotDownloadProgressFilterComposer f) f,
  ) {
    final $SnapshotDownloadProgressFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotToken,
      referencedTable: $db.snapshotDownloadProgress,
      getReferencedColumn: (t) => t.snapshotToken,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SnapshotDownloadProgressFilterComposer(
            $db: $db,
            $table: $db.snapshotDownloadProgress,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $SnapshotDownloadsOrderingComposer
    extends Composer<_$AccountDatabase, SnapshotDownloads> {
  $SnapshotDownloadsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get snapshotToken => $composableBuilder(
    column: $table.snapshotToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snapshotCursor => $composableBuilder(
    column: $table.snapshotCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
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

class $SnapshotDownloadsAnnotationComposer
    extends Composer<_$AccountDatabase, SnapshotDownloads> {
  $SnapshotDownloadsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get snapshotToken => $composableBuilder(
    column: $table.snapshotToken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get snapshotCursor => $composableBuilder(
    column: $table.snapshotCursor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

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

  Expression<T> snapshotDownloadProgressRefs<T extends Object>(
    Expression<T> Function($SnapshotDownloadProgressAnnotationComposer a) f,
  ) {
    final $SnapshotDownloadProgressAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.snapshotToken,
          referencedTable: $db.snapshotDownloadProgress,
          getReferencedColumn: (t) => t.snapshotToken,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $SnapshotDownloadProgressAnnotationComposer(
                $db: $db,
                $table: $db.snapshotDownloadProgress,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $SnapshotDownloadsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          SnapshotDownloads,
          SnapshotDownload,
          $SnapshotDownloadsFilterComposer,
          $SnapshotDownloadsOrderingComposer,
          $SnapshotDownloadsAnnotationComposer,
          $SnapshotDownloadsCreateCompanionBuilder,
          $SnapshotDownloadsUpdateCompanionBuilder,
          (SnapshotDownload, $SnapshotDownloadsReferences),
          SnapshotDownload,
          PrefetchHooks Function({
            bool userId,
            bool snapshotDownloadProgressRefs,
          })
        > {
  $SnapshotDownloadsTableManager(_$AccountDatabase db, SnapshotDownloads table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SnapshotDownloadsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SnapshotDownloadsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SnapshotDownloadsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> snapshotToken = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> manifestJson = const Value.absent(),
                Value<int> snapshotCursor = const Value.absent(),
                Value<int> expiresAt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnapshotDownloadsCompanion(
                snapshotToken: snapshotToken,
                userId: userId,
                manifestJson: manifestJson,
                snapshotCursor: snapshotCursor,
                expiresAt: expiresAt,
                state: state,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String snapshotToken,
                required String userId,
                required String manifestJson,
                required int snapshotCursor,
                required int expiresAt,
                Value<String> state = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SnapshotDownloadsCompanion.insert(
                snapshotToken: snapshotToken,
                userId: userId,
                manifestJson: manifestJson,
                snapshotCursor: snapshotCursor,
                expiresAt: expiresAt,
                state: state,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<SnapshotDownloads, SnapshotDownload>(table),
                  $SnapshotDownloadsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({userId = false, snapshotDownloadProgressRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (snapshotDownloadProgressRefs)
                      db.snapshotDownloadProgress,
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
                            referencedTable: $SnapshotDownloadsReferences
                                ._userIdTable(db),
                            referencedColumn: $SnapshotDownloadsReferences
                                ._userIdTable(db)
                                .userId,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (snapshotDownloadProgressRefs)
                        await $_getPrefetchedData<
                          SnapshotDownload,
                          SnapshotDownloads,
                          SnapshotDownloadProgressData
                        >(
                          currentTable: table,
                          referencedTable: $SnapshotDownloadsReferences
                              ._snapshotDownloadProgressRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $SnapshotDownloadsReferences(
                                db,
                                table,
                                p0,
                              ).snapshotDownloadProgressRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.snapshotToken == item.snapshotToken,
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

typedef $SnapshotDownloadsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      SnapshotDownloads,
      SnapshotDownload,
      $SnapshotDownloadsFilterComposer,
      $SnapshotDownloadsOrderingComposer,
      $SnapshotDownloadsAnnotationComposer,
      $SnapshotDownloadsCreateCompanionBuilder,
      $SnapshotDownloadsUpdateCompanionBuilder,
      (SnapshotDownload, $SnapshotDownloadsReferences),
      SnapshotDownload,
      PrefetchHooks Function({bool userId, bool snapshotDownloadProgressRefs})
    >;
typedef $SnapshotDownloadRowsCreateCompanionBuilder =
    SnapshotDownloadRowsCompanion Function({
      required String snapshotToken,
      required String userId,
      required String entity,
      required int ordinal,
      required String resourceId,
      required String canonicalPayload,
      Value<int> rowid,
    });
typedef $SnapshotDownloadRowsUpdateCompanionBuilder =
    SnapshotDownloadRowsCompanion Function({
      Value<String> snapshotToken,
      Value<String> userId,
      Value<String> entity,
      Value<int> ordinal,
      Value<String> resourceId,
      Value<String> canonicalPayload,
      Value<int> rowid,
    });

final class $SnapshotDownloadRowsReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          SnapshotDownloadRows,
          SnapshotDownloadRow
        > {
  $SnapshotDownloadRowsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('snapshot_download_rows__user_id__local_account__user_id');

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

class $SnapshotDownloadRowsFilterComposer
    extends Composer<_$AccountDatabase, SnapshotDownloadRows> {
  $SnapshotDownloadRowsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get snapshotToken => $composableBuilder(
    column: $table.snapshotToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get canonicalPayload => $composableBuilder(
    column: $table.canonicalPayload,
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

class $SnapshotDownloadRowsOrderingComposer
    extends Composer<_$AccountDatabase, SnapshotDownloadRows> {
  $SnapshotDownloadRowsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get snapshotToken => $composableBuilder(
    column: $table.snapshotToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get canonicalPayload => $composableBuilder(
    column: $table.canonicalPayload,
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

class $SnapshotDownloadRowsAnnotationComposer
    extends Composer<_$AccountDatabase, SnapshotDownloadRows> {
  $SnapshotDownloadRowsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get snapshotToken => $composableBuilder(
    column: $table.snapshotToken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get canonicalPayload => $composableBuilder(
    column: $table.canonicalPayload,
    builder: (column) => column,
  );

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

class $SnapshotDownloadRowsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          SnapshotDownloadRows,
          SnapshotDownloadRow,
          $SnapshotDownloadRowsFilterComposer,
          $SnapshotDownloadRowsOrderingComposer,
          $SnapshotDownloadRowsAnnotationComposer,
          $SnapshotDownloadRowsCreateCompanionBuilder,
          $SnapshotDownloadRowsUpdateCompanionBuilder,
          (SnapshotDownloadRow, $SnapshotDownloadRowsReferences),
          SnapshotDownloadRow,
          PrefetchHooks Function({bool userId})
        > {
  $SnapshotDownloadRowsTableManager(
    _$AccountDatabase db,
    SnapshotDownloadRows table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SnapshotDownloadRowsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SnapshotDownloadRowsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SnapshotDownloadRowsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> snapshotToken = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> resourceId = const Value.absent(),
                Value<String> canonicalPayload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnapshotDownloadRowsCompanion(
                snapshotToken: snapshotToken,
                userId: userId,
                entity: entity,
                ordinal: ordinal,
                resourceId: resourceId,
                canonicalPayload: canonicalPayload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String snapshotToken,
                required String userId,
                required String entity,
                required int ordinal,
                required String resourceId,
                required String canonicalPayload,
                Value<int> rowid = const Value.absent(),
              }) => SnapshotDownloadRowsCompanion.insert(
                snapshotToken: snapshotToken,
                userId: userId,
                entity: entity,
                ordinal: ordinal,
                resourceId: resourceId,
                canonicalPayload: canonicalPayload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<SnapshotDownloadRows, SnapshotDownloadRow>(table),
                  $SnapshotDownloadRowsReferences(db, table, e),
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
                        referencedTable: $SnapshotDownloadRowsReferences
                            ._userIdTable(db),
                        referencedColumn: $SnapshotDownloadRowsReferences
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

typedef $SnapshotDownloadRowsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      SnapshotDownloadRows,
      SnapshotDownloadRow,
      $SnapshotDownloadRowsFilterComposer,
      $SnapshotDownloadRowsOrderingComposer,
      $SnapshotDownloadRowsAnnotationComposer,
      $SnapshotDownloadRowsCreateCompanionBuilder,
      $SnapshotDownloadRowsUpdateCompanionBuilder,
      (SnapshotDownloadRow, $SnapshotDownloadRowsReferences),
      SnapshotDownloadRow,
      PrefetchHooks Function({bool userId})
    >;
typedef $SnapshotDownloadProgressCreateCompanionBuilder =
    SnapshotDownloadProgressCompanion Function({
      required String snapshotToken,
      required String entity,
      required int lastOrdinal,
      Value<String?> nextCursor,
      required int finished,
      Value<int> rowid,
    });
typedef $SnapshotDownloadProgressUpdateCompanionBuilder =
    SnapshotDownloadProgressCompanion Function({
      Value<String> snapshotToken,
      Value<String> entity,
      Value<int> lastOrdinal,
      Value<String?> nextCursor,
      Value<int> finished,
      Value<int> rowid,
    });

final class $SnapshotDownloadProgressReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          SnapshotDownloadProgress,
          SnapshotDownloadProgressData
        > {
  $SnapshotDownloadProgressReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static SnapshotDownloads _snapshotTokenTable(_$AccountDatabase db) =>
      db.snapshotDownloads.createAlias(
        'snapshot_download_progress__snapshot_token__snapshot_downloads__snapshot_token',
      );

  $SnapshotDownloadsProcessedTableManager get snapshotToken {
    final $_column = $_itemColumn<String>('snapshot_token')!;

    final manager = $SnapshotDownloadsTableManager(
      $_db,
      $_db.snapshotDownloads,
    ).filter((f) => f.snapshotToken.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_snapshotTokenTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $SnapshotDownloadProgressFilterComposer
    extends Composer<_$AccountDatabase, SnapshotDownloadProgress> {
  $SnapshotDownloadProgressFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastOrdinal => $composableBuilder(
    column: $table.lastOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextCursor => $composableBuilder(
    column: $table.nextCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finished => $composableBuilder(
    column: $table.finished,
    builder: (column) => ColumnFilters(column),
  );

  $SnapshotDownloadsFilterComposer get snapshotToken {
    final $SnapshotDownloadsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotToken,
      referencedTable: $db.snapshotDownloads,
      getReferencedColumn: (t) => t.snapshotToken,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SnapshotDownloadsFilterComposer(
            $db: $db,
            $table: $db.snapshotDownloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SnapshotDownloadProgressOrderingComposer
    extends Composer<_$AccountDatabase, SnapshotDownloadProgress> {
  $SnapshotDownloadProgressOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastOrdinal => $composableBuilder(
    column: $table.lastOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextCursor => $composableBuilder(
    column: $table.nextCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finished => $composableBuilder(
    column: $table.finished,
    builder: (column) => ColumnOrderings(column),
  );

  $SnapshotDownloadsOrderingComposer get snapshotToken {
    final $SnapshotDownloadsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotToken,
      referencedTable: $db.snapshotDownloads,
      getReferencedColumn: (t) => t.snapshotToken,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SnapshotDownloadsOrderingComposer(
            $db: $db,
            $table: $db.snapshotDownloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SnapshotDownloadProgressAnnotationComposer
    extends Composer<_$AccountDatabase, SnapshotDownloadProgress> {
  $SnapshotDownloadProgressAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<int> get lastOrdinal => $composableBuilder(
    column: $table.lastOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nextCursor => $composableBuilder(
    column: $table.nextCursor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get finished =>
      $composableBuilder(column: $table.finished, builder: (column) => column);

  $SnapshotDownloadsAnnotationComposer get snapshotToken {
    final $SnapshotDownloadsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotToken,
      referencedTable: $db.snapshotDownloads,
      getReferencedColumn: (t) => t.snapshotToken,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SnapshotDownloadsAnnotationComposer(
            $db: $db,
            $table: $db.snapshotDownloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SnapshotDownloadProgressTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          SnapshotDownloadProgress,
          SnapshotDownloadProgressData,
          $SnapshotDownloadProgressFilterComposer,
          $SnapshotDownloadProgressOrderingComposer,
          $SnapshotDownloadProgressAnnotationComposer,
          $SnapshotDownloadProgressCreateCompanionBuilder,
          $SnapshotDownloadProgressUpdateCompanionBuilder,
          (SnapshotDownloadProgressData, $SnapshotDownloadProgressReferences),
          SnapshotDownloadProgressData,
          PrefetchHooks Function({bool snapshotToken})
        > {
  $SnapshotDownloadProgressTableManager(
    _$AccountDatabase db,
    SnapshotDownloadProgress table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SnapshotDownloadProgressFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SnapshotDownloadProgressOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SnapshotDownloadProgressAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> snapshotToken = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<int> lastOrdinal = const Value.absent(),
                Value<String?> nextCursor = const Value.absent(),
                Value<int> finished = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnapshotDownloadProgressCompanion(
                snapshotToken: snapshotToken,
                entity: entity,
                lastOrdinal: lastOrdinal,
                nextCursor: nextCursor,
                finished: finished,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String snapshotToken,
                required String entity,
                required int lastOrdinal,
                Value<String?> nextCursor = const Value.absent(),
                required int finished,
                Value<int> rowid = const Value.absent(),
              }) => SnapshotDownloadProgressCompanion.insert(
                snapshotToken: snapshotToken,
                entity: entity,
                lastOrdinal: lastOrdinal,
                nextCursor: nextCursor,
                finished: finished,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    SnapshotDownloadProgress,
                    SnapshotDownloadProgressData
                  >(table),
                  $SnapshotDownloadProgressReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({snapshotToken = false}) {
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
                    if (snapshotToken) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.snapshotToken,
                        referencedTable: $SnapshotDownloadProgressReferences
                            ._snapshotTokenTable(db),
                        referencedColumn: $SnapshotDownloadProgressReferences
                            ._snapshotTokenTable(db)
                            .snapshotToken,
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

typedef $SnapshotDownloadProgressProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      SnapshotDownloadProgress,
      SnapshotDownloadProgressData,
      $SnapshotDownloadProgressFilterComposer,
      $SnapshotDownloadProgressOrderingComposer,
      $SnapshotDownloadProgressAnnotationComposer,
      $SnapshotDownloadProgressCreateCompanionBuilder,
      $SnapshotDownloadProgressUpdateCompanionBuilder,
      (SnapshotDownloadProgressData, $SnapshotDownloadProgressReferences),
      SnapshotDownloadProgressData,
      PrefetchHooks Function({bool snapshotToken})
    >;
typedef $SnapshotBaselineCreateCompanionBuilder =
    SnapshotBaselineCompanion Function({
      Value<int> singleton,
      required String snapshotToken,
      required String userId,
    });
typedef $SnapshotBaselineUpdateCompanionBuilder =
    SnapshotBaselineCompanion Function({
      Value<int> singleton,
      Value<String> snapshotToken,
      Value<String> userId,
    });

final class $SnapshotBaselineReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          SnapshotBaseline,
          SnapshotBaselineData
        > {
  $SnapshotBaselineReferences(super.$_db, super.$_table, super.$_typedResult);

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('snapshot_baseline__user_id__local_account__user_id');

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

class $SnapshotBaselineFilterComposer
    extends Composer<_$AccountDatabase, SnapshotBaseline> {
  $SnapshotBaselineFilterComposer({
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

  ColumnFilters<String> get snapshotToken => $composableBuilder(
    column: $table.snapshotToken,
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

class $SnapshotBaselineOrderingComposer
    extends Composer<_$AccountDatabase, SnapshotBaseline> {
  $SnapshotBaselineOrderingComposer({
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

  ColumnOrderings<String> get snapshotToken => $composableBuilder(
    column: $table.snapshotToken,
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

class $SnapshotBaselineAnnotationComposer
    extends Composer<_$AccountDatabase, SnapshotBaseline> {
  $SnapshotBaselineAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singleton =>
      $composableBuilder(column: $table.singleton, builder: (column) => column);

  GeneratedColumn<String> get snapshotToken => $composableBuilder(
    column: $table.snapshotToken,
    builder: (column) => column,
  );

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

class $SnapshotBaselineTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          SnapshotBaseline,
          SnapshotBaselineData,
          $SnapshotBaselineFilterComposer,
          $SnapshotBaselineOrderingComposer,
          $SnapshotBaselineAnnotationComposer,
          $SnapshotBaselineCreateCompanionBuilder,
          $SnapshotBaselineUpdateCompanionBuilder,
          (SnapshotBaselineData, $SnapshotBaselineReferences),
          SnapshotBaselineData,
          PrefetchHooks Function({bool userId})
        > {
  $SnapshotBaselineTableManager(_$AccountDatabase db, SnapshotBaseline table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SnapshotBaselineFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SnapshotBaselineOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SnapshotBaselineAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                Value<String> snapshotToken = const Value.absent(),
                Value<String> userId = const Value.absent(),
              }) => SnapshotBaselineCompanion(
                singleton: singleton,
                snapshotToken: snapshotToken,
                userId: userId,
              ),
          createCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                required String snapshotToken,
                required String userId,
              }) => SnapshotBaselineCompanion.insert(
                singleton: singleton,
                snapshotToken: snapshotToken,
                userId: userId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<SnapshotBaseline, SnapshotBaselineData>(table),
                  $SnapshotBaselineReferences(db, table, e),
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
                        referencedTable: $SnapshotBaselineReferences
                            ._userIdTable(db),
                        referencedColumn: $SnapshotBaselineReferences
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

typedef $SnapshotBaselineProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      SnapshotBaseline,
      SnapshotBaselineData,
      $SnapshotBaselineFilterComposer,
      $SnapshotBaselineOrderingComposer,
      $SnapshotBaselineAnnotationComposer,
      $SnapshotBaselineCreateCompanionBuilder,
      $SnapshotBaselineUpdateCompanionBuilder,
      (SnapshotBaselineData, $SnapshotBaselineReferences),
      SnapshotBaselineData,
      PrefetchHooks Function({bool userId})
    >;
typedef $MutationConflictResolutionsCreateCompanionBuilder =
    MutationConflictResolutionsCompanion Function({
      required String originalOpId,
      required String userId,
      Value<String?> replacementOpId,
      required int originalAttemptCount,
      required int resolvedRevision,
      required String serverSnapshot,
      required String choices,
      required String orderRootOpId,
      required int logicalOrder,
      required int createdAt,
    });
typedef $MutationConflictResolutionsUpdateCompanionBuilder =
    MutationConflictResolutionsCompanion Function({
      Value<String> originalOpId,
      Value<String> userId,
      Value<String?> replacementOpId,
      Value<int> originalAttemptCount,
      Value<int> resolvedRevision,
      Value<String> serverSnapshot,
      Value<String> choices,
      Value<String> orderRootOpId,
      Value<int> logicalOrder,
      Value<int> createdAt,
    });

final class $MutationConflictResolutionsReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          MutationConflictResolutions,
          MutationConflictResolution
        > {
  $MutationConflictResolutionsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static LocalMutations _originalOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'mutation_conflict_resolutions__original_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager get originalOpId {
    final $_column = $_itemColumn<String>('original_op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_originalOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalAccount _userIdTable(_$AccountDatabase db) =>
      db.localAccount.createAlias(
        'mutation_conflict_resolutions__user_id__local_account__user_id',
      );

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

  static LocalMutations _replacementOpIdTable(
    _$AccountDatabase db,
  ) => db.localMutations.createAlias(
    'mutation_conflict_resolutions__replacement_op_id__local_mutations__op_id',
  );

  $LocalMutationsProcessedTableManager? get replacementOpId {
    final $_column = $_itemColumn<String>('replacement_op_id');
    if ($_column == null) return null;
    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_replacementOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalMutations _orderRootOpIdTable(
    _$AccountDatabase db,
  ) => db.localMutations.createAlias(
    'mutation_conflict_resolutions__order_root_op_id__local_mutations__op_id',
  );

  $LocalMutationsProcessedTableManager get orderRootOpId {
    final $_column = $_itemColumn<String>('order_root_op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_orderRootOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $MutationConflictResolutionsFilterComposer
    extends Composer<_$AccountDatabase, MutationConflictResolutions> {
  $MutationConflictResolutionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get originalAttemptCount => $composableBuilder(
    column: $table.originalAttemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolvedRevision => $composableBuilder(
    column: $table.resolvedRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverSnapshot => $composableBuilder(
    column: $table.serverSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get choices => $composableBuilder(
    column: $table.choices,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $LocalMutationsFilterComposer get originalOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsFilterComposer get replacementOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

  $LocalMutationsFilterComposer get orderRootOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderRootOpId,
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

class $MutationConflictResolutionsOrderingComposer
    extends Composer<_$AccountDatabase, MutationConflictResolutions> {
  $MutationConflictResolutionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get originalAttemptCount => $composableBuilder(
    column: $table.originalAttemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolvedRevision => $composableBuilder(
    column: $table.resolvedRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverSnapshot => $composableBuilder(
    column: $table.serverSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get choices => $composableBuilder(
    column: $table.choices,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalMutationsOrderingComposer get originalOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsOrderingComposer get replacementOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

  $LocalMutationsOrderingComposer get orderRootOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderRootOpId,
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

class $MutationConflictResolutionsAnnotationComposer
    extends Composer<_$AccountDatabase, MutationConflictResolutions> {
  $MutationConflictResolutionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get originalAttemptCount => $composableBuilder(
    column: $table.originalAttemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resolvedRevision => $composableBuilder(
    column: $table.resolvedRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverSnapshot => $composableBuilder(
    column: $table.serverSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get choices =>
      $composableBuilder(column: $table.choices, builder: (column) => column);

  GeneratedColumn<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $LocalMutationsAnnotationComposer get originalOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsAnnotationComposer get replacementOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

  $LocalMutationsAnnotationComposer get orderRootOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderRootOpId,
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

class $MutationConflictResolutionsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          MutationConflictResolutions,
          MutationConflictResolution,
          $MutationConflictResolutionsFilterComposer,
          $MutationConflictResolutionsOrderingComposer,
          $MutationConflictResolutionsAnnotationComposer,
          $MutationConflictResolutionsCreateCompanionBuilder,
          $MutationConflictResolutionsUpdateCompanionBuilder,
          (MutationConflictResolution, $MutationConflictResolutionsReferences),
          MutationConflictResolution,
          PrefetchHooks Function({
            bool originalOpId,
            bool userId,
            bool replacementOpId,
            bool orderRootOpId,
          })
        > {
  $MutationConflictResolutionsTableManager(
    _$AccountDatabase db,
    MutationConflictResolutions table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MutationConflictResolutionsFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $MutationConflictResolutionsOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $MutationConflictResolutionsAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> originalOpId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> replacementOpId = const Value.absent(),
                Value<int> originalAttemptCount = const Value.absent(),
                Value<int> resolvedRevision = const Value.absent(),
                Value<String> serverSnapshot = const Value.absent(),
                Value<String> choices = const Value.absent(),
                Value<String> orderRootOpId = const Value.absent(),
                Value<int> logicalOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => MutationConflictResolutionsCompanion(
                originalOpId: originalOpId,
                userId: userId,
                replacementOpId: replacementOpId,
                originalAttemptCount: originalAttemptCount,
                resolvedRevision: resolvedRevision,
                serverSnapshot: serverSnapshot,
                choices: choices,
                orderRootOpId: orderRootOpId,
                logicalOrder: logicalOrder,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                required String originalOpId,
                required String userId,
                Value<String?> replacementOpId = const Value.absent(),
                required int originalAttemptCount,
                required int resolvedRevision,
                required String serverSnapshot,
                required String choices,
                required String orderRootOpId,
                required int logicalOrder,
                required int createdAt,
              }) => MutationConflictResolutionsCompanion.insert(
                originalOpId: originalOpId,
                userId: userId,
                replacementOpId: replacementOpId,
                originalAttemptCount: originalAttemptCount,
                resolvedRevision: resolvedRevision,
                serverSnapshot: serverSnapshot,
                choices: choices,
                orderRootOpId: orderRootOpId,
                logicalOrder: logicalOrder,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    MutationConflictResolutions,
                    MutationConflictResolution
                  >(table),
                  $MutationConflictResolutionsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                originalOpId = false,
                userId = false,
                replacementOpId = false,
                orderRootOpId = false,
              }) {
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
                        if (originalOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.originalOpId,
                            referencedTable:
                                $MutationConflictResolutionsReferences
                                    ._originalOpIdTable(db),
                            referencedColumn:
                                $MutationConflictResolutionsReferences
                                    ._originalOpIdTable(db)
                                    .opId,
                          ) as T;
                        }
                        if (userId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.userId,
                            referencedTable:
                                $MutationConflictResolutionsReferences
                                    ._userIdTable(db),
                            referencedColumn:
                                $MutationConflictResolutionsReferences
                                    ._userIdTable(db)
                                    .userId,
                          ) as T;
                        }
                        if (replacementOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.replacementOpId,
                            referencedTable:
                                $MutationConflictResolutionsReferences
                                    ._replacementOpIdTable(db),
                            referencedColumn:
                                $MutationConflictResolutionsReferences
                                    ._replacementOpIdTable(db)
                                    .opId,
                          ) as T;
                        }
                        if (orderRootOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.orderRootOpId,
                            referencedTable:
                                $MutationConflictResolutionsReferences
                                    ._orderRootOpIdTable(db),
                            referencedColumn:
                                $MutationConflictResolutionsReferences
                                    ._orderRootOpIdTable(db)
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

typedef $MutationConflictResolutionsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      MutationConflictResolutions,
      MutationConflictResolution,
      $MutationConflictResolutionsFilterComposer,
      $MutationConflictResolutionsOrderingComposer,
      $MutationConflictResolutionsAnnotationComposer,
      $MutationConflictResolutionsCreateCompanionBuilder,
      $MutationConflictResolutionsUpdateCompanionBuilder,
      (MutationConflictResolution, $MutationConflictResolutionsReferences),
      MutationConflictResolution,
      PrefetchHooks Function({
        bool originalOpId,
        bool userId,
        bool replacementOpId,
        bool orderRootOpId,
      })
    >;
typedef $PendingEditResolutionsCreateCompanionBuilder =
    PendingEditResolutionsCompanion Function({
      required String originalOpId,
      required String userId,
      Value<String?> replacementOpId,
      required String serverSnapshot,
      required String choices,
      required String originalEvidence,
      required int logicalOrder,
      required int createdAt,
    });
typedef $PendingEditResolutionsUpdateCompanionBuilder =
    PendingEditResolutionsCompanion Function({
      Value<String> originalOpId,
      Value<String> userId,
      Value<String?> replacementOpId,
      Value<String> serverSnapshot,
      Value<String> choices,
      Value<String> originalEvidence,
      Value<int> logicalOrder,
      Value<int> createdAt,
    });

final class $PendingEditResolutionsReferences
    extends
        BaseReferences<
          _$AccountDatabase,
          PendingEditResolutions,
          PendingEditResolution
        > {
  $PendingEditResolutionsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static LocalMutations _originalOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'pending_edit_resolutions__original_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager get originalOpId {
    final $_column = $_itemColumn<String>('original_op_id')!;

    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_originalOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LocalAccount _userIdTable(_$AccountDatabase db) => db.localAccount
      .createAlias('pending_edit_resolutions__user_id__local_account__user_id');

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

  static LocalMutations _replacementOpIdTable(_$AccountDatabase db) =>
      db.localMutations.createAlias(
        'pending_edit_resolutions__replacement_op_id__local_mutations__op_id',
      );

  $LocalMutationsProcessedTableManager? get replacementOpId {
    final $_column = $_itemColumn<String>('replacement_op_id');
    if ($_column == null) return null;
    final manager = $LocalMutationsTableManager(
      $_db,
      $_db.localMutations,
    ).filter((f) => f.opId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_replacementOpIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $PendingEditResolutionsFilterComposer
    extends Composer<_$AccountDatabase, PendingEditResolutions> {
  $PendingEditResolutionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get serverSnapshot => $composableBuilder(
    column: $table.serverSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get choices => $composableBuilder(
    column: $table.choices,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalEvidence => $composableBuilder(
    column: $table.originalEvidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $LocalMutationsFilterComposer get originalOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsFilterComposer get replacementOpId {
    final $LocalMutationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

class $PendingEditResolutionsOrderingComposer
    extends Composer<_$AccountDatabase, PendingEditResolutions> {
  $PendingEditResolutionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get serverSnapshot => $composableBuilder(
    column: $table.serverSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get choices => $composableBuilder(
    column: $table.choices,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalEvidence => $composableBuilder(
    column: $table.originalEvidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $LocalMutationsOrderingComposer get originalOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsOrderingComposer get replacementOpId {
    final $LocalMutationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

class $PendingEditResolutionsAnnotationComposer
    extends Composer<_$AccountDatabase, PendingEditResolutions> {
  $PendingEditResolutionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get serverSnapshot => $composableBuilder(
    column: $table.serverSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get choices =>
      $composableBuilder(column: $table.choices, builder: (column) => column);

  GeneratedColumn<String> get originalEvidence => $composableBuilder(
    column: $table.originalEvidence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get logicalOrder => $composableBuilder(
    column: $table.logicalOrder,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $LocalMutationsAnnotationComposer get originalOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originalOpId,
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

  $LocalMutationsAnnotationComposer get replacementOpId {
    final $LocalMutationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.replacementOpId,
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

class $PendingEditResolutionsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          PendingEditResolutions,
          PendingEditResolution,
          $PendingEditResolutionsFilterComposer,
          $PendingEditResolutionsOrderingComposer,
          $PendingEditResolutionsAnnotationComposer,
          $PendingEditResolutionsCreateCompanionBuilder,
          $PendingEditResolutionsUpdateCompanionBuilder,
          (PendingEditResolution, $PendingEditResolutionsReferences),
          PendingEditResolution,
          PrefetchHooks Function({
            bool originalOpId,
            bool userId,
            bool replacementOpId,
          })
        > {
  $PendingEditResolutionsTableManager(
    _$AccountDatabase db,
    PendingEditResolutions table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $PendingEditResolutionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $PendingEditResolutionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $PendingEditResolutionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> originalOpId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> replacementOpId = const Value.absent(),
                Value<String> serverSnapshot = const Value.absent(),
                Value<String> choices = const Value.absent(),
                Value<String> originalEvidence = const Value.absent(),
                Value<int> logicalOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => PendingEditResolutionsCompanion(
                originalOpId: originalOpId,
                userId: userId,
                replacementOpId: replacementOpId,
                serverSnapshot: serverSnapshot,
                choices: choices,
                originalEvidence: originalEvidence,
                logicalOrder: logicalOrder,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                required String originalOpId,
                required String userId,
                Value<String?> replacementOpId = const Value.absent(),
                required String serverSnapshot,
                required String choices,
                required String originalEvidence,
                required int logicalOrder,
                required int createdAt,
              }) => PendingEditResolutionsCompanion.insert(
                originalOpId: originalOpId,
                userId: userId,
                replacementOpId: replacementOpId,
                serverSnapshot: serverSnapshot,
                choices: choices,
                originalEvidence: originalEvidence,
                logicalOrder: logicalOrder,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<PendingEditResolutions, PendingEditResolution>(
                    table,
                  ),
                  $PendingEditResolutionsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                originalOpId = false,
                userId = false,
                replacementOpId = false,
              }) {
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
                        if (originalOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.originalOpId,
                            referencedTable: $PendingEditResolutionsReferences
                                ._originalOpIdTable(db),
                            referencedColumn: $PendingEditResolutionsReferences
                                ._originalOpIdTable(db)
                                .opId,
                          ) as T;
                        }
                        if (userId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.userId,
                            referencedTable: $PendingEditResolutionsReferences
                                ._userIdTable(db),
                            referencedColumn: $PendingEditResolutionsReferences
                                ._userIdTable(db)
                                .userId,
                          ) as T;
                        }
                        if (replacementOpId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.replacementOpId,
                            referencedTable: $PendingEditResolutionsReferences
                                ._replacementOpIdTable(db),
                            referencedColumn: $PendingEditResolutionsReferences
                                ._replacementOpIdTable(db)
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

typedef $PendingEditResolutionsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      PendingEditResolutions,
      PendingEditResolution,
      $PendingEditResolutionsFilterComposer,
      $PendingEditResolutionsOrderingComposer,
      $PendingEditResolutionsAnnotationComposer,
      $PendingEditResolutionsCreateCompanionBuilder,
      $PendingEditResolutionsUpdateCompanionBuilder,
      (PendingEditResolution, $PendingEditResolutionsReferences),
      PendingEditResolution,
      PrefetchHooks Function({
        bool originalOpId,
        bool userId,
        bool replacementOpId,
      })
    >;
typedef $LocalUploadQueueCreateCompanionBuilder =
    LocalUploadQueueCompanion Function({
      required String recordingId,
      required String userId,
      required String operationId,
      Value<String?> renewOperationId,
      Value<String?> attemptId,
      required String phase,
      Value<String?> claimId,
      required int expectedSize,
      required String sha256,
      Value<int> automaticRetries,
      Value<int> attemptCount,
      Value<int?> nextAttemptAt,
      Value<String?> reason,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $LocalUploadQueueUpdateCompanionBuilder =
    LocalUploadQueueCompanion Function({
      Value<String> recordingId,
      Value<String> userId,
      Value<String> operationId,
      Value<String?> renewOperationId,
      Value<String?> attemptId,
      Value<String> phase,
      Value<String?> claimId,
      Value<int> expectedSize,
      Value<String> sha256,
      Value<int> automaticRetries,
      Value<int> attemptCount,
      Value<int?> nextAttemptAt,
      Value<String?> reason,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $LocalUploadQueueFilterComposer
    extends Composer<_$AccountDatabase, LocalUploadQueue> {
  $LocalUploadQueueFilterComposer({
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

  ColumnFilters<String> get renewOperationId => $composableBuilder(
    column: $table.renewOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get claimId => $composableBuilder(
    column: $table.claimId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedSize => $composableBuilder(
    column: $table.expectedSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get automaticRetries => $composableBuilder(
    column: $table.automaticRetries,
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

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
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
}

class $LocalUploadQueueOrderingComposer
    extends Composer<_$AccountDatabase, LocalUploadQueue> {
  $LocalUploadQueueOrderingComposer({
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

  ColumnOrderings<String> get renewOperationId => $composableBuilder(
    column: $table.renewOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get claimId => $composableBuilder(
    column: $table.claimId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedSize => $composableBuilder(
    column: $table.expectedSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get automaticRetries => $composableBuilder(
    column: $table.automaticRetries,
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

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
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
}

class $LocalUploadQueueAnnotationComposer
    extends Composer<_$AccountDatabase, LocalUploadQueue> {
  $LocalUploadQueueAnnotationComposer({
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

  GeneratedColumn<String> get renewOperationId => $composableBuilder(
    column: $table.renewOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attemptId =>
      $composableBuilder(column: $table.attemptId, builder: (column) => column);

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<String> get claimId =>
      $composableBuilder(column: $table.claimId, builder: (column) => column);

  GeneratedColumn<int> get expectedSize => $composableBuilder(
    column: $table.expectedSize,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get automaticRetries => $composableBuilder(
    column: $table.automaticRetries,
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

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $LocalUploadQueueTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          LocalUploadQueue,
          LocalUploadQueueData,
          $LocalUploadQueueFilterComposer,
          $LocalUploadQueueOrderingComposer,
          $LocalUploadQueueAnnotationComposer,
          $LocalUploadQueueCreateCompanionBuilder,
          $LocalUploadQueueUpdateCompanionBuilder,
          (
            LocalUploadQueueData,
            BaseReferences<
              _$AccountDatabase,
              LocalUploadQueue,
              LocalUploadQueueData
            >,
          ),
          LocalUploadQueueData,
          PrefetchHooks Function()
        > {
  $LocalUploadQueueTableManager(_$AccountDatabase db, LocalUploadQueue table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LocalUploadQueueFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LocalUploadQueueOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LocalUploadQueueAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> recordingId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<String?> renewOperationId = const Value.absent(),
                Value<String?> attemptId = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<String?> claimId = const Value.absent(),
                Value<int> expectedSize = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<int> automaticRetries = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int?> nextAttemptAt = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalUploadQueueCompanion(
                recordingId: recordingId,
                userId: userId,
                operationId: operationId,
                renewOperationId: renewOperationId,
                attemptId: attemptId,
                phase: phase,
                claimId: claimId,
                expectedSize: expectedSize,
                sha256: sha256,
                automaticRetries: automaticRetries,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                reason: reason,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recordingId,
                required String userId,
                required String operationId,
                Value<String?> renewOperationId = const Value.absent(),
                Value<String?> attemptId = const Value.absent(),
                required String phase,
                Value<String?> claimId = const Value.absent(),
                required int expectedSize,
                required String sha256,
                Value<int> automaticRetries = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int?> nextAttemptAt = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalUploadQueueCompanion.insert(
                recordingId: recordingId,
                userId: userId,
                operationId: operationId,
                renewOperationId: renewOperationId,
                attemptId: attemptId,
                phase: phase,
                claimId: claimId,
                expectedSize: expectedSize,
                sha256: sha256,
                automaticRetries: automaticRetries,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                reason: reason,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<LocalUploadQueue, LocalUploadQueueData>(table),
                  BaseReferences<
                    _$AccountDatabase,
                    LocalUploadQueue,
                    LocalUploadQueueData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $LocalUploadQueueProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      LocalUploadQueue,
      LocalUploadQueueData,
      $LocalUploadQueueFilterComposer,
      $LocalUploadQueueOrderingComposer,
      $LocalUploadQueueAnnotationComposer,
      $LocalUploadQueueCreateCompanionBuilder,
      $LocalUploadQueueUpdateCompanionBuilder,
      (
        LocalUploadQueueData,
        BaseReferences<
          _$AccountDatabase,
          LocalUploadQueue,
          LocalUploadQueueData
        >,
      ),
      LocalUploadQueueData,
      PrefetchHooks Function()
    >;
typedef $LocalCleanupConfirmationsCreateCompanionBuilder =
    LocalCleanupConfirmationsCompanion Function({
      required String token,
      required String userId,
      required String recordingId,
      required String generation,
      required String sha256,
      required int cloudRevision,
      required int expiresAt,
      required String state,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $LocalCleanupConfirmationsUpdateCompanionBuilder =
    LocalCleanupConfirmationsCompanion Function({
      Value<String> token,
      Value<String> userId,
      Value<String> recordingId,
      Value<String> generation,
      Value<String> sha256,
      Value<int> cloudRevision,
      Value<int> expiresAt,
      Value<String> state,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $LocalCleanupConfirmationsFilterComposer
    extends Composer<_$AccountDatabase, LocalCleanupConfirmations> {
  $LocalCleanupConfirmationsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
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
}

class $LocalCleanupConfirmationsOrderingComposer
    extends Composer<_$AccountDatabase, LocalCleanupConfirmations> {
  $LocalCleanupConfirmationsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
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
}

class $LocalCleanupConfirmationsAnnotationComposer
    extends Composer<_$AccountDatabase, LocalCleanupConfirmations> {
  $LocalCleanupConfirmationsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get token =>
      $composableBuilder(column: $table.token, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $LocalCleanupConfirmationsTableManager
    extends
        RootTableManager<
          _$AccountDatabase,
          LocalCleanupConfirmations,
          LocalCleanupConfirmation,
          $LocalCleanupConfirmationsFilterComposer,
          $LocalCleanupConfirmationsOrderingComposer,
          $LocalCleanupConfirmationsAnnotationComposer,
          $LocalCleanupConfirmationsCreateCompanionBuilder,
          $LocalCleanupConfirmationsUpdateCompanionBuilder,
          (
            LocalCleanupConfirmation,
            BaseReferences<
              _$AccountDatabase,
              LocalCleanupConfirmations,
              LocalCleanupConfirmation
            >,
          ),
          LocalCleanupConfirmation,
          PrefetchHooks Function()
        > {
  $LocalCleanupConfirmationsTableManager(
    _$AccountDatabase db,
    LocalCleanupConfirmations table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LocalCleanupConfirmationsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LocalCleanupConfirmationsOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $LocalCleanupConfirmationsAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> token = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> recordingId = const Value.absent(),
                Value<String> generation = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<int> cloudRevision = const Value.absent(),
                Value<int> expiresAt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCleanupConfirmationsCompanion(
                token: token,
                userId: userId,
                recordingId: recordingId,
                generation: generation,
                sha256: sha256,
                cloudRevision: cloudRevision,
                expiresAt: expiresAt,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String token,
                required String userId,
                required String recordingId,
                required String generation,
                required String sha256,
                required int cloudRevision,
                required int expiresAt,
                required String state,
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalCleanupConfirmationsCompanion.insert(
                token: token,
                userId: userId,
                recordingId: recordingId,
                generation: generation,
                sha256: sha256,
                cloudRevision: cloudRevision,
                expiresAt: expiresAt,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    LocalCleanupConfirmations,
                    LocalCleanupConfirmation
                  >(table),
                  BaseReferences<
                    _$AccountDatabase,
                    LocalCleanupConfirmations,
                    LocalCleanupConfirmation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $LocalCleanupConfirmationsProcessedTableManager =
    ProcessedTableManager<
      _$AccountDatabase,
      LocalCleanupConfirmations,
      LocalCleanupConfirmation,
      $LocalCleanupConfirmationsFilterComposer,
      $LocalCleanupConfirmationsOrderingComposer,
      $LocalCleanupConfirmationsAnnotationComposer,
      $LocalCleanupConfirmationsCreateCompanionBuilder,
      $LocalCleanupConfirmationsUpdateCompanionBuilder,
      (
        LocalCleanupConfirmation,
        BaseReferences<
          _$AccountDatabase,
          LocalCleanupConfirmations,
          LocalCleanupConfirmation
        >,
      ),
      LocalCleanupConfirmation,
      PrefetchHooks Function()
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
  $RecordingFollowupsTableManager get recordingFollowups =>
      $RecordingFollowupsTableManager(_db, _db.recordingFollowups);
  $MutationWireRequestsTableManager get mutationWireRequests =>
      $MutationWireRequestsTableManager(_db, _db.mutationWireRequests);
  $MutationRetryControlsTableManager get mutationRetryControls =>
      $MutationRetryControlsTableManager(_db, _db.mutationRetryControls);
  $SongAliasesTableManager get songAliases =>
      $SongAliasesTableManager(_db, _db.songAliases);
  $MutationSupersessionsTableManager get mutationSupersessions =>
      $MutationSupersessionsTableManager(_db, _db.mutationSupersessions);
  $CanonicalEditIntentsTableManager get canonicalEditIntents =>
      $CanonicalEditIntentsTableManager(_db, _db.canonicalEditIntents);
  $MutationMappingHoldsTableManager get mutationMappingHolds =>
      $MutationMappingHoldsTableManager(_db, _db.mutationMappingHolds);
  $SnapshotDownloadsTableManager get snapshotDownloads =>
      $SnapshotDownloadsTableManager(_db, _db.snapshotDownloads);
  $SnapshotDownloadRowsTableManager get snapshotDownloadRows =>
      $SnapshotDownloadRowsTableManager(_db, _db.snapshotDownloadRows);
  $SnapshotDownloadProgressTableManager get snapshotDownloadProgress =>
      $SnapshotDownloadProgressTableManager(_db, _db.snapshotDownloadProgress);
  $SnapshotBaselineTableManager get snapshotBaseline =>
      $SnapshotBaselineTableManager(_db, _db.snapshotBaseline);
  $MutationConflictResolutionsTableManager get mutationConflictResolutions =>
      $MutationConflictResolutionsTableManager(
        _db,
        _db.mutationConflictResolutions,
      );
  $PendingEditResolutionsTableManager get pendingEditResolutions =>
      $PendingEditResolutionsTableManager(_db, _db.pendingEditResolutions);
  $LocalUploadQueueTableManager get localUploadQueue =>
      $LocalUploadQueueTableManager(_db, _db.localUploadQueue);
  $LocalCleanupConfirmationsTableManager get localCleanupConfirmations =>
      $LocalCleanupConfirmationsTableManager(
        _db,
        _db.localCleanupConfirmations,
      );
}
