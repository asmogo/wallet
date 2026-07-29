package com.cashu.me.Core.CDK

/**
 * Complete native-wallet boundary used by the application container.
 *
 * Keeping CDK and NWC behind one interface lets instrumentation install a
 * deterministic stateful gateway without replacing the production UI or
 * introducing a second dependency-injection framework.
 */
interface WalletGateway : CdkWalletGateway, NwcServiceGateway
