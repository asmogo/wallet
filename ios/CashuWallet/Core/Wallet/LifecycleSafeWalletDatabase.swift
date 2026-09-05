import Cdk
import Foundation

/// CDK 0.18.0-rc.3 owns a Tokio runtime in its SQLite FFI object. Its last
/// reference can be released by a native rate-limit writer, where shutting
/// down that runtime panics. Hold an extra native reference through the inherited
/// destructor, then release it on a Dispatch worker outside Tokio.
/// This can be removed once CDK's RuntimeGuard supports async-context teardown.
final class LifecycleSafeWalletDatabase: WalletSqliteDatabase, @unchecked Sendable {
    private var runtimeLifetime: DatabaseRuntimeLifetime?

    required init(unsafeFromHandle handle: UInt64) {
        super.init(unsafeFromHandle: handle)
        runtimeLifetime = DatabaseRuntimeLifetime(
            database: WalletSqliteDatabase(unsafeFromHandle: uniffiCloneHandle())
        )
    }

    convenience init(filePath: String) throws {
        let database = try WalletSqliteDatabase(filePath: filePath)
        self.init(unsafeFromHandle: database.uniffiCloneHandle())
    }
}

/// Subclass properties are destroyed after the superclass destructor. Transfer
/// ownership explicitly so no automatic local release can race the queued one.
private final class DatabaseRuntimeLifetime {
    private let retainedDatabase: Unmanaged<WalletSqliteDatabase>

    init(database: WalletSqliteDatabase) {
        retainedDatabase = .passRetained(database)
    }

    deinit {
        let retainedDatabase = retainedDatabase
        DispatchQueue.global(qos: .utility).async { retainedDatabase.release() }
    }
}
