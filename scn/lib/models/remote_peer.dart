import 'dart:convert';

/// Remote peer connection type
enum PeerType {
  local,   // Discovered via multicast (LAN)
  remote,  // Connected via secure channel (WAN)
}

/// Connection status
enum PeerStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Remote peer model
class RemotePeer {
  final String id;
  final String alias;
  final String address;  // IP or hostname
  final int port;
  final PeerType type;
  final PeerStatus status;
  final String? fingerprint;  // For certificate verification
  final DateTime? lastSeen;
  final bool isFavorite;
  final String? errorMessage;
  
  /// Peers that this peer knows about (for mesh network)
  final List<String> knownPeers;
  
  RemotePeer({
    required this.id,
    required this.alias,
    required this.address,
    required this.port,
    this.type = PeerType.remote,
    this.status = PeerStatus.disconnected,
    this.fingerprint,
    this.lastSeen,
    this.isFavorite = false,
    this.errorMessage,
    this.knownPeers = const [],
  });
  
  String get url => 'https://$address:$port';
  String get wsUrl => 'wss://$address:$port/ws';
  
  RemotePeer copyWith({
    String? id,
    String? alias,
    String? address,
    int? port,
    PeerType? type,
    PeerStatus? status,
    String? fingerprint,
    DateTime? lastSeen,
    bool? isFavorite,
    String? errorMessage,
    List<String>? knownPeers,
  }) {
    return RemotePeer(
      id: id ?? this.id,
      alias: alias ?? this.alias,
      address: address ?? this.address,
      port: port ?? this.port,
      type: type ?? this.type,
      status: status ?? this.status,
      fingerprint: fingerprint ?? this.fingerprint,
      lastSeen: lastSeen ?? this.lastSeen,
      isFavorite: isFavorite ?? this.isFavorite,
      errorMessage: errorMessage ?? this.errorMessage,
      knownPeers: knownPeers ?? this.knownPeers,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'alias': alias,
    'address': address,
    'port': port,
    'type': type.name,
    'fingerprint': fingerprint,
    'lastSeen': lastSeen?.toIso8601String(),
    'isFavorite': isFavorite,
    'knownPeers': knownPeers,
  };
  
  factory RemotePeer.fromJson(Map<String, dynamic> json) {
    return RemotePeer(
      id: json['id'] as String,
      alias: json['alias'] as String,
      address: json['address'] as String,
      port: json['port'] as int,
      type: PeerType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => PeerType.remote,
      ),
      fingerprint: json['fingerprint'] as String?,
      lastSeen: json['lastSeen'] != null 
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
      isFavorite: json['isFavorite'] as bool? ?? false,
      knownPeers: (json['knownPeers'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
    );
  }
  
  @override
  String toString() => 'RemotePeer($alias @ $address:$port, $status)';
}

/// Network settings for mesh network
class NetworkSettings {
  final bool meshEnabled;          // Allow mesh network propagation
  final bool sharePeers;           // Share my peers with others
  final bool acceptWithoutPassword; // Accept connections without password
  final String? connectionPassword; // Optional password for connections
  final int securePort;            // Port for secure WebSocket server
  
  const NetworkSettings({
    this.meshEnabled = true,
    this.sharePeers = true,
    this.acceptWithoutPassword = true,
    this.connectionPassword,
    this.securePort = 53318,
  });
  
  NetworkSettings copyWith({
    bool? meshEnabled,
    bool? sharePeers,
    bool? acceptWithoutPassword,
    String? connectionPassword,
    int? securePort,
  }) {
    return NetworkSettings(
      meshEnabled: meshEnabled ?? this.meshEnabled,
      sharePeers: sharePeers ?? this.sharePeers,
      acceptWithoutPassword: acceptWithoutPassword ?? this.acceptWithoutPassword,
      connectionPassword: connectionPassword ?? this.connectionPassword,
      securePort: securePort ?? this.securePort,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'meshEnabled': meshEnabled,
    'sharePeers': sharePeers,
    'acceptWithoutPassword': acceptWithoutPassword,
    'connectionPassword': connectionPassword,
    'securePort': securePort,
  };
  
  factory NetworkSettings.fromJson(Map<String, dynamic> json) {
    return NetworkSettings(
      meshEnabled: json['meshEnabled'] as bool? ?? true,
      sharePeers: json['sharePeers'] as bool? ?? true,
      acceptWithoutPassword: json['acceptWithoutPassword'] as bool? ?? true,
      connectionPassword: json['connectionPassword'] as String?,
      securePort: json['securePort'] as int? ?? 53318,
    );
  }
}

/// Invitation to join network
class PeerInvitation {
  final String id;
  final String fromAlias;
  final String fromAddress;
  final int fromPort;
  final String? fingerprint;
  final DateTime timestamp;
  final bool requiresPassword;
  
  PeerInvitation({
    required this.id,
    required this.fromAlias,
    required this.fromAddress,
    required this.fromPort,
    this.fingerprint,
    DateTime? timestamp,
    this.requiresPassword = false,
  }) : timestamp = timestamp ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'fromAlias': fromAlias,
    'fromAddress': fromAddress,
    'fromPort': fromPort,
    'fingerprint': fingerprint,
    'timestamp': timestamp.toIso8601String(),
    'requiresPassword': requiresPassword,
  };
  
  factory PeerInvitation.fromJson(Map<String, dynamic> json) {
    return PeerInvitation(
      id: json['id'] as String,
      fromAlias: json['fromAlias'] as String,
      fromAddress: json['fromAddress'] as String,
      fromPort: json['fromPort'] as int,
      fingerprint: json['fingerprint'] as String?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      requiresPassword: json['requiresPassword'] as bool? ?? false,
    );
  }
}

/// Message types for secure channel protocol
enum SecureMessageType {
  handshake,      // Initial connection
  handshakeAck,   // Handshake acknowledgment
  peerList,       // Share peer list (mesh)
  peerUpdate,     // Peer status update
  invitation,     // Connection invitation
  invitationAck,  // Accept/reject invitation
  data,           // Actual data transfer
  ping,           // Keep-alive
  pong,           // Keep-alive response
  disconnect,     // Graceful disconnect
}

/// Secure channel message
class SecureMessage {
  final SecureMessageType type;
  final String? senderId;
  final String? senderAlias;
  final Map<String, dynamic>? payload;
  final DateTime timestamp;
  
  SecureMessage({
    required this.type,
    this.senderId,
    this.senderAlias,
    this.payload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'senderId': senderId,
    'senderAlias': senderAlias,
    'payload': payload,
    'timestamp': timestamp.toIso8601String(),
  };
  
  String toJsonString() => jsonEncode(toJson());
  
  factory SecureMessage.fromJson(Map<String, dynamic> json) {
    return SecureMessage(
      type: SecureMessageType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => SecureMessageType.data,
      ),
      senderId: json['senderId'] as String?,
      senderAlias: json['senderAlias'] as String?,
      payload: json['payload'] as Map<String, dynamic>?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }
  
  factory SecureMessage.fromJsonString(String jsonString) {
    return SecureMessage.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }
}

